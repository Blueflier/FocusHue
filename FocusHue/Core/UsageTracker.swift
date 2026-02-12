//
//  UsageTracker.swift
//  FocusHue
//
//  Records app/site usage sessions to daily JSON files for analytics
//

import Foundation
import AppKit

// MARK: - In-Memory Models

struct UsageSession: Identifiable {
    let id = UUID()
    let app: String
    let bundleId: String
    let host: String?
    var startMin: Int
    var endMin: Int?

    func durationSeconds(nowMin: Int? = nil) -> TimeInterval {
        let end = endMin ?? nowMin ?? Self.currentMinute()
        let mins = end >= startMin ? end - startMin : (1440 - startMin) + end
        return TimeInterval(mins * 60)
    }

    static func currentMinute() -> Int {
        let cal = Calendar.current
        let now = Date()
        return cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
    }
}

struct AppMetric: Identifiable {
    let id = UUID()
    let name: String
    let bundleId: String
    let duration: TimeInterval
}

struct SiteMetric: Identifiable {
    let id = UUID()
    let host: String
    let duration: TimeInterval
}

struct DailyMetrics {
    let totalTrackedTime: TimeInterval
    let appMetrics: [AppMetric]
    let siteMetrics: [SiteMetric]
}

// MARK: - Compact Disk Format

/// Per-session within a minute bucket, encoded as JSON array:
///   ["gh"]           — app, ends same minute
///   ["gh",2]         — app, ends 2 min later
///   ["gc",0,"x"]     — app + host, ends same minute
///   ["gc",2,"x"]     — app + host, ends 2 min later
private struct MinuteSession {
    let abbrev: String
    let endDelta: Int       // minutes past this bucket's minute
    let host: String?
}

extension MinuteSession: Codable {
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        abbrev = try c.decode(String.self)
        if c.isAtEnd { endDelta = 0; host = nil; return }
        endDelta = try c.decode(Int.self)
        host = c.isAtEnd ? nil : try c.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(abbrev)
        if endDelta != 0 || host != nil { try c.encode(endDelta) }
        if let host { try c.encode(host) }
    }
}

/// Daily file: base minute + sessions grouped by minute offset
private struct DailyFile: Codable {
    var b: Int                              // base minute
    var m: [String: [MinuteSession]]        // minuteOffset → sessions
}

/// Global registry — app abbreviations + host abbreviations
private struct AppRegistry: Codable {
    var apps: [String: [String]]
    var hosts: [String: String]
    init() { apps = [:]; hosts = [:] }
}

// MARK: - UsageTracker

@Observable
final class UsageTracker {
    private let settingsManager: SettingsManager
    private var currentSession: UsageSession?
    private(set) var isSleeping = false

    private var pendingSessions: [(dateKey: String, session: UsageSession)] = []
    private var currentSessionDateKey: String?
    private var flushTimer: Timer?
    private static let flushInterval: TimeInterval = 60

    private var registry = AppRegistry()
    private var bundleIdToAbbrev: [String: String] = [:]
    private var hostToAbbrev: [String: String] = [:]

    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var screenSleepObserver: NSObjectProtocol?
    private var screenWakeObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    private let analyticsDir: URL
    private var registryURL: URL { analyticsDir.appendingPathComponent("apps.json") }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.analyticsDir = appSupport.appendingPathComponent("FocusHue/analytics", isDirectory: true)

        try? FileManager.default.createDirectory(at: analyticsDir, withIntermediateDirectories: true)

        loadRegistry()
        setupObservers()
        startFlushTimer()
    }

    deinit {
        flushTimer?.invalidate()
        let center = NSWorkspace.shared.notificationCenter
        if let o = sleepObserver { center.removeObserver(o) }
        if let o = wakeObserver { center.removeObserver(o) }
        if let o = screenSleepObserver { center.removeObserver(o) }
        if let o = screenWakeObserver { center.removeObserver(o) }
        if let o = terminateObserver { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - App Registry

    private func loadRegistry() {
        if let data = try? Data(contentsOf: registryURL),
           let reg = try? jsonDecoder.decode(AppRegistry.self, from: data) {
            registry = reg
        }
        rebuildReverseLookup()
    }

    private func saveRegistry() {
        guard let data = try? jsonEncoder.encode(registry) else { return }
        try? data.write(to: registryURL, options: .atomic)
    }

    private func rebuildReverseLookup() {
        bundleIdToAbbrev = [:]
        for (abbrev, info) in registry.apps where info.count >= 2 {
            bundleIdToAbbrev[info[1]] = abbrev
        }
        hostToAbbrev = [:]
        for (abbrev, host) in registry.hosts {
            hostToAbbrev[host] = abbrev
        }
    }

    private func abbreviation(for appName: String, bundleId: String) -> String {
        if let existing = bundleIdToAbbrev[bundleId] { return existing }
        let abbrev = generateAbbreviation(for: appName)
        registry.apps[abbrev] = [appName, bundleId]
        bundleIdToAbbrev[bundleId] = abbrev
        saveRegistry()
        return abbrev
    }

    private func generateAbbreviation(for appName: String) -> String {
        let words = appName.split(separator: " ")
        let base: String
        if words.count >= 2 {
            base = String(words.map { $0.first! }).lowercased()
        } else {
            base = String(appName.prefix(2)).lowercased()
        }
        if registry.apps[base] == nil { return base }
        var n = 2
        while registry.apps["\(base)\(n)"] != nil { n += 1 }
        return "\(base)\(n)"
    }

    private func resolveAbbrev(_ abbrev: String) -> (name: String, bundleId: String)? {
        guard let info = registry.apps[abbrev], info.count >= 2 else { return nil }
        return (info[0], info[1])
    }

    // MARK: - Host Registry

    private func hostAbbreviation(for host: String) -> String {
        if let existing = hostToAbbrev[host] { return existing }
        let abbrev = generateHostAbbreviation(for: host)
        registry.hosts[abbrev] = host
        hostToAbbrev[host] = abbrev
        saveRegistry()
        return abbrev
    }

    private func generateHostAbbreviation(for host: String) -> String {
        var h = host
        if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
        for tld in [".com", ".org", ".net", ".io", ".co", ".edu", ".gov"] {
            if h.hasSuffix(tld) { h = String(h.dropLast(tld.count)); break }
        }
        let parts = h.split(separator: ".")
        let base: String
        if parts.count >= 2 {
            base = String(parts.map { $0.first! }).lowercased()
        } else {
            base = String(h.prefix(2)).lowercased()
        }
        if registry.hosts[base] == nil { return base }
        var n = 2
        while registry.hosts["\(base)\(n)"] != nil { n += 1 }
        return "\(base)\(n)"
    }

    private func resolveHostAbbrev(_ abbrev: String) -> String? {
        registry.hosts[abbrev]
    }

    // MARK: - URL Helpers

    /// Extract host from URL, http/https only (filters out chrome://, chrome-extension://, etc.)
    private static func hostFrom(_ urlString: String?) -> String? {
        guard let urlString, !urlString.isEmpty,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else { return nil }
        return host
    }

    // MARK: - Flush Timer

    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: Self.flushInterval, repeats: true) { [weak self] _ in
            self?.flushPendingSessions()
        }
    }

    // MARK: - Observers

    private func setupObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter

        sleepObserver = wsCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.handleSleep() }

        wakeObserver = wsCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.handleWake() }

        screenSleepObserver = wsCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.handleSleep() }

        screenWakeObserver = wsCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.handleWake() }

        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.endCurrentSession()
            self?.flushPendingSessions()
        }
    }

    private func handleSleep() {
        isSleeping = true
        endCurrentSession()
        flushPendingSessions()
    }

    private func handleWake() {
        isSleeping = false
    }

    // MARK: - Session Tracking

    func handleAppChange(appName: String, bundleId: String, url: String?) {
        guard settingsManager.isAnalyticsEnabled, !isSleeping else { return }

        let host = Self.hostFrom(url)

        if appName == currentSession?.app && host == currentSession?.host { return }

        endCurrentSession()
        startSession(app: appName, bundleId: bundleId, host: host)
    }

    func endCurrentSession() {
        guard var session = currentSession else { return }
        session.endMin = UsageSession.currentMinute()
        let dateKey = currentSessionDateKey ?? dateFormatter.string(from: Date())
        currentSession = nil
        currentSessionDateKey = nil
        pendingSessions.append((dateKey: dateKey, session: session))
    }

    private func startSession(app: String, bundleId: String, host: String?) {
        currentSessionDateKey = dateFormatter.string(from: Date())
        currentSession = UsageSession(
            app: app,
            bundleId: bundleId,
            host: host,
            startMin: UsageSession.currentMinute()
        )
    }

    // MARK: - File I/O

    private func fileURL(for dateKey: String) -> URL {
        analyticsDir.appendingPathComponent(dateKey + ".json")
    }

    private func fileURL(for date: Date) -> URL {
        fileURL(for: dateFormatter.string(from: date))
    }

    private func loadFile(_ dateKey: String) -> DailyFile {
        let url = fileURL(for: dateKey)
        guard let data = try? Data(contentsOf: url),
              let file = try? jsonDecoder.decode(DailyFile.self, from: data) else {
            return DailyFile(b: 0, m: [:])
        }
        return file
    }

    private func saveFile(_ file: DailyFile, to dateKey: String) {
        let url = fileURL(for: dateKey)
        guard let data = try? jsonEncoder.encode(file) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadSessions(from dateKey: String) -> [UsageSession] {
        let file = loadFile(dateKey)
        var result: [UsageSession] = []
        for (offsetStr, sessions) in file.m {
            guard let offset = Int(offsetStr) else { continue }
            let startMin = file.b + offset
            for ms in sessions {
                guard let app = resolveAbbrev(ms.abbrev) else { continue }
                result.append(UsageSession(
                    app: app.name,
                    bundleId: app.bundleId,
                    host: ms.host.flatMap { resolveHostAbbrev($0) },
                    startMin: startMin,
                    endMin: startMin + ms.endDelta
                ))
            }
        }
        return result
    }

    private func flushPendingSessions() {
        guard !pendingSessions.isEmpty else { return }
        let sessions = pendingSessions
        pendingSessions.removeAll()

        var byDate: [String: [UsageSession]] = [:]
        for (dateKey, session) in sessions {
            byDate[dateKey, default: []].append(session)
        }

        for (dateKey, newSessions) in byDate {
            var file = loadFile(dateKey)
            if file.m.isEmpty {
                file.b = newSessions[0].startMin
            }
            for session in newSessions {
                let appAbbrev = abbreviation(for: session.app, bundleId: session.bundleId)
                let minOffset = session.startMin - file.b
                let endDelta = (session.endMin ?? session.startMin) - session.startMin
                let hAbbrev = session.host.map { hostAbbreviation(for: $0) }
                let key = String(minOffset)
                file.m[key, default: []].append(MinuteSession(abbrev: appAbbrev, endDelta: endDelta, host: hAbbrev))
            }
            saveFile(file, to: dateKey)
        }
    }

    // MARK: - Metrics

    func calculateMetrics(for date: Date) -> DailyMetrics {
        let dateKey = dateFormatter.string(from: date)
        var sessions = loadSessions(from: dateKey)
        let nowMin = UsageSession.currentMinute()
        let isToday = Calendar.current.isDateInToday(date)

        for (key, session) in pendingSessions where key == dateKey {
            sessions.append(session)
        }

        if isToday, let session = currentSession, currentSessionDateKey == dateKey {
            var snapshot = session
            snapshot.endMin = nowMin
            sessions.append(snapshot)
        }

        var appDurations: [String: (name: String, duration: TimeInterval)] = [:]
        var siteDurations: [String: TimeInterval] = [:]

        for session in sessions {
            let duration = session.durationSeconds(nowMin: isToday ? nowMin : nil)

            let existing = appDurations[session.bundleId]
            appDurations[session.bundleId] = (
                name: session.app,
                duration: (existing?.duration ?? 0) + duration
            )

            if let host = session.host {
                siteDurations[host, default: 0] += duration
            }
        }

        let appMetrics = appDurations.map { AppMetric(name: $0.value.name, bundleId: $0.key, duration: $0.value.duration) }
            .sorted { $0.duration > $1.duration }
        let siteMetrics = siteDurations.map { SiteMetric(host: $0.key, duration: $0.value) }
            .sorted { $0.duration > $1.duration }
        let total = appMetrics.reduce(0) { $0 + $1.duration }

        return DailyMetrics(totalTrackedTime: total, appMetrics: appMetrics, siteMetrics: siteMetrics)
    }

    // MARK: - Data Management

    func calculateStorageSize() -> String {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: analyticsDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "0 KB"
        }
        var totalBytes: Int64 = 0
        for file in files where file.pathExtension == "json" {
            if let attrs = try? fm.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? Int64 {
                totalBytes += size
            }
        }
        if totalBytes < 1024 {
            return "\(totalBytes) B"
        } else if totalBytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(totalBytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(totalBytes) / (1024.0 * 1024.0))
        }
    }

    func openRawDataFile(for date: Date = Date()) {
        flushPendingSessions()
        let url = fileURL(for: date)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        }
    }

    func deleteAllData() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: analyticsDir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            try? fm.removeItem(at: file)
        }
        registry = AppRegistry()
        bundleIdToAbbrev = [:]
        hostToAbbrev = [:]
    }
}
