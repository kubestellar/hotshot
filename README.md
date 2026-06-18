# hotshot

If you're like me, you use screenshots constantly to debug your work — a broken UI, a weird error message, a dashboard that doesn't look right. You screenshot it, then you need to get that image to your AI coding assistant (Claude Code, Copilot CLI, aider, etc.) running in a terminal.

**hotshot** eliminates the middleman. It works just like the Mac screenshot tool you already know — press a shortcut, select a region — but instead of just saving the file somewhere, it automatically pastes the screenshot path directly into the last terminal session you were using. If that session has your favorite AI agent running in it, it picks up the image immediately.

Speeds things up quite a bit.

## What it looks like

1. You're working in Claude Code (or any AI CLI) in your terminal
2. You switch to a browser and spot a bug
3. Press **⇧⌘S** — the familiar crosshair appears, select the area
4. hotshot saves the screenshot and types the file path into your terminal session
5. Your AI assistant reads the image and starts helping

No dragging files around. No copy-pasting paths. No "here let me find where that screenshot went."

## Install

Requires macOS 13+ and Swift (comes with Xcode or Xcode Command Line Tools).

```bash
git clone https://github.com/kubestellar/hotshot.git
cd hotshot
swift build -c release
sudo cp .build/release/hotshot /usr/local/bin/
```

Then just run it:

```bash
hotshot
```

A small camera icon appears in your menu bar — that's hotshot running. It stays out of your way until you need it.

> Tip: Run `hotshot &` to background it so it doesn't hold your terminal.

### First-time setup

macOS will ask for two permissions the first time:
- **Screen Recording** — so it can take screenshots
- **Accessibility** — so it can type the path into your terminal

Grant both in System Settings > Privacy & Security. You only have to do this once.

## How it works

hotshot remembers which terminal you last clicked on. When you press the hotkey, it:

1. Opens the macOS region selector (same crosshair as ⌘⇧4)
2. Saves the screenshot to your configured folder
3. Types the file path into your last active terminal session
4. Brings the terminal back to the front

That's it. No servers, no clipboard hacks, no browser extensions.

## Configuring

Click the camera icon in your menu bar. Everything is configurable:

| Option | Default | What it does |
|--------|---------|--------------|
| **Auto-focus terminal** | On | Brings your terminal to the front after pasting the path |
| **Auto-press Return** | Off | Sends Enter after the path (so your CLI processes it immediately) |
| **Capture full screen** | Off | Grabs the whole screen instead of letting you select a region |
| **Show notifications** | Off | Desktop notification after each capture |
| **Change screenshot folder** | Your macOS default | Pick any folder — opens a standard folder picker |
| **Change shortcut** | ⇧⌘S | Press "Change shortcut..." and type any key combination you want |

## Works with these terminals

- **iTerm2** (recommended — uses native AppleScript for reliable injection)
- Terminal.app
- Kitty
- Alacritty
- Warp
- Ghostty

## Works with these AI assistants

Any CLI tool that accepts image file paths as input:

- [Claude Code](https://claude.ai/code)
- [GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli)
- [aider](https://aider.chat)
- [OpenCode](https://github.com/anthropics/opencode)
- Any tool where you can paste a file path and it reads the image

## FAQ

**Does it conflict with the Mac's built-in screenshot shortcuts?**
No. macOS system shortcuts (⌘⇧3, ⌘⇧4, ⌘⇧5) are handled at a lower level and can't be overridden. hotshot's default ⇧⌘S doesn't conflict. You can change it to anything you want from the menu bar.

**I pressed the shortcut and nothing happened.**
Make sure hotshot is running (look for the camera icon in your menu bar). Also make sure you've clicked on a terminal window at least once since launching hotshot — it needs to know which terminal to target.

**Where do the screenshots go?**
By default, wherever your Mac saves screenshots (usually Desktop). You can change this from the menu bar > "Change screenshot folder..."

**Does it work over SSH?**
Not directly — hotshot runs on your local Mac. For remote workflows, check out [clipssh](https://github.com/samuellawrentz/clipssh) or [clipaste](https://github.com/hqhq1025/clipaste).

**Can I use it with VS Code's integrated terminal?**
Not yet — VS Code's terminal isn't a standalone app. For VS Code, try [vscode-terminal-image-paste](https://github.com/cybersader/vscode-terminal-image-paste).

## Technical details

Single Swift file (~400 lines), compiled to a native macOS binary. Zero dependencies — no frameworks, no packages, no runtime requirements. Just Apple's built-in APIs:

- `NSEvent` global monitors for the hotkey
- `NSWorkspace` notifications to track terminal focus
- `/usr/sbin/screencapture` for the actual capture
- `NSAppleScript` to inject the path into terminal sessions
- `UserDefaults` to persist your preferences

Binary size: ~90KB.

## License

Apache-2.0 — see [LICENSE](LICENSE).
