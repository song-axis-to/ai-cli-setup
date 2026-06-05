# Claude Code Multi-Session Cockpit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give 15+ parallel Claude Code sessions a cockpit — a dashboard pane, notifications, jump-to-session, error/stuck detection, and a rich statusLine — all driven by one shared session-state store.

**Architecture:** Each session's lifecycle hooks write a JSON state file under `~/.claude/cc-sessions/`. A polling TUI (`cc-monitor`) in a dedicated iTerm pane reads them all, renders a sorted list, focuses tabs via AppleScript, runs the stuck watchdog, and fires notifications on state transitions. Shared shell helpers live in `cc-lib.sh`. All workplace-specific data (type mappings, error patterns, Telegram token) stays in gitignored local files.

**Tech Stack:** Bash, `jq`, iTerm2 OSC escapes + AppleScript, macOS `osascript`, Telegram Bot API via `curl`. Tests are bash assertion scripts (synthesize hook stdin / state files).

Repo: `~/Workspace/ai-cli-setup`. Spec: `docs/specs/2026-06-05-multi-session-cockpit-design.md`.

---

## File structure

```
claude/
  hooks/
    cc-lib.sh            # NEW shared: resolve_tty, type_for, color_for, glyph_for, paint_tab
    iterm-tab.sh         # REFACTOR: source cc-lib.sh (thin wrapper)
    cc-hook.sh           # NEW: write state file + paint tab (Phase 1)
    cc-error-scan.sh     # NEW: PostToolUse error matcher (Phase 3)
  bin/
    cc-monitor           # NEW: dashboard TUI + watchdog + notifier driver
    focus_session.applescript  # NEW: focus iTerm session by tty
    cc-notify.sh         # NEW: macOS + Telegram notifier (Phase 2)
    cc-statusline.sh     # NEW: statusLine renderer (Phase 3)
  cc-notify.env.example          # NEW
  cc-error-patterns.example.txt  # NEW
  settings.snippet.json # MODIFY: hooks → cc-hook.sh (+CC_EVENT), +PostToolUse, +statusLine
  install.sh            # MODIFY: install bin/, examples; keep settings merge
tests/
  test-cc-lib.sh        # NEW
  test-cc-hook.sh       # NEW
  test-cc-monitor.sh    # NEW
  test-cc-notify.sh     # NEW (Phase 2)
  test-cc-error-scan.sh # NEW (Phase 3)
  test-cc-statusline.sh # NEW (Phase 3)
.gitignore              # MODIFY: cc-notify.env, cc-error-patterns.txt
```

Local-only (gitignored, created by user/installer, never committed):
`~/.claude/cc-tab-overrides.sh`, `~/.claude/cc-notify.env`, `~/.claude/cc-error-patterns.txt`, `~/.claude/cc-sessions/`.

---

# PHASE 1 — Core: state store + dashboard + jump + watchdog

## Task 1: Shared library `cc-lib.sh` (+ refactor `iterm-tab.sh`)

**Files:**
- Create: `claude/hooks/cc-lib.sh`
- Modify: `claude/hooks/iterm-tab.sh` (source the lib)
- Test: `tests/test-cc-lib.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-cc-lib.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "$0")/../claude/hooks" && pwd)"
HOME=/nonexistent-home . "$DIR/cc-lib.sh"   # no override file → generic
fail=0
chk(){ [ "$2" = "$3" ] || { echo "FAIL $1: got '$2' want '$3'"; fail=1; }; }

chk type_api   "$(type_for my-api)"      "api"
chk type_db    "$(type_for payments-db)" "db"
chk type_other "$(type_for randomthing)" "randomthing"
chk color_api  "$(color_for api)"        "40 110 230"
chk color_def  "$(color_for nope)"       "120 120 120"
chk glyph_wait "$(glyph_for waiting)"    "◆"

# paint writes 4 OSC sequences to the target
out="$(mktemp)"; cc_paint_tab working api "$out"
n=$(grep -c $'\a' "$out"); chk paint_seqs "$n" "4"
# waiting overrides red channel to 240
cc_paint_tab waiting api "$out"; grep -q 'red;brightness;240' "$out" || { echo "FAIL waiting override"; fail=1; }
rm -f "$out"
[ $fail -eq 0 ] && echo "ALL PASS"; exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-cc-lib.sh`
Expected: FAIL (cc-lib.sh does not exist → source error).

- [ ] **Step 3: Write `cc-lib.sh`**

Create `claude/hooks/cc-lib.sh`:

```bash
#!/usr/bin/env bash
# cc-lib.sh — shared helpers for cockpit hooks. SOURCE this; don't execute.

# Resolve the iTerm pane tty by walking the process tree (claude runs hooks
# without a controlling tty, esp. over SSH). CLAUDE_ITERM_TTY overrides (tests).
cc_resolve_tty() {
  [ -n "${CLAUDE_ITERM_TTY:-}" ] && { printf '%s' "$CLAUDE_ITERM_TTY"; return; }
  local pid="$$" ppid t
  while [ "${pid:-0}" -gt 1 ]; do
    read -r ppid t <<<"$(ps -o ppid=,tty= -p "$pid" 2>/dev/null)"
    case "$t" in ttys*) printf '/dev/%s' "$t"; return ;; esac
    pid="$ppid"
  done
  printf '/dev/tty'
}

# Map a directory basename to a short work "type" (generic examples).
type_for() {
  case "$1" in
    *-api|*api*)   echo api    ;;
    *-web|*web*)   echo web    ;;
    *worker*)      echo worker ;;
    *data*)        echo data   ;;
    *db*|*migrat*) echo db     ;;
    *infra*)       echo infra  ;;
    *docs*)        echo docs   ;;
    *)             echo "$1"   ;;
  esac
}

# Map a type to a tab color "R G B".
color_for() {
  case "$1" in
    api)    echo "40 110 230"  ;;
    web)    echo "40 170 80"   ;;
    worker) echo "150 80 220"  ;;
    data)   echo "0 170 180"   ;;
    db)     echo "230 130 0"   ;;
    infra)  echo "200 160 0"   ;;
    docs)   echo "210 60 160"  ;;
    *)      echo "120 120 120" ;;
  esac
}

# Badge glyph per session state.
glyph_for() {
  case "$1" in
    working) echo "●" ;; waiting) echo "◆" ;; done) echo "✓" ;;
    error)   echo "✗" ;; *) echo "·" ;;
  esac
}

# Private overrides (not committed): may redefine type_for / color_for.
[ -f "$HOME/.claude/cc-tab-overrides.sh" ] && . "$HOME/.claude/cc-tab-overrides.sh"

# Paint iTerm tab color (OSC 6) + badge (OSC 1337) for (state,type) to a tty.
# No-op if the tty can't be opened. "waiting" overrides color to orange.
cc_paint_tab() {
  local state="$1" type="$2" tty="$3" r g b
  ( printf '' > "$tty" ) 2>/dev/null || return 0
  read -r r g b <<<"$(color_for "$type")"
  [ "$state" = waiting ] && { r=240; g=150; b=0; }
  {
    printf '\033]6;1;bg;red;brightness;%d\a'   "$r"
    printf '\033]6;1;bg;green;brightness;%d\a' "$g"
    printf '\033]6;1;bg;blue;brightness;%d\a'  "$b"
    printf '\033]1337;SetBadgeFormat=%s\a' \
      "$(printf '%s %s' "$(glyph_for "$state")" "$type" | base64 | tr -d '\n')"
  } >> "$tty" 2>/dev/null
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-cc-lib.sh`
Expected: `ALL PASS` (exit 0).

- [ ] **Step 5: Refactor `iterm-tab.sh` to source the lib**

Replace the body of `claude/hooks/iterm-tab.sh` with:

```bash
#!/usr/bin/env bash
# iterm-tab.sh <state> — paint the current iTerm tab by work type / session state.
# Thin wrapper over cc-lib.sh so logic stays DRY with cc-hook.sh.
state="${1:-idle}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cc-lib.sh"
cwd="$PWD"
if [ ! -t 0 ]; then
  c="$(cat 2>/dev/null | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  [ -n "$c" ] && cwd="$c"
fi
cc_paint_tab "$state" "$(type_for "$(basename "$cwd")")" "$(cc_resolve_tty)"
exit 0
```

- [ ] **Step 6: Verify iterm-tab still works**

Run:
```bash
out=$(mktemp); echo '{"cwd":"/x/my-api"}' | CLAUDE_ITERM_TTY="$out" bash claude/hooks/iterm-tab.sh working
grep -q 'SetBadgeFormat' "$out" && grep -q 'brightness;40' "$out" && echo OK; rm -f "$out"
```
Expected: `OK`.

- [ ] **Step 7: Commit**

```bash
git add claude/hooks/cc-lib.sh claude/hooks/iterm-tab.sh tests/test-cc-lib.sh
git commit -m "feat(cockpit): shared cc-lib.sh; iterm-tab sources it"
```

---

## Task 2: State-writer hook `cc-hook.sh` + settings wiring

**Files:**
- Create: `claude/hooks/cc-hook.sh`
- Modify: `claude/settings.snippet.json`
- Test: `tests/test-cc-hook.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-cc-hook.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CC_SESSIONS_DIR="$(mktemp -d)"
export CLAUDE_ITERM_TTY="$(mktemp)"
fail=0
run(){ echo "$2" | CC_EVENT="$1" bash "$ROOT/claude/hooks/cc-hook.sh" "$3"; }

# UserPromptSubmit → working, captures desc + type
run UserPromptSubmit '{"session_id":"S1","cwd":"/x/my-api","prompt":"fix the auth test now"}' working
f="$CC_SESSIONS_DIR/S1.json"
[ -f "$f" ] || { echo "FAIL no state file"; fail=1; }
chk(){ [ "$2" = "$3" ] || { echo "FAIL $1: '$2'!='$3'"; fail=1; }; }
chk state "$(jq -r .state "$f")" "working"
chk type  "$(jq -r .type "$f")"  "api"
chk desc  "$(jq -r .desc "$f")"  "fix the auth test now"

# Stop → done, desc + started_at preserved across events
s1_started="$(jq -r .started_at "$f")"
run Stop '{"session_id":"S1","cwd":"/x/my-api"}' done
chk state2 "$(jq -r .state "$f")" "done"
chk desc2  "$(jq -r .desc "$f")"  "fix the auth test now"
chk start2 "$(jq -r .started_at "$f")" "$s1_started"

# SessionEnd → state file removed
run SessionEnd '{"session_id":"S1","cwd":"/x/my-api"}' end
[ -f "$f" ] && { echo "FAIL file not removed on end"; fail=1; }

rm -rf "$CC_SESSIONS_DIR" "$CLAUDE_ITERM_TTY"
[ $fail -eq 0 ] && echo "ALL PASS"; exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-cc-hook.sh`
Expected: FAIL (cc-hook.sh missing).

- [ ] **Step 3: Write `cc-hook.sh`**

Create `claude/hooks/cc-hook.sh`:

```bash
#!/usr/bin/env bash
# cc-hook.sh <state> — Claude lifecycle hook: upsert session state file + paint tab.
# state: idle|working|waiting|done|error|end   (end removes the state file)
set -uo pipefail
state="${1:-idle}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cc-lib.sh"

SESS_DIR="${CC_SESSIONS_DIR:-$HOME/.claude/cc-sessions}"
mkdir -p "$SESS_DIR" 2>/dev/null || exit 0

input="$(cat 2>/dev/null)"
g(){ printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
sid="$(g '.session_id')"; [ -z "$sid" ] && sid="pid$$"
f="$SESS_DIR/$sid.json"

# SessionEnd: drop the file and clear the tab color, then exit.
if [ "$state" = end ]; then
  rm -f "$f" 2>/dev/null
  tty="$(cc_resolve_tty)"; ( printf '\033]6;1;bg;*;default\a' >> "$tty" ) 2>/dev/null
  exit 0
fi

cwd="$(g '.cwd')"; [ -z "$cwd" ] && cwd="$PWD"
type="$(type_for "$(basename "$cwd")")"
tty="$(cc_resolve_tty)"
now="$(date +%s)"

started=""; desc=""; turn=""
if [ -f "$f" ]; then
  started="$(jq -r '.started_at // empty' "$f" 2>/dev/null)"
  desc="$(jq -r '.desc // empty' "$f" 2>/dev/null)"
  turn="$(jq -r '.turn_started_at // empty' "$f" 2>/dev/null)"
fi
[ -z "$started" ] && started="$now"
[ -z "$turn" ] && turn="$now"
# A new turn begins on UserPromptSubmit (working): reset turn clock + capture desc.
prompt="$(g '.prompt')"
if [ -n "$prompt" ]; then
  desc="$(printf '%s' "$prompt" | tr '\n\t' '  ' | sed 's/  */ /g' | cut -c1-40)"
  turn="$now"
fi

tmp="$(mktemp "$SESS_DIR/.$sid.XXXXXX" 2>/dev/null)" || exit 0
jq -n \
  --arg sid "$sid" --argjson pid "$$" --arg tty "$tty" --arg cwd "$cwd" \
  --arg type "$type" --arg state "$state" --arg desc "$desc" \
  --argjson started "$started" --argjson turn "$turn" --argjson now "$now" \
  --arg ev "${CC_EVENT:-}" \
  '{session_id:$sid,pid:$pid,tty:$tty,cwd:$cwd,type:$type,state:$state,
    desc:$desc,started_at:$started,turn_started_at:$turn,
    last_activity_at:$now,last_event:$ev}' \
  > "$tmp" 2>/dev/null && mv "$tmp" "$f"

cc_paint_tab "$state" "$type" "$tty"
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-cc-hook.sh`
Expected: `ALL PASS`.

- [ ] **Step 5: Point settings hooks at `cc-hook.sh`**

Replace the `hooks` block in `claude/settings.snippet.json` so every event calls
`cc-hook.sh` with `CC_EVENT`, and add `SessionEnd`:

```json
{
  "language": "korean",
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "CC_EVENT=SessionStart $HOME/.claude/hooks/cc-hook.sh idle", "timeout": 5 }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "CC_EVENT=UserPromptSubmit $HOME/.claude/hooks/cc-hook.sh working", "timeout": 5 }] }],
    "Notification": [{ "hooks": [{ "type": "command", "command": "CC_EVENT=Notification $HOME/.claude/hooks/cc-hook.sh waiting", "timeout": 5 }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "CC_EVENT=Stop $HOME/.claude/hooks/cc-hook.sh done", "timeout": 5 }] }],
    "SessionEnd": [{ "hooks": [{ "type": "command", "command": "CC_EVENT=SessionEnd $HOME/.claude/hooks/cc-hook.sh end", "timeout": 5 }] }]
  }
}
```

- [ ] **Step 6: Validate JSON**

Run: `jq empty claude/settings.snippet.json && echo OK`
Expected: `OK`.

- [ ] **Step 7: Commit**

```bash
git add claude/hooks/cc-hook.sh claude/settings.snippet.json tests/test-cc-hook.sh
git commit -m "feat(cockpit): cc-hook.sh writes session state; settings wired"
```

---

## Task 3: Focus a session by tty — `focus_session.applescript`

**Files:**
- Create: `claude/bin/focus_session.applescript`

- [ ] **Step 1: Write the script**

Create `claude/bin/focus_session.applescript`:

```applescript
on run argv
  if (count of argv) is 0 then return
  set target to item 1 of argv
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if (tty of s) is target then
            select w
            tell t to select
            tell s to select
            activate
            return
          end if
        end repeat
      end repeat
    end repeat
  end tell
end run
```

- [ ] **Step 2: Verify it compiles**

Run: `osacompile -o /tmp/_f.scpt claude/bin/focus_session.applescript && echo OK && rm -f /tmp/_f.scpt`
Expected: `OK` (syntax valid; runtime focus is verified manually in Task 5).

- [ ] **Step 3: Commit**

```bash
git add claude/bin/focus_session.applescript
git commit -m "feat(cockpit): focus iTerm session by tty (AppleScript)"
```

---

## Task 4: Dashboard TUI `cc-monitor` (+ stuck watchdog)

**Files:**
- Create: `claude/bin/cc-monitor`
- Test: `tests/test-cc-monitor.sh` (tests the pure render function via `--once`)

- [ ] **Step 1: Write the failing test**

Create `tests/test-cc-monitor.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CC_SESSIONS_DIR="$(mktemp -d)"
now="$(date +%s)"
mk(){ jq -n --arg s "$1" --arg t "$2" --arg d "$3" --argjson a "$4" --argjson p "$5" \
  '{session_id:$s,pid:$p,tty:("/dev/"+$s),cwd:("/x/"+$t),type:$t,state:$s,desc:$d,
    started_at:0,turn_started_at:0,last_activity_at:$a,last_event:""}' \
  > "$CC_SESSIONS_DIR/$1.json"; }
# states: a working(old→stuck), a waiting, a done. pid 1 is always alive (init).
mk working web "build"  $((now-1200)) 1
mk waiting api "review" $((now-30))   1
mk done    db  "migrate" $((now-5))   1
out="$(CC_STUCK_MIN=600 bash "$ROOT/claude/bin/cc-monitor" --once)"
fail=0
# waiting must sort above working/done
wl=$(echo "$out" | grep -n waiting | cut -d: -f1)
gl=$(echo "$out" | grep -n working | cut -d: -f1)
[ "$wl" -lt "$gl" ] || { echo "FAIL waiting not first"; fail=1; }
echo "$out" | grep -q 'STUCK' || { echo "FAIL no STUCK marker"; fail=1; }
echo "$out" | grep -q 'review' || { echo "FAIL desc missing"; fail=1; }
rm -rf "$CC_SESSIONS_DIR"
[ $fail -eq 0 ] && echo "ALL PASS"; exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-cc-monitor.sh`
Expected: FAIL (cc-monitor missing).

- [ ] **Step 3: Write `cc-monitor`**

Create `claude/bin/cc-monitor`:

```bash
#!/usr/bin/env bash
# cc-monitor [--once] — dashboard TUI for Claude cockpit sessions.
#   live: redraw every ~1s; press a row number to focus its iTerm tab; q quits.
#   --once: print one rendered frame and exit (for tests / piping).
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESS_DIR="${CC_SESSIONS_DIR:-$HOME/.claude/cc-sessions}"
STUCK_MIN="${CC_STUCK_MIN:-600}"
TTL="${CC_TTL:-86400}"
FOCUS="$SELF_DIR/focus_session.applescript"

order(){ case "$1" in error)echo 0;; waiting)echo 1;; working)echo 2;; done)echo 3;; *)echo 4;; esac; }
alive(){ kill -0 "$1" 2>/dev/null; }

# Print rows to stdout; also populate global TTYS[] index→tty for focus.
declare -a TTYS
render(){
  TTYS=()
  local now; now="$(date +%s)"
  local rows=""
  shopt -s nullglob
  for f in "$SESS_DIR"/*.json; do
    local sid pid tty type state desc act
    sid="$(jq -r '.session_id' "$f" 2>/dev/null)"; [ -z "$sid" ] && continue
    pid="$(jq -r '.pid' "$f" 2>/dev/null)"
    tty="$(jq -r '.tty' "$f" 2>/dev/null)"
    type="$(jq -r '.type' "$f" 2>/dev/null)"
    state="$(jq -r '.state' "$f" 2>/dev/null)"
    desc="$(jq -r '.desc' "$f" 2>/dev/null)"
    act="$(jq -r '.last_activity_at' "$f" 2>/dev/null)"
    # reap stale: dead pid or older than TTL
    if ! alive "$pid" || [ $(( now - act )) -gt "$TTL" ]; then rm -f "$f" 2>/dev/null; continue; fi
    local age=$(( now - act )) mark=""
    [ "$state" = working ] && [ "$age" -gt "$STUCK_MIN" ] && { state="working"; mark="STUCK"; }
    rows+="$(order "$state")|$age|$state|$mark|$type|$tty|$desc"$'\n'
  done
  shopt -u nullglob
  # sort by (state order asc, age desc) and number the rows
  local i=0
  while IFS='|' read -r ord age state mark type tty desc; do
    [ -z "$ord" ] && continue
    TTYS[$i]="$tty"
    printf '%2d) %-7s %-7s %-7s %5ss  %s\n' "$i" "$state" "${mark:--}" "$type" "$age" "$desc"
    i=$((i+1))
  done < <(printf '%s' "$rows" | sort -t'|' -k1,1n -k2,2nr)
  [ "$i" -eq 0 ] && echo "(no active sessions)"
}

if [ "${1:-}" = "--once" ]; then render; exit 0; fi

# live loop
trap 'tput cnorm 2>/dev/null; exit 0' INT TERM
tput civis 2>/dev/null
while :; do
  frame="$(render)"
  clear
  printf 'CC COCKPIT  (number=focus, q=quit)   %s\n\n%s\n' "$(date +%H:%M:%S)" "$frame"
  # wait up to 1s for a keypress
  if read -rsn1 -t 1 key; then
    case "$key" in
      q) tput cnorm 2>/dev/null; exit 0 ;;
      [0-9]) t="${TTYS[$key]:-}"; [ -n "$t" ] && osascript "$FOCUS" "$t" >/dev/null 2>&1 ;;
    esac
  fi
done
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-cc-monitor.sh`
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add claude/bin/cc-monitor tests/test-cc-monitor.sh
git commit -m "feat(cockpit): cc-monitor dashboard TUI + stuck watchdog"
```

---

## Task 5: Installer wiring + manual end-to-end verification

**Files:**
- Modify: `claude/install.sh`

- [ ] **Step 1: Extend `install.sh` to install `bin/` and keep settings merge**

In `claude/install.sh`, after the hook-install line (`install -m 0755 ".../iterm-tab.sh" ...`), add installation of the lib, cc-hook, and bin scripts. Insert:

```bash
# cockpit: shared lib + state hook
install -m 0644 "$SCRIPT_DIR/hooks/cc-lib.sh"  "$HOOKS_DIR/cc-lib.sh"
install -m 0755 "$SCRIPT_DIR/hooks/cc-hook.sh" "$HOOKS_DIR/cc-hook.sh"
echo "✓ installed cc-lib.sh + cc-hook.sh"

# cockpit: bin (monitor, focus, notifier, statusline)
BIN_DIR="$CLAUDE_DIR/bin"
mkdir -p "$BIN_DIR"
for b in cc-monitor focus_session.applescript; do
  install -m 0755 "$SCRIPT_DIR/bin/$b" "$BIN_DIR/$b"
done
echo "✓ installed cockpit bin → $BIN_DIR (run: $BIN_DIR/cc-monitor)"
```

- [ ] **Step 2: Run the installer**

Run: `bash claude/install.sh`
Expected: lines confirming `cc-lib.sh`, `cc-hook.sh`, and cockpit bin installed; settings merged.

- [ ] **Step 3: Manual end-to-end check**

1. Open a new iTerm pane and run: `~/.claude/bin/cc-monitor`
2. In other Claude sessions, submit a prompt (→ row shows `working`), let it finish (`done`), trigger a permission prompt (`waiting`).
3. In the monitor, press the row number for a waiting session → that iTerm tab is focused.
4. Confirm a session left mid-turn for >`CC_STUCK_MIN` shows `STUCK`.

Expected: rows update ~1s; waiting sorts on top; number-key focuses the right tab.

- [ ] **Step 4: Commit**

```bash
git add claude/install.sh
git commit -m "feat(cockpit): installer sets up cc-hook + cockpit bin"
```

---

# PHASE 2 — Notifications (macOS + Telegram)

## Task 6: Notifier `cc-notify.sh` + config example

**Files:**
- Create: `claude/bin/cc-notify.sh`
- Create: `claude/cc-notify.env.example`
- Modify: `.gitignore`
- Test: `tests/test-cc-notify.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-cc-notify.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CC_NOTIFY_DRYRUN=1
export CC_NOTIFY_ENV="$(mktemp)"
printf 'TELEGRAM_BOT_TOKEN=xx\nCC_NOTIFY_CHAT_ID=123\n' > "$CC_NOTIFY_ENV"
out="$(bash "$ROOT/claude/bin/cc-notify.sh" "api ◆ waiting" "review the diff" 2>&1)"
fail=0
echo "$out" | grep -q 'MACOS:' || { echo "FAIL no macOS line"; fail=1; }
echo "$out" | grep -q 'TELEGRAM:' || { echo "FAIL no telegram line"; fail=1; }
echo "$out" | grep -q 'review the diff' || { echo "FAIL body missing"; fail=1; }
# no token → telegram skipped, macOS still attempted
printf '' > "$CC_NOTIFY_ENV"
out2="$(bash "$ROOT/claude/bin/cc-notify.sh" "t" "b" 2>&1)"
echo "$out2" | grep -q 'TELEGRAM: skipped' || { echo "FAIL telegram not skipped"; fail=1; }
rm -f "$CC_NOTIFY_ENV"
[ $fail -eq 0 ] && echo "ALL PASS"; exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-cc-notify.sh`
Expected: FAIL (cc-notify.sh missing).

- [ ] **Step 3: Write `cc-notify.sh`**

Create `claude/bin/cc-notify.sh`:

```bash
#!/usr/bin/env bash
# cc-notify.sh <title> <body> — macOS + Telegram notification.
# Telegram creds from ~/.claude/cc-notify.env (TELEGRAM_BOT_TOKEN, CC_NOTIFY_CHAT_ID).
# CC_NOTIFY_DRYRUN=1 prints instead of sending. Failures never error out.
set -uo pipefail
title="${1:-Claude}"; body="${2:-}"
ENV_FILE="${CC_NOTIFY_ENV:-$HOME/.claude/cc-notify.env}"
DRY="${CC_NOTIFY_DRYRUN:-}"
[ -f "$ENV_FILE" ] && . "$ENV_FILE" 2>/dev/null

# macOS notification
if [ -n "$DRY" ]; then
  echo "MACOS: $title — $body"
else
  osascript -e "display notification \"${body//\"/\\\"}\" with title \"${title//\"/\\\"}\"" >/dev/null 2>&1 || true
fi

# Telegram
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${CC_NOTIFY_CHAT_ID:-}" ]; then
  if [ -n "$DRY" ]; then
    echo "TELEGRAM: $title — $body"
  else
    curl -s -m 5 -o /dev/null \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=${CC_NOTIFY_CHAT_ID}" \
      --data-urlencode "text=${title} — ${body}" >/dev/null 2>&1 || true
  fi
else
  echo "TELEGRAM: skipped (no token/chat id)"
fi
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-cc-notify.sh`
Expected: `ALL PASS`.

- [ ] **Step 5: Create env example + gitignore**

Create `claude/cc-notify.env.example`:

```bash
# Copy to ~/.claude/cc-notify.env (gitignored) and fill in.
# Create a bot via @BotFather; get your chat id from @userinfobot.
TELEGRAM_BOT_TOKEN=
CC_NOTIFY_CHAT_ID=
```

Append to `.gitignore`:

```
cc-notify.env
```

- [ ] **Step 6: Commit**

```bash
git add claude/bin/cc-notify.sh claude/cc-notify.env.example .gitignore tests/test-cc-notify.sh
git commit -m "feat(cockpit): cc-notify.sh (macOS + Telegram), dry-run testable"
```

---

## Task 7: Wire notifier + watchdog alerts into `cc-monitor`

**Files:**
- Modify: `claude/bin/cc-monitor`
- Modify: `tests/test-cc-monitor.sh` (assert transition emits a dry-run notify)

- [ ] **Step 1: Extend the test for transition detection**

Append to `tests/test-cc-monitor.sh` before the final `rm -rf` line:

```bash
# transition: working -> waiting between two renders fires a dry-run notify
export CC_NOTIFY_DRYRUN=1 CC_NOTIFY_ENV="$(mktemp)"
export CC_STATE_CACHE="$(mktemp)"
mk working api "x" $((now-5)) 1
CC_NOTIFY_LOG="$(mktemp)"
CC_NOTIFY_TEST_LOG="$CC_NOTIFY_LOG" bash "$ROOT/claude/bin/cc-monitor" --scan >/dev/null
mk waiting api "x" $((now-1)) 1     # api now waiting
CC_NOTIFY_TEST_LOG="$CC_NOTIFY_LOG" bash "$ROOT/claude/bin/cc-monitor" --scan >/dev/null
grep -q 'waiting' "$CC_NOTIFY_LOG" || { echo "FAIL no transition notify"; fail=1; }
rm -f "$CC_NOTIFY_ENV" "$CC_STATE_CACHE" "$CC_NOTIFY_LOG"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-cc-monitor.sh`
Expected: FAIL (`--scan` mode and notify wiring not implemented).

- [ ] **Step 3: Add transition detection to `cc-monitor`**

Add near the top of `cc-monitor` (after the config vars):

```bash
NOTIFY="$SELF_DIR/cc-notify.sh"
STATE_CACHE="${CC_STATE_CACHE:-$HOME/.claude/.cc-monitor-state}"
DONE_MIN="${CC_DONE_MIN:-120}"
THROTTLE="${CC_THROTTLE:-60}"

# Fire cc-notify.sh (or the test log) honoring per-(sid,state) throttle.
notify(){ # sid state type desc
  local sid="$1" state="$2" type="$3" desc="$4" now key last
  now="$(date +%s)"; key="$sid:$state"
  last="$(grep -F "throttle $key " "$STATE_CACHE" 2>/dev/null | tail -1 | awk '{print $3}')"
  [ -n "$last" ] && [ $(( now - last )) -lt "$THROTTLE" ] && return 0
  echo "throttle $key $now" >> "$STATE_CACHE"
  if [ -n "${CC_NOTIFY_TEST_LOG:-}" ]; then
    echo "$type $state $desc" >> "$CC_NOTIFY_TEST_LOG"
  else
    "$NOTIFY" "$type $(glyph_for "$state") $state" "$desc" >/dev/null 2>&1 || true
  fi
}
# glyph_for needed here too:
. "$SELF_DIR/../hooks/cc-lib.sh" 2>/dev/null || true
```

Then add a `scan()` function that detects transitions and calls `notify` per the
policy (→waiting, →error always; →done only if turn lasted > DONE_MIN; stuck once):

```bash
scan(){
  local now; now="$(date +%s)"
  shopt -s nullglob
  for f in "$SESS_DIR"/*.json; do
    local sid state type desc turn act prev
    sid="$(jq -r '.session_id' "$f" 2>/dev/null)"; [ -z "$sid" ] && continue
    state="$(jq -r '.state' "$f" 2>/dev/null)"
    type="$(jq -r '.type' "$f" 2>/dev/null)"
    desc="$(jq -r '.desc' "$f" 2>/dev/null)"
    turn="$(jq -r '.turn_started_at' "$f" 2>/dev/null)"
    act="$(jq -r '.last_activity_at' "$f" 2>/dev/null)"
    prev="$(grep -F "last $sid " "$STATE_CACHE" 2>/dev/null | tail -1 | awk '{print $3}')"
    if [ "$state" != "$prev" ]; then
      case "$state" in
        waiting|error) notify "$sid" "$state" "$type" "$desc" ;;
        done) [ -n "$turn" ] && [ $(( act - turn )) -gt "$DONE_MIN" ] && notify "$sid" "$state" "$type" "$desc" ;;
      esac
      echo "last $sid $state" >> "$STATE_CACHE"
    fi
    # stuck watchdog: notify once when crossing the threshold while working
    if [ "$state" = working ] && [ $(( now - act )) -gt "$STUCK_MIN" ]; then
      notify "$sid" "stuck" "$type" "$desc"
    fi
  done
  shopt -u nullglob
}
```

Add a `--scan` entrypoint (before the `--once` check):

```bash
if [ "${1:-}" = "--scan" ]; then scan; exit 0; fi
```

And call `scan` once per live-loop iteration, right after `frame="$(render)"`:

```bash
  scan
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-cc-monitor.sh`
Expected: `ALL PASS`.

- [ ] **Step 5: Install cc-notify into bin (extend installer list)**

In `claude/install.sh`, add `cc-notify.sh` to the bin loop:

```bash
for b in cc-monitor focus_session.applescript cc-notify.sh; do
  install -m 0755 "$SCRIPT_DIR/bin/$b" "$BIN_DIR/$b"
done
```

Also install the env example:

```bash
install -m 0644 "$SCRIPT_DIR/cc-notify.env.example" "$CLAUDE_DIR/cc-notify.env.example"
```

- [ ] **Step 6: Commit**

```bash
git add claude/bin/cc-monitor claude/install.sh tests/test-cc-monitor.sh
git commit -m "feat(cockpit): monitor fires throttled notifications on transitions"
```

---

# PHASE 3 — Domain-error detection + statusLine

## Task 8: Error scanner `cc-error-scan.sh` (PostToolUse) + patterns example

**Files:**
- Create: `claude/hooks/cc-error-scan.sh`
- Create: `claude/cc-error-patterns.example.txt`
- Modify: `claude/settings.snippet.json` (add PostToolUse), `.gitignore`, `claude/install.sh`
- Test: `tests/test-cc-error-scan.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-cc-error-scan.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CC_SESSIONS_DIR="$(mktemp -d)"
export CC_PATTERNS="$(mktemp)"; printf 'OutOfMemory\nFATAL\n' > "$CC_PATTERNS"
export CLAUDE_ITERM_TTY="$(mktemp)"
now="$(date +%s)"
# seed a working state file for session S1
jq -n --argjson n "$now" '{session_id:"S1",pid:1,tty:"/dev/x",cwd:"/x/my-api",
  type:"api",state:"working",desc:"d",started_at:$n,turn_started_at:$n,
  last_activity_at:$n,last_event:""}' > "$CC_SESSIONS_DIR/S1.json"
fail=0
# matching tool output → state becomes error
echo '{"session_id":"S1","tool_response":{"stdout":"… OutOfMemory: heap"}}' \
  | bash "$ROOT/claude/hooks/cc-error-scan.sh"
chk(){ [ "$2" = "$3" ] || { echo "FAIL $1: '$2'!='$3'"; fail=1; }; }
chk err "$(jq -r .state "$CC_SESSIONS_DIR/S1.json")" "error"
# non-matching output → unchanged (reset to working first)
jq '.state="working"' "$CC_SESSIONS_DIR/S1.json" > "$CC_SESSIONS_DIR/.t" && mv "$CC_SESSIONS_DIR/.t" "$CC_SESSIONS_DIR/S1.json"
echo '{"session_id":"S1","tool_response":{"stdout":"all good"}}' | bash "$ROOT/claude/hooks/cc-error-scan.sh"
chk ok "$(jq -r .state "$CC_SESSIONS_DIR/S1.json")" "working"
rm -rf "$CC_SESSIONS_DIR" "$CC_PATTERNS" "$CLAUDE_ITERM_TTY"
[ $fail -eq 0 ] && echo "ALL PASS"; exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-cc-error-scan.sh`
Expected: FAIL (script missing).

- [ ] **Step 3: Write `cc-error-scan.sh`**

Create `claude/hooks/cc-error-scan.sh`:

```bash
#!/usr/bin/env bash
# cc-error-scan.sh — PostToolUse hook. If tool output matches any regex in the
# patterns file, flip the session's state file to "error" and paint the tab red.
# Patterns: ~/.claude/cc-error-patterns.txt (gitignored). No file → no-op.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cc-lib.sh"
PATTERNS="${CC_PATTERNS:-$HOME/.claude/cc-error-patterns.txt}"
SESS_DIR="${CC_SESSIONS_DIR:-$HOME/.claude/cc-sessions}"
[ -f "$PATTERNS" ] || exit 0

input="$(cat 2>/dev/null)"
g(){ printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
sid="$(g '.session_id')"; [ -z "$sid" ] && exit 0
f="$SESS_DIR/$sid.json"; [ -f "$f" ] || exit 0

# Concatenate likely output fields and grep against the patterns.
blob="$(printf '%s' "$input" | jq -r '[.tool_response.stdout?, .tool_response.stderr?, (.tool_response|tostring)] | map(select(.!=null)) | join("\n")' 2>/dev/null)"
grep -Eqf "$PATTERNS" <<<"$blob" || exit 0

tmp="$(mktemp "$SESS_DIR/.$sid.XXXXXX" 2>/dev/null)" || exit 0
jq '.state="error" | .last_event="error-scan"' "$f" > "$tmp" 2>/dev/null && mv "$tmp" "$f"
cc_paint_tab error "$(jq -r '.type' "$f" 2>/dev/null)" "$(jq -r '.tty' "$f" 2>/dev/null)"
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-cc-error-scan.sh`
Expected: `ALL PASS`.

- [ ] **Step 5: Add PostToolUse hook + patterns example + gitignore + installer**

Add to `claude/settings.snippet.json` `hooks` object:

```json
    "PostToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/cc-error-scan.sh", "timeout": 5 }] }]
```

Create `claude/cc-error-patterns.example.txt`:

```
# Copy to ~/.claude/cc-error-patterns.txt (gitignored). One ERE regex per line.
OutOfMemory
FATAL
panic:
Traceback \(most recent call last\)
Segmentation fault
```

Append to `.gitignore`: `cc-error-patterns.txt`

In `claude/install.sh`, install the lib-dependent hook + the example:

```bash
install -m 0755 "$SCRIPT_DIR/hooks/cc-error-scan.sh" "$HOOKS_DIR/cc-error-scan.sh"
install -m 0644 "$SCRIPT_DIR/cc-error-patterns.example.txt" "$CLAUDE_DIR/cc-error-patterns.example.txt"
```

- [ ] **Step 6: Validate + commit**

Run: `jq empty claude/settings.snippet.json && bash tests/test-cc-error-scan.sh`
Expected: `ALL PASS`.

```bash
git add claude/hooks/cc-error-scan.sh claude/cc-error-patterns.example.txt \
        claude/settings.snippet.json claude/install.sh .gitignore tests/test-cc-error-scan.sh
git commit -m "feat(cockpit): PostToolUse error scanner → state=error (local patterns)"
```

---

## Task 9: Rich `cc-statusline.sh`

**Files:**
- Create: `claude/bin/cc-statusline.sh`
- Modify: `claude/settings.snippet.json` (add `statusLine`), `claude/install.sh`
- Test: `tests/test-cc-statusline.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-cc-statusline.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CC_SESSIONS_DIR="$(mktemp -d)"
now="$(date +%s)"
jq -n --argjson n "$now" '{session_id:"S1",pid:1,tty:"/dev/x",cwd:"/x/my-api",
  type:"api",state:"working",desc:"d",started_at:$n,turn_started_at:$n,
  last_activity_at:$n,last_event:""}' > "$CC_SESSIONS_DIR/S1.json"
out="$(echo '{"session_id":"S1","model":{"display_name":"Opus"},"cost":{"total_cost_usd":0.42},"workspace":{"current_dir":"/x/my-api"}}' \
  | bash "$ROOT/claude/bin/cc-statusline.sh")"
fail=0
echo "$out" | grep -q 'api'  || { echo "FAIL no type"; fail=1; }
echo "$out" | grep -q 'Opus' || { echo "FAIL no model"; fail=1; }
echo "$out" | grep -q '0.42' || { echo "FAIL no cost"; fail=1; }
rm -rf "$CC_SESSIONS_DIR"
[ $fail -eq 0 ] && echo "ALL PASS"; exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-cc-statusline.sh`
Expected: FAIL (script missing).

- [ ] **Step 3: Write `cc-statusline.sh`**

Create `claude/bin/cc-statusline.sh`:

```bash
#!/usr/bin/env bash
# cc-statusline.sh — Claude statusLine renderer.
# stdin: statusLine JSON (model, cost, workspace, session_id). Reads the session
# state file for type/state/glyph. Output one line.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)/cc-lib.sh"
SESS_DIR="${CC_SESSIONS_DIR:-$HOME/.claude/cc-sessions}"

input="$(cat 2>/dev/null)"
g(){ printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
sid="$(g '.session_id')"
model="$(g '.model.display_name')"; [ -z "$model" ] && model="?"
cost="$(g '.cost.total_cost_usd')"
cwd="$(g '.workspace.current_dir')"; [ -z "$cwd" ] && cwd="$PWD"

type="$(type_for "$(basename "$cwd")")"; state="idle"
f="$SESS_DIR/$sid.json"
[ -f "$f" ] && { type="$(jq -r '.type' "$f" 2>/dev/null)"; state="$(jq -r '.state' "$f" 2>/dev/null)"; }

branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)"; [ -z "$branch" ] && branch="-"
costs=""; [ -n "$cost" ] && costs=$(printf '$%.2f' "$cost" 2>/dev/null)

printf '%s %s │ %s │ %s │ %s' "$type" "$(glyph_for "$state")" "$branch" "$model" "$costs"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-cc-statusline.sh`
Expected: `ALL PASS`.

- [ ] **Step 5: Register statusLine + install**

Add to `claude/settings.snippet.json` (top level, sibling of `hooks`):

```json
  "statusLine": { "type": "command", "command": "$HOME/.claude/bin/cc-statusline.sh" }
```

In `claude/install.sh` bin loop add `cc-statusline.sh`:

```bash
for b in cc-monitor focus_session.applescript cc-notify.sh cc-statusline.sh; do
  install -m 0755 "$SCRIPT_DIR/bin/$b" "$BIN_DIR/$b"
done
```

- [ ] **Step 6: Validate + commit**

Run: `jq empty claude/settings.snippet.json && bash tests/test-cc-statusline.sh`
Expected: `ALL PASS`.

```bash
git add claude/bin/cc-statusline.sh claude/settings.snippet.json claude/install.sh tests/test-cc-statusline.sh
git commit -m "feat(cockpit): rich cc-statusline (type/state/branch/model/cost)"
```

---

## Final: run all tests + docs

- [ ] **Step 1: Run the whole suite**

Run: `for t in tests/test-*.sh; do echo "== $t =="; bash "$t"; done`
Expected: every test prints `ALL PASS`.

- [ ] **Step 2: Update READMEs**

Add a "Multi-session cockpit" section to `claude/README.md` (EN top / KO bottom)
documenting: `cc-monitor` (run in a pane), the state store, notifications setup
(`cp claude/cc-notify.env.example ~/.claude/cc-notify.env` then fill in),
error patterns (`cp claude/cc-error-patterns.example.txt ~/.claude/cc-error-patterns.txt`),
and the statusLine. Keep it generic — no workplace names.

- [ ] **Step 3: Commit**

```bash
git add claude/README.md
git commit -m "docs(cockpit): document monitor, notifications, error patterns, statusLine"
```

---

## Self-review notes (coverage vs spec)

- A dashboard → Task 4. B notifications → Tasks 6–7. C jump → Tasks 3–4 (number-key + AppleScript).
  D domain errors → Task 8. E watchdog → Tasks 4 (marker) + 7 (alert). F statusLine → Task 9.
- State file schema (incl. `turn_started_at` for the done-duration rule) → Task 2.
- Genericity/secrets: type mappings (cc-lib + override), patterns file, Telegram env are all
  gitignored locals; only `*.example` files are committed → Tasks 6, 8.
- Phases independently shippable: Phase 1 (Tasks 1–5) works with no notifier/statusline.
