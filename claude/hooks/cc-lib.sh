#!/usr/bin/env bash
# cc-lib.sh — shared helpers for cockpit hooks. SOURCE this; don't execute.

# Resolve the iTerm pane tty by walking the process tree (claude runs hooks
# without a controlling tty, esp. over SSH). CLAUDE_ITERM_TTY overrides (tests).
cc_resolve_tty() {
  [ -n "${CLAUDE_ITERM_TTY:-}" ] && { printf '%s' "$CLAUDE_ITERM_TTY"; return; }
  local pid="$$" ppid t
  while [ "${pid:-0}" -gt 1 ]; do
    read -r ppid t <<<"$(ps -o ppid=,tty= -p "$pid" 2>/dev/null)"
    case "$t" in ttys*) printf '/dev/%s' "$t"; return ;; esac
    pid="$ppid"
  done
  printf '/dev/tty'
}

# Map a directory basename to a short work "type" (generic examples).
type_for() {
  case "$1" in
    *-api|*api*)   echo api    ;;
    *-web|*web*)   echo web    ;;
    *worker*)      echo worker ;;
    *data*)        echo data   ;;
    *db*|*migrat*) echo db     ;;
    *infra*)       echo infra  ;;
    *docs*)        echo docs   ;;
    *)             echo "$1"   ;;
  esac
}

# Map a type to a tab color "R G B".
color_for() {
  case "$1" in
    api)    echo "40 110 230"  ;;
    web)    echo "40 170 80"   ;;
    worker) echo "150 80 220"  ;;
    data)   echo "0 170 180"   ;;
    db)     echo "230 130 0"   ;;
    infra)  echo "200 160 0"   ;;
    docs)   echo "210 60 160"  ;;
    *)      echo "120 120 120" ;;
  esac
}

# Badge glyph per session state.
glyph_for() {
  case "$1" in
    working) echo "●" ;; waiting) echo "◆" ;; done) echo "✓" ;;
    error)   echo "✗" ;; *) echo "·" ;;
  esac
}

# Private overrides (not committed): may redefine type_for / color_for.
[ -f "$HOME/.claude/cc-tab-overrides.sh" ] && . "$HOME/.claude/cc-tab-overrides.sh"

# Paint iTerm tab color (OSC 6) + badge (OSC 1337) for (state,type) to a tty.
# No-op if the tty can't be opened. "waiting" overrides color to orange.
cc_paint_tab() {
  local state="$1" type="$2" tty="$3" r g b
  ( printf '' > "$tty" ) 2>/dev/null || return 0
  read -r r g b <<<"$(color_for "$type")"
  [ "$state" = waiting ] && { r=240; g=150; b=0; }
  {
    printf '\033]6;1;bg;red;brightness;%d\a\n'   "$r"
    printf '\033]6;1;bg;green;brightness;%d\a\n' "$g"
    printf '\033]6;1;bg;blue;brightness;%d\a\n'  "$b"
    printf '\033]1337;SetBadgeFormat=%s\a\n' \
      "$(printf '%s %s' "$(glyph_for "$state")" "$type" | base64 | tr -d '\n')"
  } >> "$tty" 2>/dev/null
}
