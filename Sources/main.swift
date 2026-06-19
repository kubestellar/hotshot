import AppKit

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

// MARK: - Preferences keys

let PREF_AUTO_FOCUS = "hotshotAutoFocus"
let PREF_AUTO_RETURN = "hotshotAutoReturn"
let PREF_NOTIFICATIONS = "hotshotNotifications"
let PREF_AUTO_WATCH = "hotshotAutoWatch"
let PREF_CLIPBOARD_WATCH = "hotshotClipboardWatch"
let SCREENSHOT_EXTENSIONS: Set<String> = ["png", "jpg", "jpeg", "tiff", "bmp", "gif", "webp"]
let WATCH_DEBOUNCE_SECONDS = 1.5
let WATCH_FILE_AGE_MAX_SECONDS = 10.0
let CLIPBOARD_POLL_INTERVAL_SECONDS = 0.5
let PREF_SCREENSHOT_DIR = "hotshotScreenshotDir"

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

// MARK: - App Delegate

class HotshotApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var lastTerminalBundleID: String?
    var lastTerminalPID: pid_t?
    var lastTerminalName: String?
    var workspace = NSWorkspace.shared
    var watcherSource: DispatchSourceFileSystemObject?
    var watcherFD: Int32 = -1
    var lastSeenScreenshots: Set<String> = []
    var watchDebounceTimer: DispatchSourceTimer?
    var clipboardTimer: Timer?
    var lastClipboardChangeCount: Int = 0

    var autoFocus: Bool {
        get { UserDefaults.standard.object(forKey: PREF_AUTO_FOCUS) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: PREF_AUTO_FOCUS) }
    }

    var autoReturn: Bool {
        get { UserDefaults.standard.object(forKey: PREF_AUTO_RETURN) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: PREF_AUTO_RETURN) }
    }

    var notifications: Bool {
        get { UserDefaults.standard.object(forKey: PREF_NOTIFICATIONS) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: PREF_NOTIFICATIONS) }
    }

    var autoWatch: Bool {
        get { UserDefaults.standard.object(forKey: PREF_AUTO_WATCH) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: PREF_AUTO_WATCH) }
    }

    var clipboardWatch: Bool {
        get { UserDefaults.standard.object(forKey: PREF_CLIPBOARD_WATCH) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: PREF_CLIPBOARD_WATCH) }
    }

    var screenshotDir: String {
        get { UserDefaults.standard.string(forKey: PREF_SCREENSHOT_DIR) ?? macOSScreenshotLocation() }
        set { UserDefaults.standard.set(newValue, forKey: PREF_SCREENSHOT_DIR) }
    }


    func setTarget(_ app: NSRunningApplication) {
        lastTerminalBundleID = app.bundleIdentifier
        lastTerminalPID = app.processIdentifier
        lastTerminalName = windowTitle(for: app) ?? app.localizedName ?? "unknown"
    }

    func windowTitle(for app: NSRunningApplication) -> String? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindow: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success else {
            return nil
        }
        var title: AnyObject?
        guard AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else {
            return nil
        }
        return title as? String
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(
            atPath: screenshotDir, withIntermediateDirectories: true)

        setupStatusBar()
        observeAppActivation()

        if let front = workspace.frontmostApplication,
            let bid = front.bundleIdentifier,
            TERMINAL_BUNDLE_IDS.contains(bid)
        {
            setTarget(front)
            NSLog("Hotshot: seeded target = \(lastTerminalName ?? "unknown")")
        } else {
            for app in workspace.runningApplications where !app.isTerminated {
                if let bid = app.bundleIdentifier, TERMINAL_BUNDLE_IDS.contains(bid) {
                    setTarget(app)
                    NSLog("Hotshot: seeded target from running apps = \(lastTerminalName ?? "unknown")")
                    break
                }
            }
        }

        NSLog("Hotshot: launched, screenshotDir=\(screenshotDir)")

        if autoWatch {
            startWatchingScreenshots()
        }
        if clipboardWatch {
            startWatchingClipboard()
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

        let notifyItem = NSMenuItem(
            title: "Show notifications",
            action: #selector(toggleNotifications), keyEquivalent: "")
        notifyItem.state = notifications ? .on : .off
        menu.addItem(notifyItem)

        let watchItem = NSMenuItem(
            title: "Auto-inject new screenshots (⌘⇧3/4)",
            action: #selector(toggleAutoWatch), keyEquivalent: "")
        watchItem.state = autoWatch ? .on : .off
        menu.addItem(watchItem)

        let clipItem = NSMenuItem(
            title: "Auto-inject from clipboard (⌃⌘⇧3/4)",
            action: #selector(toggleClipboardWatch), keyEquivalent: "")
        clipItem.state = clipboardWatch ? .on : .off
        menu.addItem(clipItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: "Inject last screenshot", action: #selector(injectLastScreenshot),
            keyEquivalent: "")
        menu.addItem(
            withTitle: "Inject clipboard image (Ctrl-V)", action: #selector(injectClipboardNow),
            keyEquivalent: "")

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: "Change screenshot folder\u{2026}", action: #selector(chooseScreenshotDir),
            keyEquivalent: "")

        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: "Quit Hotshot", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")

        menu.delegate = self
        statusItem.menu = menu
        updateTargetLabel()
    }

    func menuWillOpen(_ menu: NSMenu) {
        if lastTerminalBundleID == nil {
            if let front = workspace.frontmostApplication,
               let bid = front.bundleIdentifier,
               TERMINAL_BUNDLE_IDS.contains(bid) {
                setTarget(front)
                NSLog("Hotshot: menuWillOpen seeded target = \(lastTerminalName ?? "unknown")")
            } else {
                for app in workspace.runningApplications where !app.isTerminated {
                    if let bid = app.bundleIdentifier, TERMINAL_BUNDLE_IDS.contains(bid) {
                        setTarget(app)
                        NSLog("Hotshot: menuWillOpen found running terminal = \(lastTerminalName ?? "unknown")")
                        break
                    }
                }
            }
        }
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

    @objc func toggleClipboardWatch() {
        clipboardWatch = !clipboardWatch
        if clipboardWatch {
            startWatchingClipboard()
        } else {
            stopWatchingClipboard()
        }
        rebuildMenu()
    }

    @objc func injectClipboardNow() {
        guard let bid = lastTerminalBundleID else {
            showNotification(title: "Hotshot", body: "No terminal session tracked yet. Focus a terminal first.")
            return
        }

        guard clipboardHasImage() else {
            showNotification(title: "Hotshot", body: "No image on clipboard")
            return
        }

        NSLog("Hotshot: manually injecting clipboard image via Ctrl-V")
        sendCtrlV(terminalBundleID: bid)
        showNotification(title: "Hotshot", body: "Clipboard image injected via Ctrl-V")
    }

    // MARK: - Clipboard Watcher

    func clipboardHasImage() -> Bool {
        let pb = NSPasteboard.general
        return pb.canReadItem(withDataConformingToTypes: [
            "public.png", "public.tiff", "public.jpeg",
        ])
    }

    func startWatchingClipboard() {
        stopWatchingClipboard()
        lastClipboardChangeCount = NSPasteboard.general.changeCount
        clipboardTimer = Timer.scheduledTimer(
            timeInterval: CLIPBOARD_POLL_INTERVAL_SECONDS,
            target: self,
            selector: #selector(checkClipboard),
            userInfo: nil,
            repeats: true
        )
        NSLog("Hotshot: started watching clipboard for images")
    }

    func stopWatchingClipboard() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        NSLog("Hotshot: stopped watching clipboard")
    }

    @objc func checkClipboard() {
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount
        guard currentCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = currentCount

        guard clipboardHasImage() else { return }

        NSLog("Hotshot: clipboard image detected (changeCount=\(currentCount))")

        guard let bid = lastTerminalBundleID else {
            NSLog("Hotshot: clipboard image detected but no terminal tracked")
            showNotification(title: "Hotshot", body: "Clipboard image detected but no terminal session tracked")
            return
        }

        sendCtrlV(terminalBundleID: bid)
        if autoFocus {
            focusTerminal(bundleID: bid)
        }
        showNotification(title: "Hotshot", body: "Clipboard image injected via Ctrl-V")
    }

    func sendCtrlV(terminalBundleID bid: String) {
        let script = """
            tell application id "\(bid)"
                activate
            end tell
            delay \(REFOCUS_DELAY_SECONDS)
            tell application "System Events"
                keystroke "v" using {control down}
            end tell
            """
        NSLog("Hotshot: sending Ctrl-V to \(lastTerminalName ?? bid)")
        runAppleScript(script)
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

    func updateTargetLabel() {
        guard let menuItem = statusItem.menu?.item(withTag: 100) else { return }
        guard let pid = lastTerminalPID else { return }
        if let app = workspace.runningApplications.first(where: { $0.processIdentifier == pid }),
           let title = windowTitle(for: app), !title.isEmpty {
            lastTerminalName = title
        }
        menuItem.title = "Target: \(lastTerminalName ?? "unknown")"
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
            setTarget(app)
            updateTargetLabel()
            NSLog("Hotshot: target changed to \(lastTerminalName ?? "unknown")")
        }
    }

    // MARK: - Path Injection

    func injectPath(_ path: String, terminalBundleID bid: String) {
        let bracketed = "[\(path)] "
        switch bid {
        case "com.googlecode.iterm2":
            injectViaITerm2(bracketed)
        default:
            injectViaGenericAppleScript(bracketed, bundleID: bid)
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
