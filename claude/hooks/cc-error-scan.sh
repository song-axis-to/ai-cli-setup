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
# strip blank lines and # comments so the example file's header can't match everything
pats="$(grep -vE '^[[:space:]]*(#|$)' "$PATTERNS" 2>/dev/null)"
[ -z "$pats" ] && exit 0
grep -Eq -f <(printf '%s\n' "$pats") <<<"$blob" || exit 0

tmp="$(mktemp "$SESS_DIR/.$sid.XXXXXX" 2>/dev/null)" || exit 0
jq '.state="error" | .last_event="error-scan"' "$f" > "$tmp" 2>/dev/null && mv "$tmp" "$f"
cc_paint_tab error "$(jq -r '.type' "$f" 2>/dev/null)" "$(jq -r '.tty' "$f" 2>/dev/null)"
exit 0
