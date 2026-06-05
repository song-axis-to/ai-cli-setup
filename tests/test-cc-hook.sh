#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CC_SESSIONS_DIR="$(mktemp -d)"
export CLAUDE_ITERM_TTY="$(mktemp)"
fail=0
run(){ echo "$2" | HOME=/nonexistent-home CC_EVENT="$1" bash "$ROOT/claude/hooks/cc-hook.sh" "$3"; }

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
