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
n=$(grep -c $'\a' "$out"); chk paint_seqs "$n" "4"
# waiting overrides red channel to 240
cc_paint_tab waiting api "$out"; grep -q 'red;brightness;240' "$out" || { echo "FAIL waiting override"; fail=1; }
rm -f "$out"
[ $fail -eq 0 ] && echo "ALL PASS"; exit $fail
