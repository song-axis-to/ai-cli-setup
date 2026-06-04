# ai-cli-setup

Workspace setup for AI CLIs — **iTerm2 + Claude Code + Codex CLI**.

Terminal configuration and per-CLI install scripts that make many parallel AI
sessions easy to tell apart at a glance.

## Core idea

When you run several AI CLI sessions at once, the **tab alone** should tell you
what each one is doing, where, and in what state.

| Signal | Meaning | Mechanism |
|---|---|---|
| **Tab color** | Work type — `api` 🔵 / `web` 🟢 / `db` 🟠 … | Claude Code hook → iTerm2 OSC 6 |
| **Badge** | Session state + type — `● api`(working) / `◆`(waiting) / `✓`(done) | Claude Code hook → iTerm2 OSC 1337 |
| **Tab title** | Auto summary of the session's work | Claude Code (`language` setting) |
| **Tab bar** | Left, vertical | iTerm2 `TabViewType` |

## What's inside

| Directory | Contents |
|---|---|
| [`iterm/`](./iterm) | Left vertical tab bar, positional tab navigation, color/badge stage |
| [`claude/`](./claude) | Claude Code hooks (state→color, type→badge) + title language setting |
| [`codex/`](./codex) | Codex CLI `config.toml` essentials |

## Quick start

```bash
git clone <your-repo-url>
cd ai-cli-setup

./install.sh             # interactive — confirms each step

# or apply individually
./claude/install.sh      # Claude hooks + settings (backs up settings.json, jq-merges)
./iterm/setup.sh         # iTerm2 left tab bar (run while iTerm2 is quit)
cat ./codex/README.md    # Codex is a manual guide
```

## Requirements

- macOS + iTerm2
- [Claude Code](https://claude.com/claude-code) CLI
- [Codex CLI](https://github.com/openai/codex) (optional)
- `jq` (`brew install jq`) — used by the Claude installer for safe JSON merging

## Safety

- Installers never blind-overwrite: existing config is backed up (`*.bak.<timestamp>`) and merged.
- iTerm2 reverts preference changes made while it is running, so iTerm steps are applied via GUI or while iTerm2 is quit.

---

# ai-cli-setup (한국어)

AI CLI 업무환경 설정 모음 — **iTerm2 + Claude Code + Codex CLI**.

여러 AI 세션을 동시에 띄울 때 **탭만 보고도** 무엇을 / 어디서 / 어떤 상태로 하는지
구분되게 만드는 터미널 설정과 CLI별 설치 스크립트.

## 핵심 아이디어

| 신호 | 의미 | 메커니즘 |
|---|---|---|
| **탭 색** | 작업 유형 — `api` 🔵 / `web` 🟢 / `db` 🟠 … | Claude Code 훅 → iTerm2 OSC 6 |
| **배지(Badge)** | 세션 상태 + 유형 — `● api`(작업중) / `◆`(입력대기) / `✓`(완료) | Claude Code 훅 → iTerm2 OSC 1337 |
| **탭 타이틀** | 세션 작업 자동 요약 | Claude Code (`language` 설정) |
| **탭바 위치** | 왼쪽 세로 정렬 | iTerm2 `TabViewType` |

## 구성

| 디렉터리 | 내용 |
|---|---|
| [`iterm/`](./iterm) | 탭바 왼쪽 세로, 위치순서 탭 이동, 색/배지 표시 무대 |
| [`claude/`](./claude) | Claude Code 훅(상태→색, 유형→배지) + 타이틀 언어 설정 |
| [`codex/`](./codex) | Codex CLI `config.toml` 핵심 |

## 빠른 시작 / 요구사항 / 안전성

위 영문 섹션과 동일합니다. 설치 스크립트는 기존 설정을 **백업 후 병합**하며,
iTerm2 설정은 실행 중 변경 시 되돌아가므로 GUI 또는 종료 상태에서 적용합니다.
`jq` 필요 (`brew install jq`).
