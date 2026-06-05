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

---

## Multi-session cockpit

Run many Claude Code sessions in parallel and keep track of them all from a single
dashboard pane.

### Architecture

Each session's lifecycle hooks write a small JSON state file under
`~/.claude/cc-sessions/<session_id>.json`. A polling TUI (`cc-monitor`) reads
them all, renders a sorted list, and can focus the right iTerm tab on a keypress.
Shared helpers live in `hooks/cc-lib.sh`.

### Dashboard

Open a dedicated iTerm pane and run:

```bash
~/.claude/bin/cc-monitor
```

Rows are sorted: `error` → `waiting` → `working` → `done`. Sessions idle for
longer than `CC_STUCK_MIN` seconds (default 600) are marked `STUCK`. Press a row
number to jump to that iTerm tab; `q` quits.

```
CC COCKPIT  (number=focus, q=quit)   14:32:07

 0) waiting  -       api     30s  review the diff
 1) working  -       web    120s  add login form
 2) working  STUCK   data  1205s  backfill job
 3) done     -       db       5s  migrate schema
```

Run `--once` to print a single frame to stdout (useful for piping/tests).

### State store

State files live in `~/.claude/cc-sessions/` (auto-created by `cc-hook.sh`).
The installer sets up all hooks automatically — no manual wiring needed.

### Notifications (macOS + Telegram)

`cc-monitor` fires `cc-notify.sh` when a session transitions to `waiting` or
`error`, and when a long-running session completes.

**Setup:**

```bash
cp claude/cc-notify.env.example ~/.claude/cc-notify.env
# edit ~/.claude/cc-notify.env — fill in TELEGRAM_BOT_TOKEN + CC_NOTIFY_CHAT_ID
```

If `~/.claude/cc-notify.env` has no token, Telegram is skipped; macOS
notifications are always attempted. Set `CC_NOTIFY_DRYRUN=1` to print instead
of sending (used in tests).

### Error detection (PostToolUse)

`cc-error-scan.sh` runs after every `Bash` tool call. If the output matches any
pattern in `~/.claude/cc-error-patterns.txt`, the session's state flips to
`error` and the tab is painted red.

**Setup:**

```bash
cp claude/cc-error-patterns.example.txt ~/.claude/cc-error-patterns.txt
# edit ~/.claude/cc-error-patterns.txt — add your own ERE regexes, one per line
```

The file is gitignored so patterns (which may reference internal system names)
stay local.

### statusLine

`cc-statusline.sh` feeds Claude Code's `statusLine` feature. It reads the session
state file and renders one line:

```
api ● │ feat/cockpit │ Sonnet │ $0.42
```

The `statusLine` block is already in `settings.snippet.json` and is merged by the
installer. No extra setup needed.

---

## 멀티세션 코크핏 (한국어)

여러 Claude Code 세션을 병렬로 실행할 때 하나의 대시보드 패널로 전체를 파악합니다.

### 구조

각 세션의 라이프사이클 훅이 `~/.claude/cc-sessions/<session_id>.json`에 상태 파일을
기록합니다. `cc-monitor` TUI가 이 파일들을 폴링해 정렬된 목록을 렌더링하고, 숫자 키로
해당 iTerm 탭을 포커스할 수 있습니다. 공통 헬퍼는 `hooks/cc-lib.sh`에 있습니다.

### 대시보드

전용 iTerm 패널에서 실행:

```bash
~/.claude/bin/cc-monitor
```

행 정렬: `error` → `waiting` → `working` → `done`. `CC_STUCK_MIN`초(기본 600)
이상 `working` 상태이면 `STUCK` 마크가 붙습니다. 숫자 키로 해당 탭을 포커스, `q`로
종료합니다. `--once`로 한 프레임만 출력합니다.

### 상태 저장소

상태 파일은 `~/.claude/cc-sessions/`에 저장됩니다(`cc-hook.sh`가 자동 생성).
설치 스크립트가 모든 훅을 자동으로 구성합니다.

### 알림 (macOS + Telegram)

`waiting` / `error` 전환, 장시간 작업 완료 시 `cc-notify.sh`를 통해 알림을 보냅니다.

**설정:**

```bash
cp claude/cc-notify.env.example ~/.claude/cc-notify.env
# ~/.claude/cc-notify.env 편집 — TELEGRAM_BOT_TOKEN + CC_NOTIFY_CHAT_ID 입력
```

토큰이 없으면 Telegram은 건너뛰고 macOS 알림만 시도합니다.
`CC_NOTIFY_DRYRUN=1`로 실제 전송 없이 출력만 확인할 수 있습니다.

### 에러 감지 (PostToolUse)

`cc-error-scan.sh`가 모든 `Bash` 툴 실행 후 동작합니다. 출력이
`~/.claude/cc-error-patterns.txt`의 패턴과 일치하면 세션 상태를 `error`로 바꾸고
탭을 빨간색으로 칠합니다.

**설정:**

```bash
cp claude/cc-error-patterns.example.txt ~/.claude/cc-error-patterns.txt
# ~/.claude/cc-error-patterns.txt 편집 — 한 줄에 ERE 정규식 하나씩
```

이 파일은 gitignore 처리되어 내부 시스템명 등이 git에 올라가지 않습니다.

### statusLine

`cc-statusline.sh`가 Claude Code의 `statusLine` 기능에 연결되어 한 줄을 렌더링합니다:

```
api ● │ feat/cockpit │ Sonnet │ $0.42
```

`statusLine` 블록은 `settings.snippet.json`에 이미 포함되어 있으며 설치 스크립트가
자동으로 병합합니다.
