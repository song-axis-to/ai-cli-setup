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
