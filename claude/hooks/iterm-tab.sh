#!/usr/bin/env bash
# iterm-tab.sh <state> — paint the current iTerm tab by work type / session state.
# Thin wrapper over cc-lib.sh so logic stays DRY with cc-hook.sh.
state="${1:-idle}"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cc-lib.sh"
cwd="$PWD"
if [ ! -t 0 ]; then
  c="$(cat 2>/dev/null | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  [ -n "$c" ] && cwd="$c"
fi
cc_paint_tab "$state" "$(type_for "$(basename "$cwd")")" "$(cc_resolve_tty)"
exit 0
