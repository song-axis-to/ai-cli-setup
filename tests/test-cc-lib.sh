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
n=$(tr -cd '\a' < "$out" | wc -c | tr -d ' '); chk paint_seqs "$n" "4"
# waiting overrides red channel to 240
cc_paint_tab waiting api "$out"; grep -q 'red;brightness;240' "$out" || { echo "FAIL waiting override"; fail=1; }
rm -f "$out"

# cc_resolve_pid returns a live pid (never the hook's ephemeral $$ after it exits):
# called from this (live) shell it must yield a positive integer for a running process.
rp="$(cc_resolve_pid)"
case "$rp" in ''|*[!0-9]*) echo "FAIL resolve_pid not numeric: '$rp'"; fail=1 ;; esac
ps -p "$rp" >/dev/null 2>&1 || { echo "FAIL resolve_pid '$rp' not alive"; fail=1; }
# CC_SESSION_PID override is honored (used by tests to inject a known pid)
chk resolve_pid_override "$(CC_SESSION_PID=4242 cc_resolve_pid)" "4242"

[ $fail -eq 0 ] && echo "ALL PASS"; exit $fail
