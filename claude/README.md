# Claude Code setup

Reflect each session's work type / state on its iTerm2 tab, and have the tab
title auto-summarize the work.

## Install

```bash
./install.sh        # needs jq (brew install jq)
```

After installing, open **`/hooks` once (or restart)** in Claude Code so the new
hooks load.

## What it does

### 1) Tab color = work type, badge = state (+ type)

`hooks/iterm-tab.sh` sends iTerm2 OSC escape sequences directly to the terminal
device (works regardless of the hook's captured stdout; no-ops with no usable tty
→ headless/SDK safe).

> **tty auto-resolution:** Claude Code runs hooks **without a controlling
> terminal** (especially over SSH), so `/dev/tty` is often "Device not
> configured" and color/badge silently vanish. The script walks up the process
> tree to the pane tty (`/dev/ttysNNN`) the `claude` process is attached to and
> writes there. Over SSH that pty forwards the OSC to the client's iTerm2.
> Override with `CLAUDE_ITERM_TTY` for testing.

**Tab color = work type** (inferred from cwd, stable for the session):

| Type | Color | | Type | Color |
|---|---|---|---|---|
| `api` | 🔵 blue | | `infra` | 🟡 amber |
| `web` | 🟢 green | | `docs` | 🩷 magenta |
| `data` | 🩵 cyan | | (other) | 🩶 gray |
| `db` | 🟠 orange | | | |
| `worker` | 🟣 purple | | | |

These mappings are **generic examples**. Edit the `type_for()` / `color_for()`
functions in `hooks/iterm-tab.sh`, or keep your project names **private** by
defining your own `type_for()` / `color_for()` in `~/.claude/cc-tab-overrides.sh`
(sourced automatically, never committed).

**Badge = state glyph + type** (updated per event, e.g. `● api`):

| Event | State | Badge glyph |
|---|---|---|
| `SessionStart` | idle | `·` |
| `UserPromptSubmit` | working | `●` |
| `Notification` (permission/input) | waiting | `◆` |
| `Stop` (turn end) | done | `✓` |

> Color is fixed per type, so "does this tab need me?" is read from the badge
> glyph (`◆`). The script also paints the tab **orange** while `waiting`,
> overriding the type color, so an attention-needing tab stands out.

### 2) Title = auto summary

`settings.snippet.json` sets a `language`. Claude Code generates the session's
work summary in that language and shows it as the tab title (OSC 0/2). It also
sets the assistant's response language.

> To keep responses in English, remove `language` and use `/rename <name>` per
> session instead (may flicker against Claude's auto title).

## Customize

- **Add error=red**: add a `PostToolUseFailure` hook calling
  `$HOME/.claude/hooks/iterm-tab.sh error` (noisy if your tools fail often → off by default).
- **Reset color on exit**: add a `SessionEnd` hook + a reset branch
  (`\033]6;1;bg;*;default\a`).
- Disable/edit: the `/hooks` menu.

## Files

| File | Role |
|---|---|
| `hooks/iterm-tab.sh` | type→color, state→badge (sends OSC) |
| `settings.snippet.json` | `language` + `hooks` to merge |
| `install.sh` | install hook + safe settings.json merge |

---

# Claude Code 설정 (한국어)

세션의 작업 유형/상태를 iTerm2 탭에 반영하고, 타이틀을 작업 요약으로 자동 표시.

## 설치

```bash
./install.sh        # jq 필요 (brew install jq)
```

설치 후 Claude Code에서 **`/hooks`를 한 번 열거나 재시작**하면 훅이 로드됩니다.

## 동작

### 1) 탭 색 = 작업 유형, 배지 = 상태(+유형)

`hooks/iterm-tab.sh`가 iTerm2 OSC 이스케이프를 터미널 디바이스로 직접 전송합니다.

> **tty 자동 탐색:** Claude Code는 훅을 **제어 터미널 없이** 실행해서(특히 SSH)
> `/dev/tty`가 막히는 경우가 많습니다. 그래서 프로세스 트리를 거슬러 올라가
> `claude`가 붙은 pane tty(`/dev/ttysNNN`)를 찾아 거기에 씁니다. SSH면 그 pty가
> OSC를 클라이언트 iTerm2로 포워딩. 테스트는 `CLAUDE_ITERM_TTY`로 지정.

**탭 색 = 작업 유형**(cwd로 추론, 세션 내내 고정). 위 표의 `api`/`web`/`data`/`db`/
`worker`/`infra`/`docs` 색은 **제네릭 예시**입니다. `hooks/iterm-tab.sh`의
`type_for()`/`color_for()`를 수정하거나, 프로젝트명을 **비공개**로 두려면
`~/.claude/cc-tab-overrides.sh`에 본인용 `type_for()`/`color_for()`를 정의하세요
(자동 소싱, git에 안 올라감).

**배지 = 상태 글리프 + 유형**(이벤트로 갱신, 예: `● api`):
`SessionStart`→`·`(idle), `UserPromptSubmit`→`●`(작업중), `Notification`→`◆`(대기),
`Stop`→`✓`(완료). 색은 유형 고정이라 대기 여부는 글리프(`◆`)로 보며, `waiting`일 때만
탭을 **주황**으로 덮어써 눈에 띄게 합니다.

### 2) 타이틀 = 자동 요약

`settings.snippet.json`의 `language` 설정으로 세션 요약이 해당 언어로 생성돼 탭
타이틀이 됩니다(응답 언어도 동일). 영어 응답 유지를 원하면 `language`를 빼고 세션마다
`/rename <이름>`을 쓰세요.

## 커스터마이즈 / 파일

- 에러=빨강: `PostToolUseFailure` 훅으로 `... iterm-tab.sh error` 추가(잦은 실패 시 노이즈 → 기본 제외).
- 종료 시 색 리셋: `SessionEnd` 훅 + 리셋 분기(`\033]6;1;bg;*;default\a`).
- 끄기/수정: `/hooks` 메뉴.
- 파일: `hooks/iterm-tab.sh`(색/배지), `settings.snippet.json`(language+hooks), `install.sh`(병합 설치).
