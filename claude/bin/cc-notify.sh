#!/usr/bin/env bash
# cc-notify.sh <title> <body> — macOS + Telegram notification.
# Telegram creds from ~/.claude/cc-notify.env (TELEGRAM_BOT_TOKEN, CC_NOTIFY_CHAT_ID).
# CC_NOTIFY_DRYRUN=1 prints instead of sending. Failures never error out.
set -uo pipefail
title="${1:-Claude}"; body="${2:-}"
ENV_FILE="${CC_NOTIFY_ENV:-$HOME/.claude/cc-notify.env}"
DRY="${CC_NOTIFY_DRYRUN:-}"
[ -f "$ENV_FILE" ] && . "$ENV_FILE" 2>/dev/null

# macOS notification
if [ -n "$DRY" ]; then
  echo "MACOS: $title — $body"
else
  osascript -e "display notification \"${body//\"/\\\"}\" with title \"${title//\"/\\\"}\"" >/dev/null 2>&1 || true
fi

# Telegram
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${CC_NOTIFY_CHAT_ID:-}" ]; then
  if [ -n "$DRY" ]; then
    echo "TELEGRAM: $title — $body"
  else
    curl -s -m 5 -o /dev/null \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=${CC_NOTIFY_CHAT_ID}" \
      --data-urlencode "text=${title} — ${body}" >/dev/null 2>&1 || true
  fi
else
  echo "TELEGRAM: skipped (no token/chat id)"
fi
exit 0
