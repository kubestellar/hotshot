import AppKit
import Carbon
import UserNotifications

// MARK: - Constants

let SCREENSHOT_DIR = "/tmp/hotshot-captures"
let DEFAULT_HOTKEY_KEYCODE: UInt32 = 1  // 's' key
let DEFAULT_HOTKEY_MODIFIERS: UInt32 = UInt32(cmdKey | shiftKey | controlKey)
let TERMINAL_BUNDLE_IDS: Set<String> = [
    "com.googlecode.iterm2",
    "com.apple.Terminal",
    "net.kovidgoyal.kitty",
    "io.alacritty",
    "dev.warp.Warp-Stable",
    "com.mitchellh.ghostty",
]
let REFOCUS_DELAY_SECONDS = 0.3

// MARK: - Preferences (persisted to UserDefaults)

let PREF_AUTO_FOCUS = "hotshotAutoFocus"
let PREF_AUTO_RETURN = "hotshotAutoReturn"

// MARK: - App Delegate

class HotshotApp: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var lastTerminalBundleID: String?
    var lastTerminalPID: pid_t?
    var hotkeyRef: EventHotKeyRef?
    var workspace = NSWorkspace.shared

    var autoFocus: Bool {
        get { UserDefaults.standard.object(forKey: PREF_AUTO_FOCUS) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: PREF_AUTO_FOCUS) }
    }

    var autoReturn: Bool {
        get { UserDefaults.standard.object(forKey: PREF_AUTO_RETURN) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: PREF_AUTO_RETURN) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(
            atPath: SCREENSHOT_DIR, withIntermediateDirectories: true)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }

        setupStatusBar()
        setupHotkey()
        observeAppActivation()

        if let front = workspace.frontmostApplication,
            let bid = front.bundleIdentifier,
            TERMINAL_BUNDLE_IDS.contains(bid)
        {
            lastTerminalBundleID = bid
            lastTerminalPID = front.processIdentifier
        }
    }

    // MARK: - Status Bar

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let img = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "Hotshot")
            {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "HS"
            }
            button.toolTip = "Hotshot — screenshot → terminal"
        }

        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()

        menu.addItem(
            withTitle: "Capture Screenshot (⌃⇧⌘S)", action: #selector(captureAndInject),
            keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())

        let targetItem = NSMenuItem(title: "Target: none", action: nil, keyEquivalent: "")
        targetItem.tag = 100
        menu.addItem(targetItem)

        menu.addItem(NSMenuItem.separator())

        let focusItem = NSMenuItem(
            title: "Auto-focus terminal after paste",
            action: #selector(toggleAutoFocus), keyEquivalent: "")
        focusItem.state = autoFocus ? .on : .off
        focusItem.tag = 200
        menu.addItem(focusItem)

        let returnItem = NSMenuItem(
            title: "Auto-press Return after paste",
            action: #selector(toggleAutoReturn), keyEquivalent: "")
        returnItem.state = autoReturn ? .on : .off
        returnItem.tag = 201
        menu.addItem(returnItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: "Quit Hotshot", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")

        statusItem.menu = menu
        updateTargetLabel()
    }

    @objc func toggleAutoFocus() {
        autoFocus = !autoFocus
        rebuildMenu()
    }

    @objc func toggleAutoReturn() {
        autoReturn = !autoReturn
        rebuildMenu()
    }

    func updateTargetLabel() {
        if let bid = lastTerminalBundleID,
            let menuItem = statusItem.menu?.item(withTag: 100)
        {
            let name = bid.split(separator: ".").last.map(String.init) ?? bid
            menuItem.title = "Target: \(name) (pid \(lastTerminalPID ?? 0))"
        }
    }

    // MARK: - App Activation Observer

    func observeAppActivation() {
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication,
            let bid = app.bundleIdentifier
        else { return }

        if TERMINAL_BUNDLE_IDS.contains(bid) {
            lastTerminalBundleID = bid
            lastTerminalPID = app.processIdentifier
            updateTargetLabel()
        }
    }

    // MARK: - Global Hotkey

    func setupHotkey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(
            UInt32(UnicodeScalar("H").value) << 24
                | UInt32(UnicodeScalar("S").value) << 16
                | UInt32(UnicodeScalar("H").value) << 8
                | UInt32(UnicodeScalar("T").value))
        hotKeyID.id = 1

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            HotshotApp.shared.captureAndInject()
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)

        RegisterEventHotKey(
            DEFAULT_HOTKEY_KEYCODE,
            DEFAULT_HOTKEY_MODIFIERS,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }

    static var shared: HotshotApp {
        return NSApp.delegate as! HotshotApp
    }

    // MARK: - Capture & Inject

    @objc func captureAndInject() {
        let timestamp = Int(Date().timeIntervalSince1970)
        let filePath = "\(SCREENSHOT_DIR)/hotshot-\(timestamp).png"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", filePath]

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            showNotification(title: "Hotshot", body: "Failed to launch screencapture")
            return
        }

        guard task.terminationStatus == 0,
            FileManager.default.fileExists(atPath: filePath)
        else {
            return
        }

        guard let bid = lastTerminalBundleID else {
            showNotification(
                title: "Hotshot", body: "No terminal session tracked yet. Focus a terminal first.")
            return
        }

        injectPath(filePath, terminalBundleID: bid)

        if autoFocus {
            focusTerminal(bundleID: bid)
        }

        showNotification(title: "Hotshot", body: "Screenshot injected → \(filePath)")
    }

    func injectPath(_ path: String, terminalBundleID bid: String) {
        switch bid {
        case "com.googlecode.iterm2":
            injectViaITerm2(path)
        default:
            injectViaGenericAppleScript(path, bundleID: bid)
        }
    }

    func injectViaITerm2(_ path: String) {
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        var script = """
            tell application "iTerm2"
                tell current session of current window
                    write text "\(escaped)" newline \(autoReturn ? "yes" : "no")
                end tell
            end tell
            """
        if autoFocus {
            script += """

                tell application "iTerm2" to activate
                """
        }
        runAppleScript(script)
    }

    func injectViaGenericAppleScript(_ path: String, bundleID: String) {
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        var script = """
            tell application id "\(bundleID)"
                activate
            end tell
            delay \(REFOCUS_DELAY_SECONDS)
            tell application "System Events"
                keystroke "\(escaped)"
            """
        if autoReturn {
            script += """

                    keystroke return
                """
        }
        script += """

            end tell
            """
        runAppleScript(script)
    }

    func focusTerminal(bundleID: String) {
        let script = """
            tell application id "\(bundleID)"
                activate
            end tell
            """
        runAppleScript(script)
    }

    func runAppleScript(_ source: String) {
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            script.executeAndReturnError(&error)
            if let err = error {
                NSLog("Hotshot AppleScript error: \(err)")
            }
        }
    }

    func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = HotshotApp()
app.delegate = delegate
app.run()
