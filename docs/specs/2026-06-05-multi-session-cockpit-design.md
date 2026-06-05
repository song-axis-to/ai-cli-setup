# Claude Code Multi-Session Cockpit — Design

Date: 2026-06-05
Status: Approved (brainstorming) → planning

## Problem

Running 15+ parallel Claude Code sessions across iTerm2 tabs, it is hard to see
**which session needs you**, what each is doing, and whether any is stuck. The
existing per-tab color/badge ([`claude/hooks/iterm-tab.sh`](../../claude/hooks/iterm-tab.sh))
helps inside one tab but gives no cross-session overview, no alerting, and no
fast way to jump to the session that needs attention.

## Goal

A "cockpit" for many concurrent sessions, built on **one shared state store**
that every component reads:

- **A. Dashboard** — a dedicated iTerm pane TUI listing all sessions (waiting first).
- **B. Notifications** — macOS + Telegram when a session needs you / errors / finishes a long turn.
- **C. Jump** — select a session in the dashboard, focus its iTerm tab.
- **D. Domain-error detection** — flag sessions whose tool output matches error patterns.
- **E. Stuck watchdog** — flag sessions stuck "working" with no activity.
- **F. Rich statusLine** — per-session bottom bar (type, state, branch, model, cost, elapsed).

## Non-goals

- Token/cost "runaway" auto-kill (hooks cannot see token counts; cost is surfaced read-only in F).
- A long-running daemon or socket IPC (file-based store is enough for this scale).
- Any tool other than Claude Code driving the state store (Codex has no equivalent hooks).

## Architecture

```
            ┌─────────────── per Claude session ───────────────┐
 lifecycle  │  cc-hook.sh <state>                               │
 hooks  ───▶│   • upsert ~/.claude/cc-sessions/<session_id>.json│
            │   • paint iTerm tab color + badge (iterm-tab)     │
 PostToolUse│  cc-error-scan.sh (D)                             │
        ───▶│   • match tool output vs ~/.claude/cc-error-      │
            │     patterns.txt → set state=error in state file  │
            └───────────────────────┬──────────────────────────┘
                                    │ writes
                     ~/.claude/cc-sessions/*.json   (one file per session)
                                    │ reads
            ┌───────────────────────┴──────────────────────────┐
 dedicated  │  cc-monitor  (TUI, polls ~1s)                     │
 iTerm pane │   • render sorted list (A); j/k/number+Enter (C)  │
            │   • watchdog: working & idle > STUCK_MIN (E)      │
            │   • transition detect → cc-notify.sh (B)          │
            └───────────────────────┬──────────────────────────┘
                                    │ focus by tty
                      focus_session.applescript  → iTerm2

 statusLine: cc-statusline.sh (F) — called by Claude per render, reads the
 session's state file + statusLine stdin (model, cwd, cost).
```

### Why file-based

One JSON file per session under `~/.claude/cc-sessions/`. Crash-safe (no daemon
to die), no IPC, trivially scannable at this scale. Stale files are reaped by the
monitor (dead `pid` or `mtime` older than a TTL).

## State file schema

`~/.claude/cc-sessions/<session_id>.json`:

```json
{
  "session_id": "abc123",
  "pid": 81312,
  "tty": "/dev/ttys029",
  "cwd": "/Users/you/Workspace/foo",
  "type": "api",
  "state": "waiting",
  "desc": "fix the failing auth test",
  "started_at": 1717500000,
  "turn_started_at": 1717500100,
  "last_activity_at": 1717500123,
  "last_event": "Notification"
}
```

- `session_id`, `cwd` from hook stdin JSON; `tty` via the process-tree walk
  (same logic as `iterm-tab.sh resolve_tty`); `type` via `type_for()`.
- `desc` = first ~40 chars of the latest user prompt (captured on
  `UserPromptSubmit` stdin). Deterministic; localized to whatever language the
  user types.
- `turn_started_at` resets to now on each `UserPromptSubmit` (working); used by the notifier's `DONE_MIN` rule (alert on `done` only when `last_activity_at − turn_started_at > DONE_MIN`).
- `state` ∈ {idle, working, waiting, done, error}.

## Components

### 1) cc-hook.sh `<state>` (replaces direct iterm-tab.sh hook wiring)
- Inputs: state arg + hook stdin JSON. Outputs: upserts state file; calls tab coloring.
- Merges the existing `iterm-tab.sh` behavior so one hook does both (state + OSC).
- On `UserPromptSubmit`, also records `desc` from the prompt text.
- Never blocks: `timeout 5`, errors swallowed.

### 2) cc-monitor (TUI)
- Polls `cc-sessions/*.json` every ~1s. Reaps stale (dead pid / old mtime).
- Renders a table sorted: `error` → `waiting` → `working`(oldest activity first) → `done`/`idle`.
- Row: `<color glyph> <type> <tty> <STATE> <age> "<desc>"`.
- Keys: `j`/`k` or number to select, `Enter` to focus (calls `focus_session.applescript <tty>`), `q` quit.
- Watchdog (E): rows with `state=working` and `now-last_activity_at > STUCK_MIN` (default 600s) get a ⚠ marker + one notification (throttled).
- Notifier driver (B): keeps previous poll's state per session; on transition fires `cc-notify.sh` for →waiting (always), →error (always), and →done only when the turn lasted longer than `DONE_MIN` (default 120s, measured `last_activity_at − started_at` of that turn). Throttle: no repeat within 60s per (session, state).
- Config via env/file: `STUCK_MIN`, `DONE_MIN`, throttle, TTL.

### 3) focus_session.applescript `<tty>`
- iTerm2 AppleScript: iterate windows→tabs→sessions, match `tty`, `select` tab+session and `activate`. No iTerm Python API needed.

### 4) cc-notify.sh `<title> <body> [url]`
- macOS: `osascript -e 'display notification ...'`.
- Telegram: `curl` to Bot API; `TELEGRAM_BOT_TOKEN` + `CC_NOTIFY_CHAT_ID` from
  `~/.claude/cc-notify.env` (gitignored). Missing token → skip Telegram silently.
- Dry-run via `CC_NOTIFY_DRYRUN=1` (prints instead of sends) for tests.

### 5) cc-error-scan.sh (PostToolUse hook, D)
- Reads tool output from hook stdin; greps against `~/.claude/cc-error-patterns.txt`
  (one regex per line; gitignored). Repo ships `cc-error-patterns.example.txt`
  with generic patterns (`OutOfMemory`, `FATAL`, `panic`, `Traceback`, …).
- On match: set `state=error` in the session's state file (monitor turns it red + notifies).
- No match / no patterns file → no-op.

### 6) cc-statusline.sh (F)
- Registered as `settings.json` `statusLine.command`. Reads statusLine stdin
  (model, cwd, cost if present) + the session state file.
- Renders: `<type> <glyph> │ <git branch> │ <model> │ $<cost> │ <elapsed>`.
- Fast (<50ms), pure shell + jq.

## Config & file layout

Repo (`ai-cli-setup`):
```
claude/
  bin/
    cc-monitor
    cc-notify.sh
    cc-statusline.sh
    cc-error-scan.sh
    focus_session.applescript
  hooks/
    cc-hook.sh           # state writer + tab coloring (wraps iterm-tab logic)
    iterm-tab.sh         # kept; cc-hook delegates color/badge to it
  cc-notify.env.example
  cc-error-patterns.example.txt
  settings.snippet.json  # + statusLine, + PostToolUse, hooks point to cc-hook.sh
  install.sh             # installs bin/, examples, merges settings
```

Local-only (gitignored, never committed):
`~/.claude/cc-tab-overrides.sh`, `~/.claude/cc-notify.env`, `~/.claude/cc-error-patterns.txt`,
`~/.claude/cc-sessions/`.

## Phasing

- **Phase 1 (core):** state store + `cc-hook.sh` + `cc-monitor` (A + C) + watchdog (E). Standalone value.
- **Phase 2:** `cc-notify.sh` + monitor transition detection (B).
- **Phase 3:** `cc-error-scan.sh` (D) + `cc-statusline.sh` (F).

Each phase ships independently usable.

## Error handling

- Hooks never block the session: `timeout 5`, all errors swallowed, no-op when
  deps (`jq`, `curl`) or tty are missing.
- State writes are atomic (write temp + `mv`).
- Monitor reaps stale files (dead pid / mtime > TTL) so a crashed session
  doesn't linger in the list.
- Telegram/AppleScript failures are silent and never affect the session.

## Testing

- Each script is unit-testable by synthesizing hook stdin / state files (the
  pattern already used for `iterm-tab.sh`).
- `cc-monitor` render tested against a fixture `cc-sessions/` directory.
- `cc-notify.sh` tested with `CC_NOTIFY_DRYRUN=1`.
- `focus_session.applescript` tested by matching a known tty (dry `-e` compile check at minimum).

## Security / genericity

All workplace-specific data (project→type mappings, error patterns, Telegram
token/chat id) lives in gitignored local files. The repo stays generic and
public-safe. No secrets or internal names are committed.
