# hotshot

Take a screenshot, and it lands in your terminal. That's it.

**hotshot** is a tiny macOS menu bar app that captures a screenshot and automatically pastes the file path into whichever terminal session you were last using. Built for AI coding assistants like [Claude Code](https://claude.ai/code), GitHub Copilot CLI, aider, and OpenCode that accept image paths as input.

## Demo

1. You're working in Claude Code in iTerm2
2. You switch to a browser to look at a bug
3. Press **⇧⌘S** — crosshair appears, select the region
4. The screenshot file path is typed into your Claude Code session automatically
5. Claude Code reads the image and you're in business

## Install

### Build from source

```bash
git clone https://github.com/kubestellar/hotshot.git
cd hotshot
swift build -c release
sudo cp .build/release/hotshot /usr/local/bin/
```

### Run

```bash
hotshot
```

A camera icon appears in your menu bar. To auto-start on login, add it to System Settings > General > Login Items.

## How it works

1. **hotshot** sits in your menu bar with no dock icon
2. It watches which terminal app you last focused
3. Press the hotkey (default **⇧⌘S**) from anywhere
4. A crosshair appears — select a screen region (or captures full screen if configured)
5. The screenshot is saved and the file path is injected into your last active terminal session

## Menu bar options

Click the menu bar icon to configure:

| Option | Default | Description |
|--------|---------|-------------|
| Auto-focus terminal after paste | On | Brings the terminal to the front after injecting the path |
| Auto-press Return after paste | Off | Automatically hits Enter after pasting (sends the path immediately) |
| Capture full screen | Off | Captures the entire screen instead of a selected region |
| Change screenshot folder | macOS default | Choose where screenshots are saved (defaults to your macOS screenshot location) |
| Shortcut | ⇧⌘S | Pick from preset hotkey combinations |

## Supported terminals

| Terminal | Injection method |
|----------|-----------------|
| iTerm2 | Native AppleScript (`write text` to current session) |
| Terminal.app | System Events keystrokes |
| Kitty | System Events keystrokes |
| Alacritty | System Events keystrokes |
| Warp | System Events keystrokes |
| Ghostty | System Events keystrokes |

## Requirements

- macOS 13+ (Ventura or later)
- Accessibility permissions (System Settings > Privacy & Security > Accessibility) — needed for System Events keystrokes
- Screen Recording permissions — needed for `screencapture`

## How it's built

Single Swift file, compiled to a native binary. No frameworks, no package dependencies, no runtime requirements. Uses:

- `NSWorkspace` notifications to track terminal focus
- Carbon `RegisterEventHotKey` for the global hotkey
- `/usr/sbin/screencapture` for the actual capture
- `NSAppleScript` to inject the path into terminal sessions
- `UserDefaults` to persist preferences

Binary size: ~90KB.

## FAQ

**Does it conflict with macOS ⌘⇧5?**
No — ⌘⇧5 opens the macOS screenshot toolbar. hotshot's default is ⇧⌘S. You can change the shortcut from the menu bar.

**What if I haven't focused a terminal yet?**
You'll get a notification saying "No terminal session tracked yet." Just click on your terminal window once, then try again.

**Does it work over SSH?**
Not directly. For SSH workflows, check out [clipssh](https://github.com/samuellawrentz/clipssh) or [clipaste](https://github.com/hqhq1025/clipaste).

**Can I use it with VS Code's integrated terminal?**
Not yet — VS Code's terminal isn't a standalone terminal app. For VS Code, try [vscode-terminal-image-paste](https://github.com/cybersader/vscode-terminal-image-paste).

## License

Apache-2.0 — see [LICENSE](LICENSE).
