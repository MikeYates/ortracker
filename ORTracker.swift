import AppKit
import Foundation

struct ORUsageData: Decodable {
    let ok: Bool
    let error: String?
    let days: Int?
    let total_credits: Double?
    let total_usage: Double?
    let remaining: Double?
    let remaining_pct: Double?
    let total_cost: Double?
    let total_calls: Int?
    let total_tokens: Int?
    let models: [ORModel]?
}

struct ORModel: Decodable {
    let model: String
    let cost: Double
    let tokens: Int
    let api_calls: Int
    let sessions: Int
}

let MODES = ["quotaBar", "balance", "percentage"]
let APP_VERSION = "1.1.0"
let GITHUB_REPO = "mikeyates/ortracker"

struct GitHubRelease: Decodable {
    let tag_name: String
    let html_url: String
}

let OR_LOGO_B64 = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAABmJLR0QA/wD/AP+gvaeTAAABuklEQVRYhe3Wv0tVYRzH8ZeWFEWFYYXRFEJDQYt3KLggaFNDf0R/QGsQtERD1BxSNBQNkdjk0BAhuigqTQZCtDREkkZDcSO1huceiKdz7vlxj0RwP/As5/v9Pp/38/M89NTTP1ZfTnwEV9DASZzA3pIev/AJa3iOl0WKRvGqXVx3m8VwlnE/bmNnl8yT9h7HYvM9mNpl4z/bdAxwr0PyJuYwgzfYqgniXGJ+KSNhVdiE8cY7jlv43iXAdcK6r6QEX+BAPE2RGljvAuAhjKUElrA/xzxRU/UlmewXpjjWNbQKAszjacHcWGuwHFG9rdBRU/nRb+E0fIwCjyoADGC7JMCDpPhHFLhbAQC+lDBfxkHCCfgcdfTXDVVA+3CkQN4OHgsb/1vycTGie1cBYFz2aLeFn9BNnE0rvpNSNFESIO8KfyJc9am6kFKwikMFzS8r9vPqCDGfUvAagznmE/hawDwX4qL0Y/QBV3E4yj+DSfwsYZ4LcaNDUUtYloU2VJVrNxeirz2qbjsvBRFTzAhrOp41TTXqPI5mBUfwTH0Pj6y2kfcqHhKOWQOnhFfxQMmRZqmF+zX11dN/rN+h84r/xbqyIgAAAABJRU5ErkJggg=="

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var currentDays = 7
    private var latest: ORUsageData?
    private var displayMode = "balance" // "quotaBar" | "balance" | "percentage"
    private var quotaRef: Double = 0 // balance at last Reset Quota; used to compute remaining %
    private let scriptPath = NSString(string: "~/.ortracker/or_usage.py").expandingTildeInPath
    private let pythonPath = "/usr/bin/python3"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        displayMode = UserDefaults.standard.string(forKey: "orViewMode") ?? "balance"
        if !MODES.contains(displayMode) { displayMode = "balance" }
        quotaRef = UserDefaults.standard.double(forKey: "orQuotaRef")
        if let button = statusItem.button {
            button.title = "OR …"
            button.toolTip = "OpenRouter"
            button.imagePosition = .imageLeft
        }
        refresh(nil)
        timer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(refresh(_:)), userInfo: nil, repeats: true)
        checkForUpdates(nil)
        Timer.scheduledTimer(timeInterval: 21600, target: self, selector: #selector(checkForUpdates(_:)), userInfo: nil, repeats: true)
    }

    @objc private func refresh(_ sender: Any?) {
        DispatchQueue.global(qos: .utility).async {
            let data = self.loadUsage(days: self.currentDays)
            DispatchQueue.main.async {
                self.latest = data
                if data.ok, self.quotaRef <= 0 {
                    self.quotaRef = data.remaining ?? 0
                    UserDefaults.standard.set(self.quotaRef, forKey: "orQuotaRef")
                }
                self.updateTitle()
                self.rebuildMenu()
            }
        }
    }

    private func loadUsage(days: Int) -> ORUsageData {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: FileManager.default.fileExists(atPath: pythonPath) ? pythonPath : "/usr/bin/python3")
        process.arguments = [scriptPath, String(days)]
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let decoded = try? JSONDecoder().decode(ORUsageData.self, from: data) {
                return decoded
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            return ORUsageData(ok: false, error: "Could not parse: \(text.prefix(120))", days: days, total_credits: nil, total_usage: nil, remaining: nil, remaining_pct: nil, total_cost: nil, total_calls: nil, total_tokens: nil, models: nil)
        } catch {
            return ORUsageData(ok: false, error: error.localizedDescription, days: days, total_credits: nil, total_usage: nil, remaining: nil, remaining_pct: nil, total_cost: nil, total_calls: nil, total_tokens: nil, models: nil)
        }
    }

    private func currentRemaining() -> Double { latest?.remaining ?? 0 }

    private func currentPct() -> Double {
        guard quotaRef > 0 else { return 1.0 }
        return min(max(currentRemaining() / quotaRef, 0), 1)
    }

    // MARK: - Title

    private func orLogoImage(size: NSSize = NSSize(width: 20, height: 16)) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        defer { img.unlockFocus() }
        guard let data = Data(base64Encoded: OR_LOGO_B64),
              let logoImg = NSImage(data: data) else {
            img.unlockFocus()
            return NSImage(size: size)
        }
        let logoSize: CGFloat = 16
        logoImg.size = NSSize(width: logoSize, height: logoSize)
        logoImg.draw(at: NSPoint(x: 0, y: (size.height - logoSize) / 2), from: .zero, operation: .sourceOver, fraction: 1)
        img.isTemplate = true
        return img
    }

    private func compositeQuotaBar(fraction: Double) -> NSImage {
        let logoSize: CGFloat = 14
        let barWidth: CGFloat = 46
        let barHeight: CGFloat = 12
        let gap: CGFloat = 2
        let totalWidth = logoSize + gap + barWidth
        let totalHeight = max(logoSize, barHeight)

        let img = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        img.lockFocus()
        defer { img.unlockFocus() }

        let logo = orLogoImage(size: NSSize(width: logoSize, height: logoSize))
        logo.draw(at: NSPoint(x: 0, y: (totalHeight - logoSize) / 2), from: .zero, operation: .sourceOver, fraction: 1)

        let barY = (totalHeight - barHeight) / 2
        let bar = quotaBarImage(fraction: fraction, width: barWidth, height: barHeight)
        bar.draw(at: NSPoint(x: logoSize + gap, y: barY), from: .zero, operation: .sourceOver, fraction: 1)

        return img
    }

    private func updateTitle() {
        guard let d = latest, d.ok else {
            statusItem.button?.title = "OR ⚠"
            statusItem.button?.attributedTitle = NSAttributedString()
            statusItem.button?.image = nil
            return
        }
        let pct = currentPct()
        let bal = currentRemaining()

        // OR logo is always the button image (template, follows system color)
        statusItem.button?.image = orLogoImage()

        switch displayMode {
        case "quotaBar":
            // Bar goes in the attributed title so the logo stays template-colored
            statusItem.button?.title = ""
            let attachment = NSTextAttachment()
            attachment.image = quotaBarImage(fraction: pct)
            attachment.bounds = CGRect(x: 0, y: -2, width: 46, height: 12)
            let attr = NSAttributedString(attachment: attachment)
            statusItem.button?.attributedTitle = attr
        case "balance":
            statusItem.button?.attributedTitle = NSAttributedString()
            statusItem.button?.title = formatMoney(bal)
        case "percentage":
            statusItem.button?.attributedTitle = NSAttributedString()
            statusItem.button?.title = "\(Int((pct * 100).rounded()))%"
        default:
            statusItem.button?.attributedTitle = NSAttributedString()
            statusItem.button?.title = formatMoney(bal)
        }
        statusItem.button?.toolTip = "OpenRouter: $\(String(format: "%.2f", bal)) remaining"
    }

    private func quotaBarImage(fraction: Double, width: CGFloat = 46, height: CGFloat = 12) -> NSImage {
        let pct = min(max(fraction, 0), 1)
        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()
        defer { img.unlockFocus() }
        NSColor.labelColor.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1), xRadius: height / 2, yRadius: height / 2).fill()
        let fillWidth = max(height, (width - 2) * CGFloat(pct))
        let color: NSColor
        if pct >= 0.5 { color = NSColor.systemGreen }
        else if pct >= 0.25 { color = NSColor.systemOrange }
        else { color = NSColor.systemRed }
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: fillWidth, height: height - 1), xRadius: height / 2, yRadius: height / 2).fill()
        return img
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        let d = latest
        let bal = currentRemaining()

        if let d, d.ok {
            menu.addItem(disabled("OpenRouter usage, last \(d.days ?? 7) days"))
            menu.addItem(disabled("Cost: \(formatMoney(d.total_cost ?? 0))"))
            menu.addItem(disabled("API calls: \(formatNumber(d.total_calls ?? 0))"))
            menu.addItem(disabled("Balance: \(formatMoney(bal))"))
            menu.addItem(disabled("Remaining: \\(Int((currentPct() * 100).rounded()))%"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(disabled("Recently used"))
            for m in (d.models ?? []).prefix(6) {
                let item = NSMenuItem(title: "\(m.model): \(formatMoney(m.cost)) · \(formatNumber(m.tokens)) tok", action: nil, keyEquivalent: "")
                item.toolTip = "\(formatNumber(m.api_calls)) calls, \(m.sessions) sessions"
                menu.addItem(item)
            }
        } else {
            menu.addItem(disabled("OpenRouter unavailable"))
            if let err = d?.error { menu.addItem(disabled(err)) }
        }

        menu.addItem(NSMenuItem.separator())
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu()
        for mode in MODES {
            let label: String
            switch mode {
            case "quotaBar": label = "Quota Bar"
            case "balance": label = "Balance"
            case "percentage": label = "Percentage"
            default: label = mode
            }
            let item = NSMenuItem(title: label, action: #selector(setDisplayMode(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = mode
            item.state = mode == displayMode ? .on : .off
            viewMenu.addItem(item)
        }
        viewItem.submenu = viewMenu
        menu.addItem(viewItem)

        addDaysItem(menu, days: 7)
        addDaysItem(menu, days: 30)
        addDaysItem(menu, days: 90)
        menu.addItem(NSMenuItem.separator())
        let resetItem = NSMenuItem(title: "Reset Quota", action: #selector(resetQuota(_:)), keyEquivalent: "r")
        resetItem.target = self
        resetItem.toolTip = "Sets the quota to 100% at the current balance"
        menu.addItem(resetItem)
        let refreshItem = NSMenuItem(title: "Refresh now", action: #selector(refresh(_:)), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        // Update check
        if let url = updateAvailable {
            let updateItem = NSMenuItem(title: "⚠ Update available — Download", action: #selector(openUpdateURL(_:)), keyEquivalent: "")
            updateItem.target = self
            updateItem.representedObject = url
            menu.addItem(updateItem)
        }
        let checkItem = NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        checkItem.target = self
        menu.addItem(checkItem)

        let quitItem = NSMenuItem(title: "Quit OpenRouter Usage", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func addDaysItem(_ menu: NSMenu, days: Int) {
        let item = NSMenuItem(title: "Show last \(days) days", action: #selector(setDays(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = days
        item.state = days == currentDays ? .on : .off
        menu.addItem(item)
    }

    @objc private func setDisplayMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String, mode != displayMode else { return }
        displayMode = mode
        UserDefaults.standard.set(mode, forKey: "orViewMode")
        updateTitle()
        rebuildMenu()
    }

    @objc private func setDays(_ sender: NSMenuItem) {
        guard let days = sender.representedObject as? Int else { return }
        currentDays = days
        refresh(nil)
    }

    @objc private func resetQuota(_ sender: Any?) {
        quotaRef = currentRemaining()
        UserDefaults.standard.set(quotaRef, forKey: "orQuotaRef")
        updateTitle()
        rebuildMenu()
        // Notify
        hostNotify(title: "Quota reset", message: "Quota set to 100% at \(formatMoney(quotaRef))")
    }

    private func hostNotify(title: String, message: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        NSUserNotificationCenter.default.deliver(notification)
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    // MARK: - Update Check

    private var updateAvailable: String?

    @objc private func openUpdateURL(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? String {
            NSWorkspace.shared.open(URL(string: url)!)
        }
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        DispatchQueue.global(qos: .background).async {
            guard let url = URL(string: "https://api.github.com/repos/\(GITHUB_REPO)/releases/latest") else { return }
            var req = URLRequest(url: url)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 10
            guard let data = try? Data(contentsOf: url),
                  let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else { return }
            let latest = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            if latest.compare(APP_VERSION, options: .numeric) == .orderedDescending {
                DispatchQueue.main.async {
                    self.updateAvailable = release.html_url
                    self.rebuildMenu()
                    self.hostNotify(title: "ORTracker update available",
                                   message: "Version \(latest) is ready — click Check for Updates in the menu")
                }
            }
        }
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