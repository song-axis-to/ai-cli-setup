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
