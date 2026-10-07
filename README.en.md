# 🍊 CapyWork (카피 출근부)

[한국어](README.md) · **English**

A macOS menu bar app that gives every Claude Code session its own pixel capybara, so you can see at a glance which sessions are working and which ones are waiting on you.

![CapyWork: a capybara swimming while it works, rolling a yuzu while it waits for approval, munching grass when an answer is ready](docs/demo.gif)

| Capybara | Meaning |
| --- | --- |
| 🌊 Swimming with a yuzu | Claude is working. After 7 pm a 🌙 moon comes out |
| 🍊 Rolling a yuzu | Waiting for your permission. After 5 minutes the yuzu flashes red and you get a second notification |
| 🌿 Munching grass | A turn finished and you haven't read it yet |
| 💦 Flailing | Tool calls keep failing |
| 🎉 Tossing the yuzu | The session ended (clocked out!) |
| 💤 Napping with a yuzu | Nothing going on |

## Using it

Click a capybara to open the attendance board:

- **Needs you · Working · Today's work time**
- **5-hour and weekly plan usage**, with reset times
- **Session list**: click one to jump to it in the Claude app
- **This week's grass**: work time per day

**Right-click** a capybara to jump straight to the session waiting for approval.

## Install

### Requirements

| You need | Check |
| --- | --- |
| macOS 15 (Sequoia) or later | Apple menu → About This Mac |
| Xcode Command Line Tools | `xcode-select --install` if missing |
| Claude Code | `claude --version` |

### Steps

```bash
git clone https://github.com/E-JIWON/capywork.git
cd capywork
./install.sh
```

It builds from source on your Mac, so there's no "unidentified developer" warning, and it starts automatically at login.

- **Update**: `git pull && ./install.sh`
- **Remove**: `./uninstall.sh` (removes only what CapyWork added; your own hooks and statusLine stay)

## How it works

- **No login, no network.** It only reads files on your Mac.
- `install.sh` registers Claude Code hooks in `~/.claude/settings.json` (backed up to `settings.json.bak-capywork`). The hooks append session events to `~/.capywork/log/`.
- Plan usage comes from the `rate_limits` Claude Code passes to its statusLine, plus the Claude app's usage history. If you already have a statusLine, it's left alone (reset times may not show).
- Session titles, read state, and "open session" come from the Claude desktop app's local files, **read-only**.
- On first install it backfills the grass grid from your `~/.claude/projects` transcripts.

## Good to know

- Terminal-only sessions can't tell read from unread.
- Claude app sessions may never send a clock-out event.
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
