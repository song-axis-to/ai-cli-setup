#!/usr/bin/env bash
# Installs the Claude Code tab-coloring hook + merges settings (language + hooks).
# Safe: backs up existing settings.json and deep-merges via jq (never blind-overwrites).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"
SNIPPET="$SCRIPT_DIR/settings.snippet.json"

command -v jq >/dev/null 2>&1 || { echo "✗ jq is required:  brew install jq"; exit 1; }

# 1) install the helper hook script
mkdir -p "$HOOKS_DIR"
install -m 0755 "$SCRIPT_DIR/hooks/iterm-tab.sh" "$HOOKS_DIR/iterm-tab.sh"
echo "✓ installed $HOOKS_DIR/iterm-tab.sh"

# cockpit: shared lib + state hook + error scanner
install -m 0644 "$SCRIPT_DIR/hooks/cc-lib.sh"        "$HOOKS_DIR/cc-lib.sh"
install -m 0755 "$SCRIPT_DIR/hooks/cc-hook.sh"       "$HOOKS_DIR/cc-hook.sh"
install -m 0755 "$SCRIPT_DIR/hooks/cc-error-scan.sh" "$HOOKS_DIR/cc-error-scan.sh"
install -m 0644 "$SCRIPT_DIR/cc-error-patterns.example.txt" "$CLAUDE_DIR/cc-error-patterns.example.txt"
echo "✓ installed cc-lib.sh + cc-hook.sh + cc-error-scan.sh"

# cockpit: bin (monitor, focus, notifier, statusline)
BIN_DIR="$CLAUDE_DIR/bin"
mkdir -p "$BIN_DIR"
for b in cc-monitor focus_session.applescript cc-notify.sh; do
  install -m 0755 "$SCRIPT_DIR/bin/$b" "$BIN_DIR/$b"
done
install -m 0644 "$SCRIPT_DIR/cc-notify.env.example" "$CLAUDE_DIR/cc-notify.env.example"
echo "✓ installed cockpit bin → $BIN_DIR (run: $BIN_DIR/cc-monitor)"

# 2) merge language + hooks into settings.json (backup first)
ts="$(date +%Y%m%d-%H%M%S)"
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak.$ts"
  echo "✓ backed up -> $(basename "$SETTINGS").bak.$ts"
  # deep merge: snippet wins on conflicting keys; existing top-level keys preserved.
  merged="$(jq -s '.[0] * .[1]' "$SETTINGS" "$SNIPPET")"
else
  echo "· no existing settings.json — creating from snippet"
  merged="$(cat "$SNIPPET")"
fi
printf '%s\n' "$merged" | jq . > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
echo "✓ merged hooks + language into settings.json"

cat <<'MSG'

Done.
  • Tab color  = work type      (api 🔵 / web 🟢 / db 🟠 ... ; waiting→🟠)
  • Badge      = state + type    (● working / ◆ waiting / ✓ done, e.g. "● api")
  • Title      = auto summary    (language setting)
  • Private project mappings: ~/.claude/cc-tab-overrides.sh (not committed)

Activate: open /hooks in Claude Code once (or restart) so the new hooks load.
MSG
