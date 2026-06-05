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
