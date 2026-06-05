#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CC_NOTIFY_DRYRUN=1
export CC_NOTIFY_ENV="$(mktemp)"
printf 'TELEGRAM_BOT_TOKEN=xx\nCC_NOTIFY_CHAT_ID=123\n' > "$CC_NOTIFY_ENV"
out="$(bash "$ROOT/claude/bin/cc-notify.sh" "api ◆ waiting" "review the diff" 2>&1)"
fail=0
# macOS is OFF by default (avoids duplicating iTerm) → skipped, Telegram sent
echo "$out" | grep -q 'MACOS: skipped' || { echo "FAIL macOS not skipped by default"; fail=1; }
echo "$out" | grep -q 'TELEGRAM: api ◆ waiting' || { echo "FAIL no telegram send"; fail=1; }
echo "$out" | grep -q 'review the diff' || { echo "FAIL body missing"; fail=1; }
# CC_NOTIFY_MACOS=1 → macOS notification is emitted
outm="$(CC_NOTIFY_MACOS=1 bash "$ROOT/claude/bin/cc-notify.sh" "t" "b" 2>&1)"
echo "$outm" | grep -q 'MACOS: t — b' || { echo "FAIL macOS not sent when enabled"; fail=1; }
# no token → telegram skipped
printf '' > "$CC_NOTIFY_ENV"
out2="$(bash "$ROOT/claude/bin/cc-notify.sh" "t" "b" 2>&1)"
echo "$out2" | grep -q 'TELEGRAM: skipped' || { echo "FAIL telegram not skipped"; fail=1; }
rm -f "$CC_NOTIFY_ENV"
[ $fail -eq 0 ] && echo "ALL PASS"; exit $fail
