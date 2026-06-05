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
