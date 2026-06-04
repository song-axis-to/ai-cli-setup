# Codex CLI setup

[Codex CLI](https://github.com/openai/codex) (`codex-cli`) workspace config.

Config file: **`~/.codex/config.toml`** (Codex CLI reads and writes it directly).
Reference example: [`config.example.toml`](./config.example.toml).

## Key settings

| Key | Example | Meaning |
|---|---|---|
| `model` | `"gpt-5.5"` | model to use |
| `model_reasoning_effort` | `"medium"` | reasoning depth (`minimal`/`low`/`medium`/`high`) |
| `[projects."<path>"].trust_level` | `"trusted"` | trusted dir — fewer approval prompts |
| `[mcp_servers.<name>]` | `url=...` | register an MCP server |

## Apply

Codex manages `~/.codex/config.toml`, so add only the keys you need by hand
rather than overwriting it.

```bash
# back up first if it exists
[ -f ~/.codex/config.toml ] && cp ~/.codex/config.toml ~/.codex/config.toml.bak
$EDITOR ~/.codex/config.toml
```

> Don't overwrite an existing `config.toml` — copy in only the blocks you need.
> Some keys (`trust_level`, `notice.*`, `tui.*`) are filled in by Codex itself.

## Trusted directories

Register frequently used working dirs to cut approval prompts. Never mark an
untrusted path as `trusted`.

```toml
[projects."/Users/you/Workspace/your-project"]
trust_level = "trusted"
```

## On tab color/badge

The iTerm2 tab color/badge automation lives in [`claude/`](../claude) and relies
on **Claude Code lifecycle hooks**. Codex CLI doesn't expose the same built-in
hooks, so the automatic coloring isn't provided out of the box.

- **Shared:** the left tab bar and positional tab navigation ([`iterm/`](../iterm))
  apply to every session regardless of tool.
- **Manual:** color a Codex tab via right-click → Change Tab Color, or
  `printf '\033]6;1;bg;...'`.
- **Advanced (experimental):** Codex's `notify` setting can run an external
  script on events, but the payload format varies by version — check
  `codex --help` / the official docs before relying on it.

---

# Codex CLI 설정 (한국어)

[Codex CLI](https://github.com/openai/codex) 업무환경 설정. 설정 파일은
**`~/.codex/config.toml`** (Codex가 직접 읽고 씀). 예시: [`config.example.toml`](./config.example.toml).

## 핵심 설정

| 키 | 예시 | 의미 |
|---|---|---|
| `model` | `"gpt-5.5"` | 사용 모델 |
| `model_reasoning_effort` | `"medium"` | 추론 강도 (`minimal`/`low`/`medium`/`high`) |
| `[projects."<path>"].trust_level` | `"trusted"` | 신뢰 디렉터리(승인 프롬프트 최소화) |
| `[mcp_servers.<name>]` | `url=...` | MCP 서버 등록 |

## 적용

Codex가 `config.toml`을 관리하므로 **필요한 키만 손으로 추가**하세요(덮어쓰기 금지).
신뢰하지 않는 경로에 `trusted`를 주지 말 것.

## 탭 색/배지

탭 색/배지 자동화는 [`claude/`](../claude)의 Claude 라이프사이클 훅에 의존합니다.
Codex는 동일 훅이 없어 자동 색상은 기본 미제공. 공통(탭바·이동)은 [`iterm/`](../iterm)로
모든 세션에 적용되고, 수동으로는 탭 우클릭 → Change Tab Color 또는 `printf '\033]6;...'`,
고급으로는 Codex `notify`(버전별 페이로드 상이 — 문서 확인 후 사용)가 있습니다.
