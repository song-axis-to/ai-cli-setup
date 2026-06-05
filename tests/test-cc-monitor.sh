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
# transition: a single session working -> waiting across two scans fires one waiting notify
TDIR="$(mktemp -d)"
TLOG="$(mktemp)"
TCACHE="$(mktemp)"
wr(){ jq -n --arg s "$1" --arg st "$2" --argjson n "$now" \
  '{session_id:$s,pid:1,tty:"/dev/x",cwd:"/x/my-api",type:"api",state:$st,desc:"d",
    started_at:$n,turn_started_at:$n,last_activity_at:$n,last_event:""}' \
  > "$TDIR/$1.json"; }
wr S1 working
CC_SESSIONS_DIR="$TDIR" CC_STATE_CACHE="$TCACHE" CC_NOTIFY_TEST_LOG="$TLOG" \
  bash "$ROOT/claude/bin/cc-monitor" --scan >/dev/null
: > "$TLOG"   # ignore baseline; only care about the transition scan
wr S1 waiting
CC_SESSIONS_DIR="$TDIR" CC_STATE_CACHE="$TCACHE" CC_NOTIFY_TEST_LOG="$TLOG" \
  bash "$ROOT/claude/bin/cc-monitor" --scan >/dev/null
grep -q 'waiting' "$TLOG" || { echo "FAIL no transition notify"; fail=1; }
rm -rf "$TDIR" "$TLOG" "$TCACHE"

rm -rf "$CC_SESSIONS_DIR"
[ $fail -eq 0 ] && echo "ALL PASS"; exit $fail
