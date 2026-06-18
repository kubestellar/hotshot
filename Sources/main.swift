import AppKit
import Carbon

// MARK: - Constants

let TERMINAL_BUNDLE_IDS: Set<String> = [
    "com.googlecode.iterm2",
    "com.apple.Terminal",
    "net.kovidgoyal.kitty",
    "io.alacritty",
    "dev.warp.Warp-Stable",
    "com.mitchellh.ghostty",
]
let REFOCUS_DELAY_SECONDS = 0.3
let HOTKEY_SIGNATURE: UInt32 =
    UInt32(UnicodeScalar("H").value) << 24
    | UInt32(UnicodeScalar("S").value) << 16
    | UInt32(UnicodeScalar("H").value) << 8
    | UInt32(UnicodeScalar("T").value)

let KEYCODE_NAMES: [UInt32: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G",
    6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
    13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1",
    19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=",
    25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 31: "O",
    32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K",
    45: "N", 46: "M", 30: "]", 33: "[", 36: "Return",
    39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".",
    48: "Tab", 49: "Space", 50: "`",
    96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
    101: "F9", 109: "F10", 103: "F11", 111: "F12",
    105: "F13", 107: "F14", 113: "F15",
    118: "F4", 120: "F2", 122: "F1",
]

// MARK: - Preferences keys

let PREF_AUTO_FOCUS = "hotshotAutoFocus"
let PREF_AUTO_RETURN = "hotshotAutoReturn"
let PREF_FULLSCREEN = "hotshotFullscreen"
let PREF_NOTIFICATIONS = "hotshotNotifications"
let PREF_AUTO_WATCH = "hotshotAutoWatch"
let SCREENSHOT_EXTENSIONS: Set<String> = ["png", "jpg", "jpeg", "tiff", "bmp", "gif", "webp"]
let WATCH_DEBOUNCE_SECONDS = 1.5
let WATCH_FILE_AGE_MAX_SECONDS = 10.0
let PREF_SCREENSHOT_DIR = "hotshotScreenshotDir"
let PREF_HOTKEY_KEYCODE = "hotshotHotkeyKeycode"
let PREF_HOTKEY_MODIFIERS = "hotshotHotkeyModifiers"

// MARK: - Helpers

func macOSScreenshotLocation() -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    task.arguments = ["read", "com.apple.screencapture", "location"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    do {
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty
        {
            return path
        }
    } catch {}
    return NSHomeDirectory() + "/Desktop"
}

func hotkeyDisplayString(keycode: UInt32, modifiers: UInt32) -> String {
    var parts: [String] = []
    if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
    if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
    if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
    if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
    let keyName = KEYCODE_NAMES[keycode] ?? "key\(keycode)"
    parts.append(keyName)
    return parts.joined()
}

func carbonModifiers(from cocoa: NSEvent.ModifierFlags) -> UInt32 {
    var mods: UInt32 = 0
    if cocoa.contains(.command) { mods |= UInt32(cmdKey) }
    if cocoa.contains(.shift) { mods |= UInt32(shiftKey) }
    if cocoa.contains(.control) { mods |= UInt32(controlKey) }
    if cocoa.contains(.option) { mods |= UInt32(optionKey) }
    return mods
}

// MARK: - Shortcut Recorder Window

class ShortcutRecorderWindow: NSWindow {
    var onRecord: ((UInt32, UInt32) -> Void)?
    var label: NSTextField!

    convenience init(onRecord: @escaping (UInt32, UInt32) -> Void) {
        let RECORDER_WIDTH = 340.0
        let RECORDER_HEIGHT = 120.0
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: RECORDER_WIDTH, height: RECORDER_HEIGHT),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        self.onRecord = onRecord
        self.title = "Record Shortcut"
        self.isReleasedWhenClosed = false
        self.level = .floating
        self.center()

        let label = NSTextField(labelWithString: "Press your desired key combination\u{2026}")
        label.font = NSFont.systemFont(ofSize: 16)
        label.alignment = .center
        label.frame = NSRect(x: 20, y: 40, width: RECORDER_WIDTH - 40, height: 60)
        self.label = label
        self.contentView?.addSubview(label)
    }

    override func keyDown(with event: NSEvent) {
        let keycode = UInt32(event.keyCode)
        let mods = carbonModifiers(from: event.modifierFlags)

        let hasModifier = mods != 0
        let isModifierOnly = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(event.keyCode)

        if hasModifier && !isModifierOnly {
            let display = hotkeyDisplayString(keycode: keycode, modifiers: mods)
            label.stringValue = "Recorded: \(display)"
            onRecord?(keycode, mods)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.close()
            }
        }
    }
}

// MARK: - App Delegate

class HotshotApp: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var lastTerminalBundleID: String?
    var lastTerminalPID: pid_t?
    var hotkeyRef: EventHotKeyRef?
    var globalMonitor: Any?
    var localMonitor: Any?
    var recorderWindow: ShortcutRecorderWindow?
    var workspace = NSWorkspace.shared
    var watcherSource: DispatchSourceFileSystemObject?
    var watcherFD: Int32 = -1
    var lastSeenScreenshots: Set<String> = []
    var watchDebounceTimer: DispatchSourceTimer?

    var autoFocus: Bool {
        get { UserDefaults.standard.object(forKey: PREF_AUTO_FOCUS) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: PREF_AUTO_FOCUS) }
    }

    var autoReturn: Bool {
        get { UserDefaults.standard.object(forKey: PREF_AUTO_RETURN) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: PREF_AUTO_RETURN) }
    }

    var fullscreen: Bool {
        get { UserDefaults.standard.object(forKey: PREF_FULLSCREEN) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: PREF_FULLSCREEN) }
    }

    var notifications: Bool {
        get { UserDefaults.standard.object(forKey: PREF_NOTIFICATIONS) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: PREF_NOTIFICATIONS) }
    }

    var autoWatch: Bool {
        get { UserDefaults.standard.object(forKey: PREF_AUTO_WATCH) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: PREF_AUTO_WATCH) }
    }

    var screenshotDir: String {
        get { UserDefaults.standard.string(forKey: PREF_SCREENSHOT_DIR) ?? macOSScreenshotLocation() }
        set { UserDefaults.standard.set(newValue, forKey: PREF_SCREENSHOT_DIR) }
    }

    var hotkeyKeycode: UInt32 {
        get {
            if UserDefaults.standard.object(forKey: PREF_HOTKEY_KEYCODE) != nil {
                return UInt32(UserDefaults.standard.integer(forKey: PREF_HOTKEY_KEYCODE))
            }
            return 1
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: PREF_HOTKEY_KEYCODE) }
    }

    var hotkeyModifiers: UInt32 {
        get {
            if UserDefaults.standard.object(forKey: PREF_HOTKEY_MODIFIERS) != nil {
                return UInt32(UserDefaults.standard.integer(forKey: PREF_HOTKEY_MODIFIERS))
            }
            return UInt32(cmdKey | shiftKey)
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: PREF_HOTKEY_MODIFIERS) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(
            atPath: screenshotDir, withIntermediateDirectories: true)

        setupStatusBar()
        registerHotkey()
        observeAppActivation()

        if let front = workspace.frontmostApplication,
            let bid = front.bundleIdentifier,
            TERMINAL_BUNDLE_IDS.contains(bid)
        {
            lastTerminalBundleID = bid
            lastTerminalPID = front.processIdentifier
            NSLog("Hotshot: seeded target = \(bid) pid=\(front.processIdentifier)")
        }

        NSLog("Hotshot: launched, hotkey=\(hotkeyDisplayString(keycode: hotkeyKeycode, modifiers: hotkeyModifiers)), screenshotDir=\(screenshotDir)")

        if autoWatch {
            startWatchingScreenshots()
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
            button.toolTip = "Hotshot \u{2014} screenshot \u{2192} terminal"
        }

        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let hotkeyLabel = hotkeyDisplayString(keycode: hotkeyKeycode, modifiers: hotkeyModifiers)
        menu.addItem(
            withTitle: "Capture Screenshot (\(hotkeyLabel))", action: #selector(captureAndInject),
            keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())

        let targetItem = NSMenuItem(title: "Target: none", action: nil, keyEquivalent: "")
        targetItem.tag = 100
        menu.addItem(targetItem)

        let dirItem = NSMenuItem(title: "Save to: \(screenshotDir)", action: nil, keyEquivalent: "")
        dirItem.isEnabled = false
        menu.addItem(dirItem)

        menu.addItem(NSMenuItem.separator())

        let focusItem = NSMenuItem(
            title: "Auto-focus terminal after paste",
            action: #selector(toggleAutoFocus), keyEquivalent: "")
        focusItem.state = autoFocus ? .on : .off
        menu.addItem(focusItem)

        let returnItem = NSMenuItem(
            title: "Auto-press Return after paste",
            action: #selector(toggleAutoReturn), keyEquivalent: "")
        returnItem.state = autoReturn ? .on : .off
        menu.addItem(returnItem)

        let fullscreenItem = NSMenuItem(
            title: "Capture full screen (default: selected area)",
            action: #selector(toggleFullscreen), keyEquivalent: "")
        fullscreenItem.state = fullscreen ? .on : .off
        menu.addItem(fullscreenItem)

        let notifyItem = NSMenuItem(
            title: "Show notifications",
            action: #selector(toggleNotifications), keyEquivalent: "")
        notifyItem.state = notifications ? .on : .off
        menu.addItem(notifyItem)

        let watchItem = NSMenuItem(
            title: "Auto-inject new screenshots",
            action: #selector(toggleAutoWatch), keyEquivalent: "")
        watchItem.state = autoWatch ? .on : .off
        menu.addItem(watchItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: "Inject last screenshot", action: #selector(injectLastScreenshot),
            keyEquivalent: "")

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: "Change screenshot folder\u{2026}", action: #selector(chooseScreenshotDir),
            keyEquivalent: "")

        let currentShortcut = hotkeyDisplayString(keycode: hotkeyKeycode, modifiers: hotkeyModifiers)
        menu.addItem(
            withTitle: "Change shortcut (\(currentShortcut))\u{2026}", action: #selector(recordShortcut),
            keyEquivalent: "")

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

    @objc func toggleFullscreen() {
        fullscreen = !fullscreen
        rebuildMenu()
    }

    @objc func toggleNotifications() {
        notifications = !notifications
        rebuildMenu()
    }

    @objc func toggleAutoWatch() {
        autoWatch = !autoWatch
        if autoWatch {
            startWatchingScreenshots()
        } else {
            stopWatchingScreenshots()
        }
        rebuildMenu()
    }

    @objc func injectLastScreenshot() {
        let dir = (screenshotDir as NSString).expandingTildeInPath
        guard let bid = lastTerminalBundleID else {
            showNotification(title: "Hotshot", body: "No terminal session tracked yet. Focus a terminal first.")
            return
        }

        guard let latest = findMostRecentScreenshot(in: dir) else {
            showNotification(title: "Hotshot", body: "No screenshot files found in \(dir)")
            return
        }

        NSLog("Hotshot: injecting last screenshot: \(latest)")
        injectPath(latest, terminalBundleID: bid)
        if autoFocus {
            focusTerminal(bundleID: bid)
        }
        showNotification(title: "Hotshot", body: "Injected \u{2192} \(latest)")
    }

    // MARK: - Screenshot Folder Watcher

    func findMostRecentScreenshot(in dir: String) -> String? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return nil }

        var newest: String?
        var newestDate = Date.distantPast

        for file in files {
            let ext = (file as NSString).pathExtension.lowercased()
            guard SCREENSHOT_EXTENSIONS.contains(ext) else { continue }
            let fullPath = (dir as NSString).appendingPathComponent(file)
            guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                  let modified = attrs[.modificationDate] as? Date else { continue }
            if modified > newestDate {
                newestDate = modified
                newest = fullPath
            }
        }
        return newest
    }

    func snapshotScreenshotFiles(in dir: String) -> Set<String> {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        var result = Set<String>()
        for file in files {
            let ext = (file as NSString).pathExtension.lowercased()
            if SCREENSHOT_EXTENSIONS.contains(ext) {
                result.insert(file)
            }
        }
        return result
    }

    func startWatchingScreenshots() {
        stopWatchingScreenshots()

        let dir = (screenshotDir as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        lastSeenScreenshots = snapshotScreenshotFiles(in: dir)

        let fd = open(dir, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("Hotshot: failed to open directory for watching: \(dir)")
            return
        }
        watcherFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .link, .attrib],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            self?.handleDirectoryChange()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        watcherSource = source
        NSLog("Hotshot: started watching \(dir) for new screenshots")
    }

    func stopWatchingScreenshots() {
        watchDebounceTimer?.cancel()
        watchDebounceTimer = nil
        watcherSource?.cancel()
        watcherSource = nil
        watcherFD = -1
        NSLog("Hotshot: stopped watching for screenshots")
    }

    func handleDirectoryChange() {
        NSLog("Hotshot: directory change detected, debouncing...")
        watchDebounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + WATCH_DEBOUNCE_SECONDS)
        timer.setEventHandler { [weak self] in
            self?.checkForNewScreenshots()
        }
        timer.resume()
        watchDebounceTimer = timer
    }

    func checkForNewScreenshots() {
        let dir = (screenshotDir as NSString).expandingTildeInPath
        let current = snapshotScreenshotFiles(in: dir)
        let newFiles = current.subtracting(lastSeenScreenshots)
        lastSeenScreenshots = current

        NSLog("Hotshot: checking for new screenshots, found \(newFiles.count) new file(s)")
        guard !newFiles.isEmpty else { return }
        NSLog("Hotshot: new files: \(newFiles)")

        let fm = FileManager.default
        var newestFile: String?
        var newestDate = Date.distantPast

        for file in newFiles {
            let fullPath = (dir as NSString).appendingPathComponent(file)
            guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                  let modified = attrs[.modificationDate] as? Date else { continue }

            let age = Date().timeIntervalSince(modified)
            guard age < WATCH_FILE_AGE_MAX_SECONDS else { continue }

            // Skip hotshot's own captures
            if file.hasPrefix("hotshot-") { continue }

            if modified > newestDate {
                newestDate = modified
                newestFile = fullPath
            }
        }

        guard let path = newestFile else { return }

        NSLog("Hotshot: watcher detected new screenshot: \(path)")

        guard let bid = lastTerminalBundleID else {
            NSLog("Hotshot: new screenshot detected but no terminal tracked")
            showNotification(title: "Hotshot", body: "Screenshot detected but no terminal session tracked")
            return
        }

        injectPath(path, terminalBundleID: bid)
        if autoFocus {
            focusTerminal(bundleID: bid)
        }
        showNotification(title: "Hotshot", body: "Auto-injected \u{2192} \((path as NSString).lastPathComponent)")
    }

    @objc func chooseScreenshotDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Select folder for hotshot screenshots"
        panel.directoryURL = URL(fileURLWithPath: screenshotDir)

        if panel.runModal() == .OK, let url = panel.url {
            screenshotDir = url.path
            rebuildMenu()
        }
    }

    @objc func recordShortcut() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        recorderWindow = ShortcutRecorderWindow { [weak self] keycode, modifiers in
            guard let self = self else { return }
            self.hotkeyKeycode = keycode
            self.hotkeyModifiers = modifiers

            self.registerHotkey()
            self.rebuildMenu()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        recorderWindow?.makeKeyAndOrderFront(nil)
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
            NSLog("Hotshot: target changed to \(bid) pid=\(app.processIdentifier)")
        }
    }

    // MARK: - Global Hotkey

    func registerHotkey() {
        unregisterHotkey()

        let targetKeycode = UInt16(hotkeyKeycode)
        let targetModifiers = cocoaModifiers(from: hotkeyModifiers)

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == targetKeycode && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == targetModifiers {
                NSLog("Hotshot: hotkey pressed (global)!")
                self?.captureAndInject()
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == targetKeycode && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == targetModifiers {
                NSLog("Hotshot: hotkey pressed (local)!")
                self?.captureAndInject()
                return nil
            }
            return event
        }

        NSLog("Hotshot: registered hotkey monitors for keycode=\(targetKeycode) modifiers=\(targetModifiers.rawValue)")
    }

    func unregisterHotkey() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    func cocoaModifiers(from carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbon & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbon & UInt32(optionKey) != 0 { flags.insert(.option) }
        return flags
    }

    static var shared: HotshotApp {
        return NSApp.delegate as! HotshotApp
    }

    // MARK: - Capture & Inject

    @objc func captureAndInject() {
        NSLog("Hotshot: captureAndInject called, target=\(lastTerminalBundleID ?? "none")")
        let dir = (screenshotDir as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)

        let timestamp = Int(Date().timeIntervalSince1970)
        let filePath = "\(dir)/hotshot-\(timestamp).png"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = fullscreen ? [filePath] : ["-i", filePath]

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
            NSLog("Hotshot: screenshot failed or cancelled (status=\(task.terminationStatus), exists=\(FileManager.default.fileExists(atPath: filePath)), path=\(filePath))")
            return
        }
        NSLog("Hotshot: screenshot saved to \(filePath)")

        guard let bid = lastTerminalBundleID else {
            showNotification(
                title: "Hotshot", body: "No terminal session tracked yet. Focus a terminal first.")
            return
        }

        injectPath(filePath, terminalBundleID: bid)

        if autoFocus {
            focusTerminal(bundleID: bid)
        }

        showNotification(title: "Hotshot", body: "Screenshot injected \u{2192} \(filePath)")
    }

    func injectPath(_ path: String, terminalBundleID bid: String) {
        let quoted = path.contains(" ") ? "\"\(path)\"" : path
        switch bid {
        case "com.googlecode.iterm2":
            injectViaITerm2(quoted)
        default:
            injectViaGenericAppleScript(quoted, bundleID: bid)
        }
    }

    func injectViaITerm2(_ path: String) {
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        var script: String
        if autoReturn {
            script = """
                tell application "iTerm2"
                    tell current session of current window
                        write text "\(escaped)"
                    end tell
                end tell
                """
        } else {
            script = """
                tell application "iTerm2"
                    tell current session of current window
                        write text "\(escaped)" newline NO
                    end tell
                end tell
                """
        }
        if autoFocus {
            script += """

                tell application "iTerm2" to activate
                """
        }
        NSLog("Hotshot: injecting into iTerm2, path=\(path)")
        NSLog("Hotshot: script=\(script)")
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
            let result = script.executeAndReturnError(&error)
            if let err = error {
                NSLog("Hotshot: AppleScript ERROR: \(err)")
            } else {
                NSLog("Hotshot: AppleScript OK, result=\(result.stringValue ?? "(none)")")
            }
        } else {
            NSLog("Hotshot: failed to create NSAppleScript")
        }
    }

    func showNotification(title: String, body: String) {
        guard notifications else { return }
        let script = """
            display notification "\(body)" with title "\(title)"
            """
        runAppleScript(script)
    }
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = HotshotApp()
app.delegate = delegate
app.run()
