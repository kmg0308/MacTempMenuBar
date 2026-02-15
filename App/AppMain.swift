import AppKit
import Darwin
import Foundation
import Sparkle
import SwiftUI
import UserNotifications

enum RefreshInterval: Int, CaseIterable {
    case oneSecond = 1
    case twoSeconds = 2
    case fiveSeconds = 5

    var title: String { "\(rawValue)초" }

    static func sanitized(_ value: Int) -> RefreshInterval {
        // Default to a low-frequency refresh to minimize CPU/battery impact on first launch.
        return Self(rawValue: value) ?? .fiveSeconds
    }
}

private struct TemperatureSample {
    let date: Date
    let tempC: Double
}

// Prevent multiple processes from creating duplicate menubar items.
// This can happen if the app is launched from multiple login mechanisms (LaunchAgent + "reopen at login", etc).
private final class SingleInstanceLock {
    private let fd: Int32

    private init(fd: Int32) {
        self.fd = fd
    }

    static func acquire() -> SingleInstanceLock? {
        let fileManager = FileManager.default

        let bundleID = Bundle.main.bundleIdentifier ?? "MacTempMenuBar"
        let supportRoot =
            (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)

        let dirURL = supportRoot.appendingPathComponent(bundleID, isDirectory: true)
        try? fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let lockURL = dirURL.appendingPathComponent("instance.lock", isDirectory: false)
        let fd: Int32 = lockURL.path.withCString { path in
            open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        if fd < 0 {
            return nil
        }

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return nil
        }

        return SingleInstanceLock(fd: fd)
    }

    deinit {
        close(fd)
    }
}

private final class LoginItemManager {
    static let shared = LoginItemManager()

    private let label = "com.kangmingyu.mactempmenubar.login"
    private let fileManager = FileManager.default

    private var plistURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist", isDirectory: false)
    }

    func isEnabled() -> Bool {
        return fileManager.fileExists(atPath: plistURL.path)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            install()
        } else {
            uninstall()
        }
    }

    private func install() {
        do {
            let parent = plistURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

            let executablePath = Bundle.main.executablePath
                ?? "/Applications/MacTempMenuBar.app/Contents/MacOS/MacTempMenuBar"

            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executablePath],
                "RunAtLoad": true,
                "ProcessType": "Interactive"
            ]

            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)

            let domain = "gui/\(getuid())"
            _ = runLaunchctl(["bootout", domain, label], ignoreFailure: true)
            _ = runLaunchctl(["bootout", domain, plistURL.path], ignoreFailure: true)
            _ = runLaunchctl(["bootstrap", domain, plistURL.path], ignoreFailure: true)
            _ = runLaunchctl(["enable", "\(domain)/\(label)"], ignoreFailure: true)
        } catch {
            // Keep failure silent; UI will reflect actual state via isEnabled().
        }
    }

    private func uninstall() {
        let domain = "gui/\(getuid())"
        _ = runLaunchctl(["bootout", domain, label], ignoreFailure: true)
        _ = runLaunchctl(["bootout", domain, plistURL.path], ignoreFailure: true)
        try? fileManager.removeItem(at: plistURL)
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String], ignoreFailure: Bool) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 || ignoreFailure
        } catch {
            return ignoreFailure
        }
    }
}

private final class TemperatureCSVLogger {
    static let shared = TemperatureCSVLogger()

    private let fileManager = FileManager.default
    private let timestampFormatter: ISO8601DateFormatter
    private let dayFormatter: DateFormatter

    let logDirectoryURL: URL

    private init() {
        self.logDirectoryURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("MacTempLogs", isDirectory: true)

        let ts = ISO8601DateFormatter()
        ts.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestampFormatter = ts

        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = day
    }

    private func logFileURL(for date: Date) -> URL {
        let fileName = "temperature_\(dayFormatter.string(from: date)).csv"
        return logDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    func ensureLogFile(for date: Date) throws {
        try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)

        let fileURL = logFileURL(for: date)
        if !fileManager.fileExists(atPath: fileURL.path) {
            let header = "timestamp,temperature_c\n"
            try header.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    func append(temperatureC: Double, at date: Date) {
        do {
            try ensureLogFile(for: date)
            let fileURL = logFileURL(for: date)
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            let line = "\(timestampFormatter.string(from: date)),\(String(format: "%.2f", temperatureC))\n"
            if let data = line.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
            try handle.close()
        } catch {
            // Logging failures should not affect the app loop.
        }
    }
}

private final class TemperatureAlertManager {
    static let shared = TemperatureAlertManager()

    private let center = UNUserNotificationCenter.current()
    private let stateQueue = DispatchQueue(label: "com.kangmingyu.mactempmenubar.alerts")
    private var authorizationRequested = false

    func requestAuthorizationIfNeeded() {
        stateQueue.sync {
            if authorizationRequested { return }
            authorizationRequested = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func postRapidRiseAlert(delta: Double, from: Double, to: Double) {
        requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = "MacTemp: 급상승 감지"
        content.body = String(format: "10초 내 %.1f°C 상승 (%.1f°C → %.1f°C)", delta, from, to)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request) { _ in }
    }
}

final class TemperatureMonitor: ObservableObject {
    private enum DefaultsKey {
        static let refreshInterval = "refreshIntervalSeconds"
        static let csvLoggingEnabled = "csvLoggingEnabled"
        static let rapidRiseAlertsEnabled = "rapidRiseAlertsEnabled"
    }

    private static let historyWindowSec: TimeInterval = 600
    private static let rapidRiseWindowSec: TimeInterval = 10
    private static let rapidRiseDeltaC: Double = 8.0
    private static let rapidRiseCooldownSec: TimeInterval = 120
    private static let menuDetailsMinUpdateIntervalSec: TimeInterval = 5

    @Published private(set) var statusText: String = "--"
    @Published private(set) var temperatureText: String = "N/A"
    @Published private(set) var refreshInterval: RefreshInterval = .fiveSeconds
    @Published private(set) var launchAtLoginEnabled: Bool = false
    @Published private(set) var csvLoggingEnabled: Bool = false
    @Published private(set) var rapidRiseAlertsEnabled: Bool = true
    @Published private(set) var sparklineText: String = "수집 중"
    @Published private(set) var sparklineRangeText: String = "--"

    private let workQueue = DispatchQueue(label: "com.kangmingyu.mactempmenubar.smc", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var menuTrackingCountWorker = 0
    private var menuObservers: [NSObjectProtocol] = []
    private var lastMenuDetailsPublishAtWorker: Date = .distantPast
    private var lastTempCMain: Double?

    private var refreshIntervalWorker: RefreshInterval = .fiveSeconds
    private var csvLoggingEnabledWorker = false
    private var rapidRiseAlertsEnabledWorker = true
    private var historyWorker: [TemperatureSample] = []
    private var lastRapidAlertAt: Date = .distantPast

    private let defaults = UserDefaults.standard
    private let loginItemManager = LoginItemManager.shared
    private let csvLogger = TemperatureCSVLogger.shared
    private let alertManager = TemperatureAlertManager.shared

    init() {
        let interval = RefreshInterval.sanitized(defaults.integer(forKey: DefaultsKey.refreshInterval))
        let logging = defaults.object(forKey: DefaultsKey.csvLoggingEnabled) as? Bool ?? false
        let alerts = defaults.object(forKey: DefaultsKey.rapidRiseAlertsEnabled) as? Bool ?? true

        refreshInterval = interval
        refreshIntervalWorker = interval

        csvLoggingEnabled = logging
        csvLoggingEnabledWorker = logging

        rapidRiseAlertsEnabled = alerts
        rapidRiseAlertsEnabledWorker = alerts

        launchAtLoginEnabled = loginItemManager.isEnabled()

        defaults.set(interval.rawValue, forKey: DefaultsKey.refreshInterval)
        defaults.set(logging, forKey: DefaultsKey.csvLoggingEnabled)
        defaults.set(alerts, forKey: DefaultsKey.rapidRiseAlertsEnabled)

        if alerts {
            alertManager.requestAuthorizationIfNeeded()
        }

        setupMenuTrackingObservers()
        start()
    }

    deinit {
        for observer in menuObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        stop()
        smc_temp_close()
    }

    private func setupMenuTrackingObservers() {
        let center = NotificationCenter.default
        let begin = center.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, Self.isOurMenuOrSubmenu(note.object as? NSMenu) else { return }
            self.workQueue.async {
                let wasClosed = (self.menuTrackingCountWorker == 0)
                self.menuTrackingCountWorker += 1
                if wasClosed {
                    // Make the dropdown text fresh once, then freeze while any menu (including submenus) is open
                    // to prevent SwiftUI re-render from closing the menu during tracking.
                    self.readAndPublish(forceMenuDetails: true)
                }
            }
        }

        let end = center.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, Self.isOurMenuOrSubmenu(note.object as? NSMenu) else { return }
            self.workQueue.async {
                if self.menuTrackingCountWorker > 0 {
                    self.menuTrackingCountWorker -= 1
                }
                if self.menuTrackingCountWorker == 0 {
                    // Reflect latest menu text once after close.
                    self.readAndPublish(forceMenuDetails: true)
                }
            }
        }

        menuObservers = [begin, end]
    }

    private static func isOurMenu(_ menu: NSMenu?) -> Bool {
        guard let menu else { return false }
        let titles = Set(menu.items.map(\.title))
        return titles.contains("지금 업데이트") && titles.contains("종료")
    }

    private static func isOurMenuOrSubmenu(_ menu: NSMenu?) -> Bool {
        var cur = menu
        while let m = cur {
            if isOurMenu(m) { return true }
            cur = m.supermenu
        }
        return false
    }

    func start() {
        if timer != nil { return }

        workQueue.async {
            _ = smc_temp_init()
        }

        scheduleTimer()
    }

    private func scheduleTimer() {
        let t = DispatchSource.makeTimerSource(queue: workQueue)
        t.schedule(
            deadline: .now() + .milliseconds(150),
            repeating: .seconds(refreshIntervalWorker.rawValue),
            leeway: .milliseconds(250)
        )
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.readAndPublish(forceMenuDetails: false)
        }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func forceUpdate() {
        workQueue.async { [weak self] in
            self?.readAndPublish(forceMenuDetails: true)
        }
    }

    func setRefreshInterval(_ interval: RefreshInterval) {
        defaults.set(interval.rawValue, forKey: DefaultsKey.refreshInterval)
        refreshInterval = interval

        workQueue.async { [weak self] in
            guard let self else { return }
            self.refreshIntervalWorker = interval
            self.timer?.cancel()
            self.timer = nil
            self.scheduleTimer()
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            self.loginItemManager.setEnabled(enabled)
            let actual = self.loginItemManager.isEnabled()
            DispatchQueue.main.async {
                self.launchAtLoginEnabled = actual
            }
        }
    }

    func setCSVLoggingEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: DefaultsKey.csvLoggingEnabled)
        csvLoggingEnabled = enabled

        workQueue.async { [weak self] in
            guard let self else { return }
            self.csvLoggingEnabledWorker = enabled
            if enabled {
                try? self.csvLogger.ensureLogFile(for: Date())
            }
        }
    }

    func setRapidRiseAlertsEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: DefaultsKey.rapidRiseAlertsEnabled)
        rapidRiseAlertsEnabled = enabled

        workQueue.async { [weak self] in
            guard let self else { return }
            self.rapidRiseAlertsEnabledWorker = enabled
            if enabled {
                self.alertManager.requestAuthorizationIfNeeded()
            }
        }
    }

    func openLogFolder() {
        workQueue.async { [weak self] in
            guard let self else { return }
            try? self.csvLogger.ensureLogFile(for: Date())
            let directory = self.csvLogger.logDirectoryURL
            DispatchQueue.main.async {
                NSWorkspace.shared.open(directory)
            }
        }
    }

    private func readAndPublish() {
        readAndPublish(forceMenuDetails: false)
    }

    private func readAndPublish(forceMenuDetails: Bool) {
        autoreleasepool {
            var tempC: Double = .nan
            let rc: Int32 = smc_temp_read_max(&tempC, nil)
            let sampledAt = Date()

            guard rc == 0, tempC.isFinite else {
                DispatchQueue.main.async {
                    self.lastTempCMain = nil
                    if self.statusText != "--" { self.statusText = "--" }
                    if self.temperatureText != "N/A" { self.temperatureText = "N/A" }
                    if self.sparklineText != "N/A" { self.sparklineText = "N/A" }
                    if self.sparklineRangeText != "--" { self.sparklineRangeText = "--" }
                }
                return
            }

            historyWorker.append(.init(date: sampledAt, tempC: tempC))
            pruneHistory(now: sampledAt)

            if csvLoggingEnabledWorker {
                csvLogger.append(temperatureC: tempC, at: sampledAt)
            }

            if rapidRiseAlertsEnabledWorker {
                maybeSendRapidRiseAlert(currentTemp: tempC, now: sampledAt)
            }

            let rounded = Int(tempC.rounded())

            let isMenuTracking = (menuTrackingCountWorker > 0)
            let shouldPublishMenuDetails =
                forceMenuDetails ||
                (!isMenuTracking && sampledAt.timeIntervalSince(lastMenuDetailsPublishAtWorker) >= Self.menuDetailsMinUpdateIntervalSec)

            if shouldPublishMenuDetails {
                lastMenuDetailsPublishAtWorker = sampledAt

                let precise = String(format: "%.1f°C", tempC)
                let (sparkline, rangeText) = Self.makeSparkline(from: historyWorker)

                DispatchQueue.main.async {
                    self.lastTempCMain = tempC

                    let statusText = "\(rounded)"
                    if self.statusText != statusText { self.statusText = statusText }
                    if self.temperatureText != precise { self.temperatureText = precise }
                    if self.sparklineText != sparkline { self.sparklineText = sparkline }
                    if self.sparklineRangeText != rangeText { self.sparklineRangeText = rangeText }
                }
                return
            }

            // While a menu/submenu is tracking, avoid publishing *any* SwiftUI state changes.
            // Published updates can cause SwiftUI to rebuild the MenuBarExtra view tree and close the open menu.
            if isMenuTracking {
                return
            }

            // Keep menubar number/color fresh, but freeze dropdown text while the menu is open (or between periodic updates)
            // to avoid hover target jitter from frequent layout changes.
            DispatchQueue.main.async {
                self.lastTempCMain = tempC

                let statusText = "\(rounded)"
                if self.statusText != statusText { self.statusText = statusText }
            }
        }
    }

    private func pruneHistory(now: Date) {
        historyWorker.removeAll { now.timeIntervalSince($0.date) > Self.historyWindowSec }
    }

    private func maybeSendRapidRiseAlert(currentTemp: Double, now: Date) {
        var minRecent: Double? = nil
        for sample in historyWorker.reversed() {
            let dt = now.timeIntervalSince(sample.date)
            if dt <= 0 { continue } // skip current sample (dt == 0)
            if dt > Self.rapidRiseWindowSec { break }

            if let current = minRecent {
                if sample.tempC < current { minRecent = sample.tempC }
            } else {
                minRecent = sample.tempC
            }
        }

        guard let minRecent else { return }

        let delta = currentTemp - minRecent
        guard delta >= Self.rapidRiseDeltaC else {
            return
        }

        guard now.timeIntervalSince(lastRapidAlertAt) >= Self.rapidRiseCooldownSec else {
            return
        }

        lastRapidAlertAt = now
        alertManager.postRapidRiseAlert(delta: delta, from: minRecent, to: currentTemp)
    }

    private static func makeSparkline(from samples: [TemperatureSample]) -> (String, String) {
        guard !samples.isEmpty else {
            return ("수집 중", "--")
        }

        let values = samples.map(\.tempC)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0

        let bins = 24
        let downsampled = downsample(values, to: bins)

        let blocks: [Character] = Array("▁▂▃▄▅▆▇█")
        let sparkline: String

        if abs(maxValue - minValue) < 0.001 {
            sparkline = String(repeating: "▅", count: max(1, downsampled.count))
        } else {
            sparkline = String(downsampled.map { value in
                let normalized = (value - minValue) / (maxValue - minValue)
                let idx = Int((normalized * Double(blocks.count - 1)).rounded())
                let clamped = max(0, min(blocks.count - 1, idx))
                return blocks[clamped]
            })
        }

        let rangeText = String(format: "%.1f~%.1f°C", minValue, maxValue)
        return (sparkline, rangeText)
    }

    private static func downsample(_ values: [Double], to bins: Int) -> [Double] {
        guard bins > 0 else { return values }
        guard values.count > bins else { return values }

        var result: [Double] = []
        result.reserveCapacity(bins)

        let step = Double(values.count) / Double(bins)
        for i in 0 ..< bins {
            let start = Int(floor(Double(i) * step))
            var end = Int(floor(Double(i + 1) * step))
            if end <= start {
                end = start + 1
            }
            end = min(end, values.count)

            let slice = values[start ..< end]
            let avg = slice.reduce(0, +) / Double(slice.count)
            result.append(avg)
        }

        return result
    }

}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var instanceLock: SingleInstanceLock?

    func applicationWillFinishLaunching(_ notification: Notification) {
        instanceLock = SingleInstanceLock.acquire()
        if instanceLock == nil {
            // Another instance already has the lock.
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        smc_temp_close()
    }
}

@main
struct MacTempMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = TemperatureMonitor()
    private let updaterController: SPUStandardUpdaterController

    init() {
        // Sparkle: checks update feed periodically and prompts the user when an update is available.
        // This is the typical "notify -> update" flow used by many non-App-Store macOS apps.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        MenuBarExtra {
            Text("현재: \(monitor.temperatureText)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))

            Text("최근 10분: \(monitor.sparklineText)")
                .font(.system(size: 12, weight: .regular, design: .monospaced))

            Text("범위: \(monitor.sparklineRangeText)")
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(.secondary)

            Divider()

            Toggle("급상승 알림 (10초 내 +8°C)", isOn: Binding(
                get: { monitor.rapidRiseAlertsEnabled },
                set: { monitor.setRapidRiseAlertsEnabled($0) }
            ))

            Toggle("로그인 시 자동 실행", isOn: Binding(
                get: { monitor.launchAtLoginEnabled },
                set: { monitor.setLaunchAtLoginEnabled($0) }
            ))

            Menu("갱신 주기: \(monitor.refreshInterval.title)") {
                ForEach(RefreshInterval.allCases, id: \.self) { interval in
                    Button("\(monitor.refreshInterval == interval ? "✓ " : "")\(interval.title)") {
                        monitor.setRefreshInterval(interval)
                    }
                }
            }

            Toggle("CSV 로그 저장 (일별 파일)", isOn: Binding(
                get: { monitor.csvLoggingEnabled },
                set: { monitor.setCSVLoggingEnabled($0) }
            ))

            Button("로그 폴더 열기") {
                monitor.openLogFolder()
            }

            Divider()

            Button("지금 업데이트") {
                monitor.forceUpdate()
            }
            .keyboardShortcut("r")

            Button("앱 업데이트 확인…") {
                updaterController.checkForUpdates(nil)
            }

            Button("종료") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Text(monitor.statusText)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
                .foregroundStyle(.primary)
                .accessibilityLabel("Mac 온도 \(monitor.statusText)도")
        }
        .menuBarExtraStyle(.menu)
    }
}
