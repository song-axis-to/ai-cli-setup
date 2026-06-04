#!/usr/bin/env bash
# Sets the iTerm2 tab bar to the LEFT side (vertical tab list).
#
# iTerm2 reads its prefs at launch and OVERWRITES the plist on quit, so a
# `defaults write` while iTerm2 is running gets reverted. This script refuses to
# run while iTerm2 is open and tells you how to do it safely.
set -euo pipefail

# TabViewType:  0 = Top (default) | 1 = Bottom | 2 = Left

# iTerm's binary is /Applications/iTerm.app/Contents/MacOS/iTerm2, so `pgrep -x
# iTerm2` is unreliable (comm can be the full path). Match the app binary path
# directly; this avoids false positives from tools that merely have iTerm.app in
# their PATH (those reference .../Contents/Resources/utilities, not /MacOS/).
iterm_running() {
  pgrep -x iTerm2 >/dev/null 2>&1 && return 0
  pgrep -f '/iTerm.app/Contents/MacOS/' >/dev/null 2>&1 && return 0
  return 1
}

if iterm_running; then
  cat <<'MSG'
⚠️  iTerm2 is running — a `defaults write` now would be overwritten on quit.

Choose one:
  (A) GUI (easiest, applies immediately):
        Settings(⌘,) → Appearance → General → Tab bar location → Left
  (B) CLI:
        1. Quit iTerm2 (⌘Q)
        2. From Terminal.app, run:  ./iterm/setup.sh
        3. Relaunch iTerm2
MSG
  exit 1
fi

defaults write com.googlecode.iterm2 TabViewType -int 2
echo "✓ iTerm2 tab bar location → Left. Launch iTerm2 to see it."
