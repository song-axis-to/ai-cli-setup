# iTerm2 setup

iTerm2 environment for readable multi-session work. It also provides the stage
where the Claude hooks ([`claude/`](../claude)) paint tab colors and badges.

## 1) Vertical tab bar on the left

With many tabs, a top horizontal bar gets cramped. A left vertical list scales
better for parallel sessions.

- **GUI (recommended, immediate):** Settings(⌘,) → Appearance → General →
  **Tab bar location → `Left`**
- **CLI:** `./setup.sh` — only while **iTerm2 is quit** (a `defaults write` while
  it runs is overwritten on quit).

`TabViewType`: `0`=Top, `1`=Bottom, `2`=Left.

## 2) Positional (left/right) tab navigation

`Ctrl+Tab` cycles in **most-recently-used (MRU)** order by default
(`Cycle Tabs Forward/Backward`). For positional order:

**Built-in shortcuts (no setup, always positional):**
- `⌘ + Shift + ]` / `⌘ + Shift + [` → next / previous tab
- `⌘ + Option + →` / `⌘ + Option + ←` → next / previous tab
- `⌘ + 1..9` → jump to tab N
- `⌘ + Shift + Ctrl + →` / `←` → **move** the current tab right / left

**To keep the `Ctrl+Tab` muscle memory (GUI rebind):**
1. Settings → Keys → Key Bindings
2. `Ctrl+Tab` (currently `Cycle Tabs Forward`) → action **`Next Tab`**
3. `Ctrl+Shift+Tab` → action **`Previous Tab`**

> `Next/Previous Tab` = positional, `Cycle Tabs Forward/Backward` = MRU. Key
> bindings are keycode-based, so GUI is recommended over editing the plist.

## 3) Tab color / badge / title (on by default)

- **Tab color (OSC 6)** — painted per work type by the Claude hook. Supported by default.
- **Badge (OSC 1337 `SetBadgeFormat`)** — work type in the corner. Supported by default.
- **Tab title** — whatever title the terminal app (Claude) sends.
  If missing, check Settings → Profiles → General → **Title** components.

No separate install needed for these three; [`claude/install.sh`](../claude/install.sh)
fills in color/badge/title.

## At a glance

```
Left vertical tab bar
┌──────────────┐
│ 🔵 ● api  …  │ ← color=work type, badge=state(●working/◆waiting/✓done)+type,
│ 🟢 ◆ web     │    text=auto summary
│ 🟠 ✓ db      │
└──────────────┘
```

---

# iTerm2 설정 (한국어)

멀티 세션 가독성을 위한 iTerm2 환경. Claude 훅([`claude/`](../claude))이 보내는
탭 색/배지를 표시할 무대이기도 합니다.

## 1) 탭바를 왼쪽 세로로

- **GUI(권장, 즉시):** Settings(⌘,) → Appearance → General → **Tab bar location → `Left`**
- **CLI:** `./setup.sh` — **iTerm2 종료 상태에서만**(실행 중 변경은 종료 시 덮어써짐)
- `TabViewType`: `0`=Top, `1`=Bottom, `2`=Left

## 2) 위치 순서(좌/우) 탭 이동

`Ctrl+Tab`은 기본이 **MRU(최근 사용 순서)**. 위치 순서로 쓰려면:

- 기본 단축키(설정 불필요): `⌘+Shift+]`/`[`, `⌘+Option+→`/`←`, `⌘+1..9`,
  현재 탭 이동 `⌘+Shift+Ctrl+→`/`←`
- `Ctrl+Tab` 재매핑(GUI): Settings → Keys → Key Bindings 에서 `Ctrl+Tab`→**`Next Tab`**,
  `Ctrl+Shift+Tab`→**`Previous Tab`**

## 3) 탭 색 / 배지 / 타이틀 (기본 ON)

- 탭 색(OSC 6) · 배지(OSC 1337) · 타이틀 — 모두 iTerm2 기본 지원.
  별도 설치 없이 [`claude/install.sh`](../claude/install.sh)가 채워줍니다.
