#!/usr/bin/env bash
# iterm-tab.sh <state>
# Color the iTerm2 tab by project/work TYPE (stable per session, from cwd), and
# show the session STATE as a badge glyph next to the type label.
# Driven by Claude Code lifecycle hooks (see ../settings.snippet.json).
#
#   state: working | waiting | done | error | idle (default)
#
# Writes iTerm2 OSC escape sequences straight to the controlling terminal so it
# works regardless of the hook's captured stdout. No-ops when not attached to a
# usable tty (headless / SDK runs). Override the target with CLAUDE_ITERM_TTY
# (used for testing).

state="${1:-idle}"

# Resolve the terminal device to write to. Claude Code runs hooks WITHOUT a
# controlling terminal (especially over SSH), so /dev/tty here is often "Device
# not configured" and every escape sequence is silently dropped. Instead, walk
# up the process tree to the nearest ancestor (claude itself) attached to a real
# pane tty (ttysNNN) and write there — over SSH that pty forwards the OSC
# sequences to the client's iTerm2. Override with CLAUDE_ITERM_TTY (testing);
# fall back to /dev/tty as a last resort.
resolve_tty() {
  [ -n "${CLAUDE_ITERM_TTY:-}" ] && { printf '%s' "$CLAUDE_ITERM_TTY"; return; }
  local pid="$$" ppid t
  while [ "${pid:-0}" -gt 1 ]; do
    read -r ppid t <<<"$(ps -o ppid=,tty= -p "$pid" 2>/dev/null)"
    case "$t" in
      ttys*) printf '/dev/%s' "$t"; return ;;
    esac
    pid="$ppid"
  done
  printf '/dev/tty'
}
tty_dev="$(resolve_tty)"

# Probe: can we actually open the target for writing? ("Device not configured"
# passes a plain -w test, so write a zero-length payload and check.)
( printf '' > "$tty_dev" ) 2>/dev/null || exit 0

emit() { ( printf "$1" "${2:-}" >> "$tty_dev" ) 2>/dev/null; }

# --- type + color mapping (override-able) -----------------------------------
# Map a directory basename to a short work "type". These are GENERIC examples —
# edit them, or keep them private by defining your own type_for()/color_for() in
# ~/.claude/cc-tab-overrides.sh (sourced below, not tracked by git).
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
    api)    echo "40 110 230"  ;;  # blue
    web)    echo "40 170 80"   ;;  # green
    worker) echo "150 80 220"  ;;  # purple
    data)   echo "0 170 180"   ;;  # cyan
    db)     echo "230 130 0"   ;;  # orange
    infra)  echo "200 160 0"   ;;  # amber
    docs)   echo "210 60 160"  ;;  # magenta
    *)      echo "120 120 120" ;;  # gray (unknown type)
  esac
}

# Private overrides (NOT committed): may redefine type_for / color_for to match
# your own project names. Create ~/.claude/cc-tab-overrides.sh to use.
[ -f "$HOME/.claude/cc-tab-overrides.sh" ] && . "$HOME/.claude/cc-tab-overrides.sh"

# --- resolve cwd -> type ----------------------------------------------------
# Prefer cwd from the hook's stdin JSON; fall back to $PWD.
cwd="$PWD"
if [ ! -t 0 ]; then
  stdin_cwd="$(cat 2>/dev/null | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  [ -n "$stdin_cwd" ] && cwd="$stdin_cwd"
fi
type="$(type_for "$(basename "$cwd")")"

# --- tab color by type, with a "waiting" attention override -----------------
read -r r g b <<<"$(color_for "$type")"
# When the session is waiting on you (permission / input), paint orange
# regardless of type so the tab that needs attention stands out.
[ "$state" = waiting ] && { r=240; g=150; b=0; }

# iTerm2 OSC 6: set tab title (background) color, per channel.
emit '\033]6;1;bg;red;brightness;%d\a'   "$r"
emit '\033]6;1;bg;green;brightness;%d\a' "$g"
emit '\033]6;1;bg;blue;brightness;%d\a'  "$b"

# --- badge = session-state glyph + type label -------------------------------
case "$state" in
  working) glyph="●" ;;  # actively working
  waiting) glyph="◆" ;;  # needs your input / permission
  done)    glyph="✓" ;;  # turn finished
  error)   glyph="✗" ;;  # a tool failed
  *)       glyph="·" ;;  # idle / ready
esac

# iTerm2 OSC 1337 SetBadgeFormat expects base64 (single line).
badge="$(printf '%s %s' "$glyph" "$type" | base64 | tr -d '\n')"
emit '\033]1337;SetBadgeFormat=%s\a' "$badge"

exit 0
