# hotshot

Hotkey-triggered screenshot injection into your last active terminal session.

Take a screenshot anywhere on your Mac, and hotshot automatically pastes the file path into whichever terminal you were last using — perfect for feeding screenshots to Claude Code, GitHub Copilot CLI, aider, or any AI coding assistant.

## How it works

1. **hotshot** sits in your menu bar (no dock icon)
2. It watches which terminal you last focused
3. Press **⌃⇧⌘S** (Ctrl+Shift+Cmd+S) from anywhere
4. Select a screen region — the screenshot is saved to `/tmp/hotshot-captures/`
5. The file path is automatically typed into your last active terminal session

## Supported terminals

- iTerm2 (native integration via AppleScript)
- Terminal.app
- Kitty
- Alacritty
- Warp
- Ghostty

## Install

### Build from source

```bash
git clone https://github.com/kubestellar/hotshot.git
cd hotshot
swift build -c release
cp .build/release/hotshot /usr/local/bin/
```

### Run

```bash
hotshot
```

Or add to Login Items for auto-start.

## Requirements

- macOS 13+ (Ventura or later)
- Accessibility permissions (System Settings → Privacy & Security → Accessibility)
- Screen Recording permissions (for `screencapture`)

## How it injects

- **iTerm2**: Uses AppleScript to write text to the current session
- **Other terminals**: Activates the terminal window and uses System Events keystrokes

## Configuration

Currently configured via constants in the source. Planned:
- Configurable hotkey
- Configurable screenshot directory
- Per-terminal injection method

## License

Apache-2.0
