# hotshot

Take a screenshot, and it lands in your terminal. That's it.

**hotshot** is a tiny macOS menu bar app that captures a screenshot and automatically pastes the file path into whichever terminal session you were last using. Built for AI coding assistants like [Claude Code](https://claude.ai/code), GitHub Copilot CLI, aider, and OpenCode that accept image paths as input.

If you're like me, you use screenshots constantly to debug your work — a broken UI, a weird error message, a dashboard that doesn't look right. Normally you'd screenshot it, find the file, copy the path, switch to your terminal, paste it in. **hotshot** does all of that in one keystroke — or zero keystrokes if you use your Mac's built-in screenshot shortcuts.

## What it looks like

**With the hotkey (⇧⌘S):**
1. You're working in Claude Code (or any AI CLI) in your terminal
2. You switch to a browser and spot a bug
3. Press **⇧⌘S** — the familiar crosshair appears, select the area
4. hotshot saves the screenshot and types the file path into your terminal session
5. Your AI assistant reads the image and starts helping

**With native screenshots (⌘⇧3, ⌘⇧4, ⌘⇧5):**
1. Take a screenshot the way you always do — full screen, region, window, whatever
2. hotshot detects the new file and automatically injects its path into your last terminal session
3. That's it — keep using the shortcuts you already know

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

hotshot remembers which terminal you last clicked on. It works in two ways:

**Hotkey mode (⇧⌘S):**
1. Opens the macOS region selector (same crosshair as ⌘⇧4)
2. Saves the screenshot to your configured folder
3. Injects the file path into your last active terminal session
4. Brings the terminal back to the front

**Auto-watch mode (on by default):**
1. You take a screenshot with any native macOS shortcut (⌘⇧3, ⌘⇧4, ⌘⇧5)
2. hotshot detects the new file in your screenshot folder
3. Automatically injects the path into your last active terminal session

Paths are injected in `[bracket]` format — the same format AI CLIs like Claude Code use for drag-and-dropped files. No servers, no clipboard hacks, no browser extensions.

## Configuring

Click the camera icon in your menu bar. Everything is configurable:

| Option | Default | What it does |
|--------|---------|--------------|
| **Auto-focus terminal** | On | Brings your terminal to the front after pasting the path |
| **Auto-press Return** | Off | Sends Enter after the path (so your CLI processes it immediately) |
| **Capture full screen** | Off | Grabs the whole screen instead of letting you select a region |
| **Show notifications** | Off | Desktop notification after each capture |
| **Auto-inject new screenshots** | On | Watches your screenshot folder for new files (from ⌘⇧3/4/5) and auto-injects them |
| **Inject last screenshot** | — | Menu action: injects the most recent screenshot file from your folder |
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
No — it works *with* them. macOS system shortcuts (⌘⇧3, ⌘⇧4, ⌘⇧5) still work as normal. With auto-watch enabled (the default), hotshot detects the new screenshot and injects it automatically. hotshot's own ⇧⌘S hotkey is a separate shortcut that doesn't conflict. You can change it to anything you want from the menu bar.

**I pressed the shortcut and nothing happened.**
Make sure hotshot is running (look for the camera icon in your menu bar). Also make sure you've clicked on a terminal window at least once since launching hotshot — it needs to know which terminal to target.

**Where do the screenshots go?**
By default, wherever your Mac saves screenshots (usually Desktop or Downloads). hotshot reads your macOS screenshot location setting automatically. You can override it from the menu bar > "Change screenshot folder..."

**What format is the path injected in?**
Paths are wrapped in square brackets: `[/path/to/screenshot.png]`. This is the same format Claude Code and other AI CLIs use when you drag and drop a file into the terminal.

**Does it work over SSH?**
Not directly — hotshot runs on your local Mac. For remote workflows, check out [clipssh](https://github.com/samuellawrentz/clipssh) or [clipaste](https://github.com/hqhq1025/clipaste).

**Can I use it with VS Code's integrated terminal?**
Not yet — VS Code's terminal isn't a standalone app. For VS Code, try [vscode-terminal-image-paste](https://github.com/cybersader/vscode-terminal-image-paste).

## Technical details

Single Swift file (~650 lines), compiled to a native macOS binary. Zero dependencies — no frameworks, no packages, no runtime requirements. Just Apple's built-in APIs:

- `NSEvent` global monitors for the hotkey
- `NSWorkspace` notifications to track terminal focus
- `DispatchSource` file system watcher for auto-detecting new screenshots
- `/usr/sbin/screencapture` for the actual capture
- `NSAppleScript` to inject the path into terminal sessions
- `UserDefaults` to persist your preferences

## License

Apache-2.0 — see [LICENSE](LICENSE).
