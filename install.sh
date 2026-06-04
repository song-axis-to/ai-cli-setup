#!/usr/bin/env bash
# Top-level installer for ai-cli-setup. Runs each tool's setup with confirmation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ask() { read -r -p "$1 [y/N] " a; [[ "$a" =~ ^[Yy]$ ]]; }

echo "== ai-cli-setup =="
echo

if ask "Claude Code 훅 + 한국어 타이틀 설정을 적용할까요?"; then
  "$SCRIPT_DIR/claude/install.sh"
fi
echo

if ask "iTerm2 탭바를 왼쪽으로 설정할까요? (iTerm2 종료 상태에서만 적용)"; then
  "$SCRIPT_DIR/iterm/setup.sh" || true
fi
echo

echo "Codex 는 수동 설정입니다 → codex/README.md 참고:"
echo "  $SCRIPT_DIR/codex/README.md"
echo
echo "완료. Claude Code 에서 /hooks 를 한 번 열거나 재시작하면 훅이 로드됩니다."
