<img src="docs/icon.png" width="128" alt="CapyWork icon: a capybara napping with a yuzu under a night sky">

# CapyWork (카피 코드 바라)

[![test](https://github.com/E-JIWON/capywork/actions/workflows/test.yml/badge.svg)](https://github.com/E-JIWON/capywork/actions/workflows/test.yml) [![release](https://img.shields.io/github/v/release/E-JIWON/capywork)](https://github.com/E-JIWON/capywork/releases/latest) ![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black) ![Swift 6](https://img.shields.io/badge/Swift-6-orange) [![MIT](https://img.shields.io/github/license/E-JIWON/capywork?color=2ea043)](LICENSE) [![Homebrew](https://img.shields.io/badge/Homebrew-e--jiwon%2Ftap-FBB040?logo=homebrew&logoColor=white)](https://github.com/E-JIWON/homebrew-tap)

[한국어](README.md) · **English**

A macOS menu bar app that gives every Claude Code session its own pixel capybara, so you can see at a glance which sessions are working and which ones are waiting on you.

![CapyWork: a capybara swimming while it works, rolling a yuzu while it waits for approval, munching grass when an answer is ready](docs/demo.gif)

| Capybara | Meaning |
| --- | --- |
| Swimming with a yuzu | Claude is working. After 7 pm a moon comes out |
| Rolling a yuzu | Waiting for your permission. After 5 minutes the yuzu flashes red and you get a second notification |
| Munching grass | A turn finished and you haven't read it yet |
| Flailing | Tool calls keep failing |
| Tossing the yuzu | The session ended (clocked out!) |
| Napping with a yuzu | Nothing going on |

## Using it

Click a capybara to open the attendance board:

- **Today's work time** plus **needs-you · working** badges (red while an approval waits)
- **5-hour and weekly plan usage**, with reset times
- **Session list**: click one to jump to it in the Claude app. Idle, read sessions quiet for 30+ minutes fold under "past sessions"
  - **Right-click → Hide** drops a session from the list and the menu bar. It comes back by itself when it waits for approval or has a new answer. It's hidden only in CapyWork; the Claude app is untouched. Unfold "past sessions" and right-click → Show to bring it back
- **This week's grass**: work time per day

**Right-click** a capybara to jump straight to the session waiting for approval. Clicking a notification opens its session too.

## Install

### Requirements

| You need | Check |
| --- | --- |
| macOS 15 (Sequoia) or later | Apple menu → About This Mac |
| Xcode Command Line Tools | `xcode-select --install` if missing |
| Claude Code | `claude --version` |

### Homebrew (recommended)

```bash
brew install e-jiwon/tap/capywork
capywork-setup
```

`brew install` builds from source on your Mac (1–2 minutes) and `capywork-setup` wires the Claude Code hooks, the login item and the grass backfill. Built on your Mac, so there's no "unidentified developer" warning. Allow notifications when it asks on first launch.

- **Update**: `brew upgrade capywork && capywork-setup`
- **Remove**: `capywork-setup --uninstall && brew uninstall capywork` (removes only what CapyWork added; your own hooks and statusLine stay)

### From source

```bash
git clone https://github.com/E-JIWON/capywork.git
cd capywork
./install.sh
```

The app lands in `~/Applications/CapyWork.app` and starts at login.

- **Update**: `git pull && ./install.sh`
- **Remove**: `./uninstall.sh`

## How it works

- **By default, no login and no network.** It only reads files on your Mac.
- **(Optional) sign in for exact numbers** — the panel's **Log in** opens a small claude.ai window inside CapyWork. Sign in **once**; the window closes itself and the panel shows the same usage and reset times as claude.ai, refreshed every 3 minutes (live). The session is kept only in CapyWork's own browser storage and "Log out" clears it. If Google sign-in is blocked, use "Continue with email".
- `capywork-setup` (or `install.sh`) registers Claude Code hooks in `~/.claude/settings.json` (backed up to `settings.json.bak-capywork`). The hooks append session events to `~/.capywork/log/`.
- Plan usage comes from the `rate_limits` Claude Code passes to its statusLine, plus the Claude app's usage history. Without statusLine data, reset times are estimated from where usage drops to zero (shown with "약", about). An existing statusLine is left alone.
- Session titles, read state, and "open session" come from the Claude desktop app's local files, **read-only**.
- On first install it backfills the grass grid from your `~/.claude/projects` transcripts.

## Good to know

- A terminal session counts as read if a terminal was in front when it finished; otherwise it shows as a new answer until you click it in the panel.
- Archiving a Claude app session in its sidebar counts as clocking out.
- Interrupting a turn (Esc) sends no end signal, so a working session with 10 minutes of silence counts as stopped (an hour while a command is still running).
- Logs older than 30 days are deleted automatically.
- A Claude app update can temporarily break titles and "open session"; everything else keeps working.

## Development

```
Sources/
  CapyKit/        UI-free core: event parsing, plan usage, which capybaras to show
  CapyWork/       the menu bar app: SessionStore (@Observable) → MenuBar / Panel components
Tests/
  CapyKitTests/   unit tests
  CapyWorkTests/  hook-to-screen integration tests, light/dark snapshots
scripts/          hook.sh · statusline.sh · backfill.py (copied to ~/.capywork by install.sh)
tools/capy.py     pixel-art generator
```

```bash
swift build        # build
swift test         # tests (snapshot images land in .build/snapshots/)
CAPYWORK_HOME=/tmp/qa CAPYWORK_SELFCHECK=/tmp/qa/out "$(swift build --show-bin-path)/CapyWork"  # status item click self-check
open Package.swift # open in Xcode
```

Every pose is in [docs/poses.png](docs/poses.png).

---

A personal project, not affiliated with Anthropic. Claude is a trademark of Anthropic.
