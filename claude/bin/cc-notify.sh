#!/usr/bin/env bash
# cc-notify.sh <title> <body> — Telegram (+ optional macOS) notification.
# Telegram creds from ~/.claude/cc-notify.env (TELEGRAM_BOT_TOKEN, CC_NOTIFY_CHAT_ID).
# macOS desktop notification is OFF by default: iTerm2 already shows its own
# alert, and osascript notifications misattribute to "Script Editor". Enable with
# CC_NOTIFY_MACOS=1 (env or cc-notify.env). CC_NOTIFY_DRYRUN=1 prints instead of
# sending. Failures never error out.
set -uo pipefail
title="${1:-Claude}"; body="${2:-}"
ENV_FILE="${CC_NOTIFY_ENV:-$HOME/.claude/cc-notify.env}"
DRY="${CC_NOTIFY_DRYRUN:-}"
[ -f "$ENV_FILE" ] && . "$ENV_FILE" 2>/dev/null

# macOS notification — opt-in (avoids duplicating iTerm's own notification).
case "${CC_NOTIFY_MACOS:-0}" in
  1|true|yes|on)
    if [ -n "$DRY" ]; then
      echo "MACOS: $title — $body"
    else
      osascript -e "display notification \"${body//\"/\\\"}\" with title \"${title//\"/\\\"}\"" >/dev/null 2>&1 || true
    fi
    ;;
  *)
    [ -n "$DRY" ] && echo "MACOS: skipped (CC_NOTIFY_MACOS off)"
    ;;
esac

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
