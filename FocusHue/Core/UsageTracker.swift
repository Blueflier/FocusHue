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
    let mode: MonitoringMode

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
    let greyscaleDuration: TimeInterval
    let normalDuration: TimeInterval
    let isBrowser: Bool
    var siteBreakdown: [SiteMetric]?

    var totalDuration: TimeInterval {
        greyscaleDuration + normalDuration
    }
}

struct SiteMetric: Identifiable {
    let id = UUID()
    let host: String
    let greyscaleDuration: TimeInterval
    let normalDuration: TimeInterval

    var totalDuration: TimeInterval {
        greyscaleDuration + normalDuration
    }
}

struct DailyMetrics {
    let totalTrackedTime: TimeInterval
    let appMetrics: [AppMetric]
    let siteMetrics: [SiteMetric]
    let activeModeTime: TimeInterval
    let monitoringOnlyTime: TimeInterval
}

struct HourlyUsage: Identifiable {
    let id = UUID()
    let hour: Int
    let greyscaleDuration: TimeInterval
    let normalDuration: TimeInterval

    var totalDuration: TimeInterval {
        greyscaleDuration + normalDuration
    }
}

// MARK: - Aggregated Metrics (for consolidated data)

/// Aggregated metrics file format (.agg.json)
private struct AggregatedFile: Codable {
    let type: String  // "daily", "weekly", or "monthly"
    let date: String  // YYYY-MM-DD for daily, YYYY-WNN for weekly, YYYY-MM for monthly
    var apps: [String: DurationPair]  // abbrev → durations
    var sites: [String: DurationPair]  // abbrev → durations
    var total: DurationPair
}

private struct DurationPair: Codable {
    var g: Int  // greyscale seconds
    var n: Int  // normal seconds
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
    var m: [String: [MinuteSession]]        // minuteOffset → sessions (active mode)
    var mon: [String: [MinuteSession]]?     // minuteOffset → sessions (monitoring-only mode)
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
    private var dailyDir: URL { analyticsDir.appendingPathComponent("daily", isDirectory: true) }
    private var weeklyDir: URL { analyticsDir.appendingPathComponent("weekly", isDirectory: true) }
    private var monthlyDir: URL { analyticsDir.appendingPathComponent("monthly", isDirectory: true) }

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

        let fm = FileManager.default
        try? fm.createDirectory(at: analyticsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: dailyDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: weeklyDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: monthlyDir, withIntermediateDirectories: true)

        loadRegistry()
        setupObservers()
        startFlushTimer()

        // Consolidate yesterday's data on launch
        consolidateYesterday()
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

    // MARK: - Browser Detection

    /// Check if a bundle ID belongs to a known browser
    private func isBrowserBundle(_ bundleId: String) -> Bool {
        let browsers = [
            "com.google.Chrome",
            "com.brave.Browser",
            "com.apple.Safari",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.vivaldi.Vivaldi",
            "com.operasoftware.Opera"
        ]
        return browsers.contains(bundleId)
    }

    // MARK: - URL Helpers

    /// Extract host from URL, http/https only (filters out chrome://, chrome-extension://, etc.)
    /// For localhost, returns display name from settings or "localhost:<port>"
    private func hostFrom(_ urlString: String?) -> String? {
        guard let urlString, !urlString.isEmpty,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else { return nil }

        // Check for localhost
        if host == "127.0.0.1" || host == "localhost" {
            if let port = url.port {
                let portStr = String(port)
                if let displayName = settingsManager.localhostDisplayNames[portStr] {
                    return displayName
                }
                return "localhost:\(port)"
            }
            return "localhost"
        }

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

        let host = hostFrom(url)

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
            startMin: UsageSession.currentMinute(),
            mode: settingsManager.monitoringMode
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
            return DailyFile(b: 0, m: [:], mon: nil)
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

        // Load active mode sessions
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
                    endMin: startMin + ms.endDelta,
                    mode: .greyscale
                ))
            }
        }

        // Load monitoring-only sessions
        if let monSessions = file.mon {
            for (offsetStr, sessions) in monSessions {
                guard let offset = Int(offsetStr) else { continue }
                let startMin = file.b + offset
                for ms in sessions {
                    guard let app = resolveAbbrev(ms.abbrev) else { continue }
                    result.append(UsageSession(
                        app: app.name,
                        bundleId: app.bundleId,
                        host: ms.host.flatMap { resolveHostAbbrev($0) },
                        startMin: startMin,
                        endMin: startMin + ms.endDelta,
                        mode: .normal
                    ))
                }
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
            if file.m.isEmpty && file.mon?.isEmpty != false {
                file.b = newSessions[0].startMin
            }
            for session in newSessions {
                let appAbbrev = abbreviation(for: session.app, bundleId: session.bundleId)
                let minOffset = session.startMin - file.b
                let endDelta = (session.endMin ?? session.startMin) - session.startMin
                let hAbbrev = session.host.map { hostAbbreviation(for: $0) }
                let key = String(minOffset)

                // Route to correct section based on mode
                if session.mode == .greyscale {
                    file.m[key, default: []].append(MinuteSession(abbrev: appAbbrev, endDelta: endDelta, host: hAbbrev))
                } else {
                    if file.mon == nil { file.mon = [:] }
                    file.mon?[key, default: []].append(MinuteSession(abbrev: appAbbrev, endDelta: endDelta, host: hAbbrev))
                }
            }
            saveFile(file, to: dateKey)
        }
    }

    // MARK: - Data Consolidation

    /// Consolidate old raw data (7+ days old) into daily/.agg.json
    /// Keep raw files for recent 7 days for viewing historical data
    private func consolidateYesterday() {
        let cal = Calendar.current
        let fm = FileManager.default

        // Get all raw files in analytics directory
        guard let files = try? fm.contentsOfDirectory(at: analyticsDir, includingPropertiesForKeys: [.creationDateKey]) else { return }

        let now = Date()
        for file in files {
            // Only process YYYY-MM-DD.json files (raw daily files)
            guard file.pathExtension == "json",
                  file.lastPathComponent != "apps.json",
                  file.lastPathComponent.count == 15, // "YYYY-MM-DD.json"
                  let fileDate = dateFormatter.date(from: String(file.lastPathComponent.prefix(10))) else {
                continue
            }

            // Only consolidate files 7+ days old
            let daysOld = cal.dateComponents([.day], from: fileDate, to: now).day ?? 0
            guard daysOld >= 7 else { continue }

            let dateKey = dateFormatter.string(from: fileDate)
            let aggURL = dailyDir.appendingPathComponent(dateKey + ".agg.json")

            // Skip if already consolidated
            guard !fm.fileExists(atPath: aggURL.path) else {
                try? fm.removeItem(at: file)
                continue
            }

            // Load sessions from raw file
            let sessions = loadSessions(from: dateKey)

            // Aggregate durations
            var appDurations: [String: (name: String, bundleId: String, g: Int, n: Int)] = [:]
            var siteDurations: [String: (g: Int, n: Int)] = [:]
            var totalG = 0
            var totalN = 0

            for session in sessions {
                let duration = Int(session.durationSeconds())
                let appAbbrev = abbreviation(for: session.app, bundleId: session.bundleId)

                let existing = appDurations[appAbbrev]
                if session.mode == .greyscale {
                    appDurations[appAbbrev] = (session.app, session.bundleId, (existing?.g ?? 0) + duration, existing?.n ?? 0)
                    totalG += duration
                } else {
                    appDurations[appAbbrev] = (session.app, session.bundleId, existing?.g ?? 0, (existing?.n ?? 0) + duration)
                    totalN += duration
                }

                if let host = session.host {
                    let hostAbbrev = hostAbbreviation(for: host)
                    let existingSite = siteDurations[hostAbbrev]
                    if session.mode == .greyscale {
                        siteDurations[hostAbbrev] = ((existingSite?.g ?? 0) + duration, existingSite?.n ?? 0)
                    } else {
                        siteDurations[hostAbbrev] = (existingSite?.g ?? 0, (existingSite?.n ?? 0) + duration)
                    }
                }
            }

            // Create aggregated file
            let aggFile = AggregatedFile(
                type: "daily",
                date: dateKey,
                apps: appDurations.mapValues { DurationPair(g: $0.g, n: $0.n) },
                sites: siteDurations.mapValues { DurationPair(g: $0.g, n: $0.n) },
                total: DurationPair(g: totalG, n: totalN)
            )

            // Save to daily/<date>.agg.json
            if let data = try? jsonEncoder.encode(aggFile) {
                try? data.write(to: aggURL, options: .atomic)
            }

            // Delete raw file after consolidation
            try? fm.removeItem(at: file)
        }
    }

    /// Load consolidated metrics for a date (from .agg.json if exists, else raw)
    func loadConsolidatedMetrics(date: Date) -> DailyMetrics? {
        let dateKey = dateFormatter.string(from: date)
        let aggURL = dailyDir.appendingPathComponent(dateKey + ".agg.json")

        if FileManager.default.fileExists(atPath: aggURL.path),
           let data = try? Data(contentsOf: aggURL),
           let aggFile = try? jsonDecoder.decode(AggregatedFile.self, from: data) {
            return metricsFromAggregated(aggFile)
        }

        // Fallback to raw (for today)
        return calculateMetrics(for: date)
    }

    /// Convert AggregatedFile to DailyMetrics
    private func metricsFromAggregated(_ aggFile: AggregatedFile) -> DailyMetrics {
        var appMetrics: [AppMetric] = []
        for (abbrev, dur) in aggFile.apps {
            guard let app = resolveAbbrev(abbrev) else { continue }
            appMetrics.append(AppMetric(
                name: app.name,
                bundleId: app.bundleId,
                greyscaleDuration: TimeInterval(dur.g),
                normalDuration: TimeInterval(dur.n),
                isBrowser: isBrowserBundle(app.bundleId),
                siteBreakdown: nil
            ))
        }
        appMetrics.sort { $0.totalDuration > $1.totalDuration }

        var siteMetrics: [SiteMetric] = []
        for (abbrev, dur) in aggFile.sites {
            guard let host = resolveHostAbbrev(abbrev) else { continue }
            siteMetrics.append(SiteMetric(
                host: host,
                greyscaleDuration: TimeInterval(dur.g),
                normalDuration: TimeInterval(dur.n)
            ))
        }
        siteMetrics.sort { $0.totalDuration > $1.totalDuration }

        return DailyMetrics(
            totalTrackedTime: TimeInterval(aggFile.total.g + aggFile.total.n),
            appMetrics: appMetrics,
            siteMetrics: siteMetrics,
            activeModeTime: TimeInterval(aggFile.total.g),
            monitoringOnlyTime: TimeInterval(aggFile.total.n)
        )
    }

    /// Calculate metrics for a date range (for week/month views)
    func calculateMultiDayMetrics(from startDate: Date, to endDate: Date) -> [(date: Date, metrics: DailyMetrics)] {
        var result: [(date: Date, metrics: DailyMetrics)] = []
        let cal = Calendar.current
        var current = startDate

        while current <= endDate {
            if let metrics = loadConsolidatedMetrics(date: current) {
                result.append((date: current, metrics: metrics))
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return result
    }

    // MARK: - Hourly Breakdown

    /// Get hourly usage breakdown for Apple-style chart
    func calculateHourlyBreakdown(for date: Date) -> [HourlyUsage] {
        let dateKey = dateFormatter.string(from: date)
        var sessions = loadSessions(from: dateKey)
        let nowMin = UsageSession.currentMinute()
        let isToday = Calendar.current.isDateInToday(date)

        // Include pending and current sessions if viewing today
        for (key, session) in pendingSessions where key == dateKey {
            sessions.append(session)
        }

        if isToday, let session = currentSession, currentSessionDateKey == dateKey {
            var snapshot = session
            snapshot.endMin = nowMin
            sessions.append(snapshot)
        }

        // Group by hour (0-23)
        var hourlyData: [Int: (greyscale: TimeInterval, normal: TimeInterval)] = [:]

        for session in sessions {
            let startHour = session.startMin / 60
            let endMin = session.endMin ?? (isToday ? nowMin : session.startMin)
            let endHour = endMin / 60

            // If session spans multiple hours, split it
            if startHour == endHour {
                let duration = session.durationSeconds(nowMin: isToday ? nowMin : nil)
                let existing = hourlyData[startHour]
                if session.mode == .greyscale {
                    hourlyData[startHour] = ((existing?.greyscale ?? 0) + duration, existing?.normal ?? 0)
                } else {
                    hourlyData[startHour] = (existing?.greyscale ?? 0, (existing?.normal ?? 0) + duration)
                }
            } else {
                // Split across hours
                for hour in startHour...endHour {
                    let hourStart = max(session.startMin, hour * 60)
                    let hourEnd = min(endMin, (hour + 1) * 60 - 1)
                    let duration = TimeInterval((hourEnd - hourStart + 1) * 60)

                    let existing = hourlyData[hour]
                    if session.mode == .greyscale {
                        hourlyData[hour] = ((existing?.greyscale ?? 0) + duration, existing?.normal ?? 0)
                    } else {
                        hourlyData[hour] = (existing?.greyscale ?? 0, (existing?.normal ?? 0) + duration)
                    }
                }
            }
        }

        // Convert to array
        return (0..<24).map { hour in
            let data = hourlyData[hour] ?? (0, 0)
            return HourlyUsage(hour: hour, greyscaleDuration: data.greyscale, normalDuration: data.normal)
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

        var appDurations: [String: (name: String, greyscale: TimeInterval, normal: TimeInterval)] = [:]
        var siteDurations: [String: (greyscale: TimeInterval, normal: TimeInterval)] = [:]
        var browserSiteDurations: [String: [String: (greyscale: TimeInterval, normal: TimeInterval)]] = [:]
        var activeModeTotal: TimeInterval = 0
        var monitoringOnlyTotal: TimeInterval = 0

        for session in sessions {
            let duration = session.durationSeconds(nowMin: isToday ? nowMin : nil)

            // Track app duration by mode
            let existing = appDurations[session.bundleId]
            if session.mode == .greyscale {
                appDurations[session.bundleId] = (
                    name: session.app,
                    greyscale: (existing?.greyscale ?? 0) + duration,
                    normal: existing?.normal ?? 0
                )
            } else {
                appDurations[session.bundleId] = (
                    name: session.app,
                    greyscale: existing?.greyscale ?? 0,
                    normal: (existing?.normal ?? 0) + duration
                )
            }

            // Track site duration by mode
            if let host = session.host {
                let existingSite = siteDurations[host]
                if session.mode == .greyscale {
                    siteDurations[host] = (
                        greyscale: (existingSite?.greyscale ?? 0) + duration,
                        normal: existingSite?.normal ?? 0
                    )
                } else {
                    siteDurations[host] = (
                        greyscale: existingSite?.greyscale ?? 0,
                        normal: (existingSite?.normal ?? 0) + duration
                    )
                }

                // Also track which browser this site belongs to
                if isBrowserBundle(session.bundleId) {
                    var browserSites = browserSiteDurations[session.bundleId] ?? [:]
                    let existingBrowserSite = browserSites[host]
                    if session.mode == .greyscale {
                        browserSites[host] = (
                            greyscale: (existingBrowserSite?.greyscale ?? 0) + duration,
                            normal: existingBrowserSite?.normal ?? 0
                        )
                    } else {
                        browserSites[host] = (
                            greyscale: existingBrowserSite?.greyscale ?? 0,
                            normal: (existingBrowserSite?.normal ?? 0) + duration
                        )
                    }
                    browserSiteDurations[session.bundleId] = browserSites
                }
            }

            // Track time by mode
            if session.mode == .greyscale {
                activeModeTotal += duration
            } else {
                monitoringOnlyTotal += duration
            }
        }

        // Build app metrics with browser detection and site breakdown
        var appMetrics = appDurations.map { bundleId, data -> AppMetric in
            let isBrowser = isBrowserBundle(bundleId)
            var siteBreakdown: [SiteMetric]?

            if isBrowser, let sites = browserSiteDurations[bundleId] {
                // Build site metrics for this browser
                var breakdown = sites.map { host, durations in
                    SiteMetric(
                        host: host,
                        greyscaleDuration: durations.greyscale,
                        normalDuration: durations.normal
                    )
                }
                breakdown.sort { $0.totalDuration > $1.totalDuration }

                // Calculate "Other browsing" time (browser total - sum of sites)
                let sitesTotal = breakdown.reduce(0) { $0 + $1.totalDuration }
                let browserTotal = data.greyscale + data.normal
                let otherBrowsingTime = browserTotal - sitesTotal

                if otherBrowsingTime > 120 {  // Only show if > 2 minutes
                    breakdown.append(SiteMetric(
                        host: "Other browsing",
                        greyscaleDuration: 0,
                        normalDuration: otherBrowsingTime
                    ))
                }

                siteBreakdown = breakdown
            }

            return AppMetric(
                name: data.name,
                bundleId: bundleId,
                greyscaleDuration: data.greyscale,
                normalDuration: data.normal,
                isBrowser: isBrowser,
                siteBreakdown: siteBreakdown
            )
        }
        appMetrics.sort { $0.totalDuration > $1.totalDuration }

        let siteMetrics = siteDurations.map {
            SiteMetric(
                host: $0.key,
                greyscaleDuration: $0.value.greyscale,
                normalDuration: $0.value.normal
            )
        }
        .sorted { $0.totalDuration > $1.totalDuration }

        let total = appMetrics.reduce(0) { $0 + $1.totalDuration }

        return DailyMetrics(
            totalTrackedTime: total,
            appMetrics: appMetrics,
            siteMetrics: siteMetrics,
            activeModeTime: activeModeTotal,
            monitoringOnlyTime: monitoringOnlyTotal
        )
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
