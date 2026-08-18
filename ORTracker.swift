import AppKit
import Foundation

let APP_VERSION = "1.0.0"
let GITHUB_REPO = "mikeyates/ortracker"
let INSTALL_URL = "https://ortracker.yates.id/install.sh"
let CONFIG_PATH = NSString(string: "~/.ortracker/config").expandingTildeInPath
let TRACKER_PATH = NSString(string: "~/.ortracker/tracker.json").expandingTildeInPath

struct Config: Codable {
    var api_key: String
}

struct Tracker: Codable {
    var baseline: Double // balance at last top-up (100% reference)
    var lastBalance: Double
    var autoUpdate: Bool
    var lastUpdateCheck: Double // epoch
}

struct GitHubRelease: Codable {
    let tag_name: String
    let assets: [GitHubAsset]?
    let body: String?
}

struct GitHubAsset: Codable {
    let name: String
    let browser_download_url: String
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var updateTimer: Timer?
    private var balance: Double?
    private var baseline: Double?
    private var autoUpdate = true
    private var currentVersion = APP_VERSION
    private var pendingUpdate: String?
    private let topUpThreshold = 0.50

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loadTracker()
        ensureConfig()
        if let button = statusItem.button {
            button.title = "OR …"
            button.toolTip = "OpenRouter balance tracker"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)
        }
        refresh(balance: nil)
        checkForUpdates(silent: true)
        // Balance refresh every 60s
        timer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(refreshTimer), userInfo: nil, repeats: true)
        // Update check every 6 hours
        updateTimer = Timer.scheduledTimer(timeInterval: 21600, target: self, selector: #selector(checkForUpdatesSilent), userInfo: nil, repeats: true)
    }

    // MARK: - Config & Tracker

    private func ensureConfig() {
        let path = CONFIG_PATH as NSString
        let dir = path.deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: CONFIG_PATH) {
            // First run — prompt for API key via alert
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.promptForApiKey()
            }
        }
    }

    private func promptForApiKey() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "OpenRouter API Key"
        alert.informativeText = "ORTracker needs your OpenRouter API key to track your balance.\n\nGet it from: https://openrouter.ai/keys"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.placeholderString = "sk-or-v1-..."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Quit")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                saveConfig(Config(api_key: key))
            }
        } else {
            NSApp.terminate(nil)
        }
    }

    private func saveConfig(_ config: Config) {
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: URL(fileURLWithPath: CONFIG_PATH), options: [.atomic, .completeFileProtection])
            // Restrict permissions
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: CONFIG_PATH)
        }
    }

    private func loadConfig() -> Config? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: CONFIG_PATH)),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return nil
        }
        return config
    }

    private func loadTracker() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: TRACKER_PATH)),
              let store = try? JSONDecoder().decode(Tracker.self, from: data) else {
            autoUpdate = true
            return
        }
        baseline = store.baseline
        autoUpdate = store.autoUpdate
    }

    private func saveTracker(baseline bl: Double, lastBalance: Double) {
        let store = Tracker(baseline: bl, lastBalance: lastBalance, autoUpdate: autoUpdate, lastUpdateCheck: Date().timeIntervalSince1970)
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: URL(fileURLWithPath: TRACKER_PATH), options: .atomic)
        }
    }

    // MARK: - Balance

    @objc private func refreshTimer() {
        refresh(balance: nil)
    }

    private func refresh(balance initial: Double?) {
        DispatchQueue.global(qos: .utility).async {
            let bal = initial ?? self.fetchBalance()
            DispatchQueue.main.async {
                guard let bal = bal else { return }
                let prev = self.lastSavedBalance()
                if bal > prev + self.topUpThreshold {
                    self.baseline = bal
                    self.saveTracker(baseline: bal, lastBalance: bal)
                } else {
                    if self.baseline == nil { self.baseline = bal }
                    self.saveTracker(baseline: self.baseline ?? bal, lastBalance: bal)
                }
                self.balance = bal
                self.updateTitle()
            }
        }
    }

    private func fetchBalance() -> Double? {
        guard let config = loadConfig() else {
            DispatchQueue.main.async { self.promptForApiKey() }
            return nil
        }
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/credits")!)
        request.setValue("Bearer \(config.api_key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        let semaphore = DispatchSemaphore(value: 0)
        var result: Double?
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            defer { semaphore.signal() }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let creds = json["data"] as? [String: Any],
               let total = creds["total_credits"] as? Double,
               let used = creds["total_usage"] as? Double {
                result = total - used
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 15)
        return result
    }

    private func lastSavedBalance() -> Double {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: TRACKER_PATH)),
              let store = try? JSONDecoder().decode(Tracker.self, from: data) else {
            return 0
        }
        return store.lastBalance
    }

    // MARK: - Title & Bar

    private func updateTitle() {
        guard let bal = balance else {
            statusItem.button?.title = "OR —"
            statusItem.button?.image = nil
            statusItem.button?.toolTip = "ORTracker: unavailable"
            return
        }
        statusItem.button?.title = String(format: "$%.2f", bal)
        statusItem.button?.image = balanceBar(balance: bal, baseline: baseline ?? bal)
        statusItem.button?.toolTip = String(format: "ORTracker: $%.2f left", bal)
    }

    private func balanceBar(balance: Double, baseline: Double, width: CGFloat = 46, height: CGFloat = 12) -> NSImage {
        let pct = baseline > 0 ? min(max(balance / baseline, 0), 1) : 0
        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()
        defer { img.unlockFocus() }
        NSColor.labelColor.withAlphaComponent(0.22).setFill()
        let trackRect = NSRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1)
        NSBezierPath(roundedRect: trackRect, xRadius: height / 2, yRadius: height / 2).fill()
        let fillWidth = max(height, (width - 2) * CGFloat(pct))
        let color: NSColor
        if pct >= 0.5 { color = NSColor.systemGreen }
        else if pct >= 0.25 { color = NSColor.systemOrange }
        else { color = NSColor.systemRed }
        color.setFill()
        let fillRect = NSRect(x: 0.5, y: 0.5, width: fillWidth, height: height - 1)
        NSBezierPath(roundedRect: fillRect, xRadius: height / 2, yRadius: height / 2).fill()
        return img
    }

    // MARK: - Auto Update

    @objc private func checkForUpdatesSilent() {
        checkForUpdates(silent: true)
    }

    private func checkForUpdates(silent: Bool) {
        guard let url = URL(string: "https://api.github.com/repos/\(GITHUB_REPO)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        DispatchQueue.global(qos: .background).async {
            let semaphore = DispatchSemaphore(value: 0)
            let task = URLSession.shared.dataTask(with: request) { data, _, error in
                defer { semaphore.signal() }
                guard let data = data,
                      let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else { return }

                let latest = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
                let current = self.currentVersion

                DispatchQueue.main.async {
                    if latest.compare(current, options: .numeric) == .orderedDescending {
                        self.pendingUpdate = release.tag_name
                        // If auto-update is on, update silently
                        if self.autoUpdate {
                            self.performUpdate(release: release)
                        } else if !silent {
                            // Show notification that update is available
                            let resp = self.showUpdateAlert(version: latest, notes: release.body ?? "")
                            if resp {
                                self.performUpdate(release: release)
                            }
                        }
                    } else if !silent {
                        self.showUpToDateAlert()
                    }
                }
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 20)
        }
    }

    private func showUpdateAlert(version: String, notes: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Update available: v\(version)"
        let info = notes.isEmpty ? "" : "\n\nWhat's new:\n\(notes)"
        alert.informativeText = "A new version of ORTracker is ready.\(info)"
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showUpToDateAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "ORTracker is up to date"
        alert.informativeText = "You're running v\(currentVersion), which is the latest version."
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
    }

    private func performUpdate(release: GitHubRelease) {
        // Find the source zip or DMG asset
        guard let asset = release.assets?.first(where: { $0.name.hasSuffix(".swift") || $0.name.hasSuffix(".zip") || $0.name == "ORTracker.swift" }) ?? release.assets?.first else {
            return
        }

        let downloadUrl = asset.browser_download_url
        guard let url = URL(string: downloadUrl) else { return }

        DispatchQueue.global(qos: .background).async {
            guard let data = try? Data(contentsOf: url) else { return }

            let tmpDir = "/tmp/ortracker-update"
            try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

            if asset.name.hasSuffix(".swift") {
                // Compile from source
                let sourcePath = "\(tmpDir)/ORTracker.swift"
                try? data.write(to: URL(fileURLWithPath: sourcePath))
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
                process.arguments = ["-O", sourcePath, "-o", "\(tmpDir)/ORTracker"]
                try? process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: "\(tmpDir)/ORTracker") else { return }

                DispatchQueue.main.async {
                    self.installUpdate(binaryPath: "\(tmpDir)/ORTracker")
                }
            } else if asset.name.hasSuffix(".zip") {
                // Extract and install
                let zipPath = "\(tmpDir)/update.zip"
                try? data.write(to: URL(fileURLWithPath: zipPath))
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-o", zipPath, "-d", tmpDir]
                try? process.run()
                process.waitUntilExit()

                // Find the .app bundle
                let contents = (try? FileManager.default.contentsOfDirectory(atPath: tmpDir)) ?? []
                if let appName = contents.first(where: { $0.hasSuffix(".app") }) {
                    DispatchQueue.main.async {
                        self.installUpdateBundle(appPath: "\(tmpDir)/\(appName)")
                    }
                }
            }
        }
    }

    private func installUpdate(binaryPath: String) {
        // Create .app structure at tmp, then swap
        let tmpAppPath = "/tmp/ortracker-update/ORTracker.app"
        let appPath = "/Applications/ORTracker.app"
        let bundlePath = "\(tmpAppPath)/Contents/MacOS"
        try? FileManager.default.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)

        // Copy binary
        try? FileManager.default.copyItem(atPath: binaryPath, toPath: "\(bundlePath)/ORTracker")

        // Create Info.plist
        let plist: [String: Any] = [
            "CFBundleExecutable": "ORTracker",
            "CFBundleIdentifier": "com.mikeyates.ortracker",
            "CFBundleName": "ORTracker",
            "CFBundleDisplayName": "ORTracker",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": currentVersion,
            "LSMinimumSystemVersion": "13.0",
            "LSUIElement": true,
            "NSHighResolutionCapable": true,
        ]
        let plistData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try? plistData?.write(to: URL(fileURLWithPath: "\(tmpAppPath)/Contents/Info.plist"))

        // Replace running app via delayed script
        let script = """
        #!/bin/bash
        sleep 1
        rm -rf "\(appPath)"
        cp -R "\(tmpAppPath)" "\(appPath)"
        codesign --force --deep --sign - "\(appPath)" 2>/dev/null
        open "\(appPath)"
        """
        let scriptPath = "/tmp/ortracker-update/swap.sh"
        try? script.write(to: URL(fileURLWithPath: scriptPath), atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        DispatchQueue.global(qos: .background).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath]
            try? process.run()
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    private func installUpdateBundle(appPath: String) {
        let targetPath = "/Applications/ORTracker.app"
        let script = """
        #!/bin/bash
        sleep 1
        rm -rf "\(targetPath)"
        cp -R "\(appPath)" "\(targetPath)"
        codesign --force --deep --sign - "\(targetPath)" 2>/dev/null
        open "\(targetPath)"
        """
        let scriptPath = "/tmp/ortracker-update/swap.sh"
        try? script.write(to: URL(fileURLWithPath: scriptPath), atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        DispatchQueue.global(qos: .background).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath]
            try? process.run()
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()

        if let bal = balance {
            menu.addItem(disabled(String(format: "ORTracker  v%@", currentVersion)))
            menu.addItem(disabled(String(format: "OpenRouter: $%.2f left", bal)))
            if let bl = baseline {
                let pct = bl > 0 ? Int((bal / bl * 100).rounded()) : 0
                menu.addItem(disabled(String(format: "  %.0f%% remaining  (baseline $%.2f)", pct, bl)))
            }
        } else {
            menu.addItem(disabled("ORTracker"))
            menu.addItem(disabled("OpenRouter: —"))
        }

        menu.addItem(NSMenuItem.separator())

        // Auto Update toggle
        let autoItem = NSMenuItem(title: "Auto Update", action: #selector(toggleAutoUpdate), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = autoUpdate ? .on : .off
        menu.addItem(autoItem)

        let checkItem = NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdatesManual), keyEquivalent: "u")
        checkItem.target = self
        menu.addItem(checkItem)

        menu.addItem(NSMenuItem.separator())

        let apiItem = NSMenuItem(title: "Set API Key…", action: #selector(setApiKey), keyEquivalent: "")
        apiItem.target = self
        menu.addItem(apiItem)

        menu.addItem(NSMenuItem.separator())
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshTimer), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        let quitItem = NSMenuItem(title: "Quit ORTracker", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func toggleAutoUpdate() {
        autoUpdate.toggle()
        // Persist
        if let bal = balance {
            saveTracker(baseline: baseline ?? bal, lastBalance: bal)
        }
        rebuildMenu()
    }

    @objc private func checkForUpdatesManual() {
        checkForUpdates(silent: false)
    }

    @objc private func setApiKey() {
        promptForApiKey()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func formatCompact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000.0) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000.0) }
        return "\(n)"
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatMoney(_ n: Double) -> String {
        if n <= 0 { return "$0.00" }
        if n < 0.01 { return String(format: "$%.4f", n) }
        return String(format: "$%.2f", n)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()