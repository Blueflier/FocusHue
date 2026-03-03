//
//  SettingsManager.swift
//  FocusHue
//
//  Manages user-configurable settings for distraction detection
//

import Foundation
import SwiftUI

/// App monitoring mode
enum MonitoringMode: String, Codable {
    case greyscale      // Grayscale activates on distraction
    case normal         // Tracks usage but no grayscale
}

@Observable
final class SettingsManager {
    // Default distraction domains
    static let defaultDistractionDomains = [
        "twitter.com",
        "x.com",
        "www.twitter.com",
        "www.x.com",
        "mobile.twitter.com",
        "mobile.x.com",
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "instagram.com",
        "www.instagram.com",
        "facebook.com",
        "www.facebook.com",
        "m.facebook.com"
    ]

    // Default activation delay in seconds (0 = instant)
    static let defaultActivationDelay: Double = 0.0

    // Minimum and maximum delay values
    static let minActivationDelay: Double = 0.0
    static let maxActivationDelay: Double = 120.0
    
    // MARK: - Stored Properties

    var distractionDomains: [String] {
        didSet {
            saveDomains()
        }
    }

    var distractionApps: [String] {  // Bundle IDs
        didSet {
            saveApps()
        }
    }
    
    var activationDelay: Double {
        didSet {
            // Clamp to valid range
            let clamped = min(max(activationDelay, Self.minActivationDelay), Self.maxActivationDelay)
            if clamped != activationDelay {
                activationDelay = clamped
            }
            saveDelay()
        }
    }

    var isAnalyticsEnabled: Bool {
        didSet {
            saveAnalytics()
        }
    }

    var monitoringMode: MonitoringMode {
        didSet {
            saveMonitoringMode()
        }
    }

    var localhostDisplayNames: [String: String] {
        didSet {
            saveLocalhostDisplayNames()
        }
    }

    // MARK: - UserDefaults Keys

    private let domainsKey = "distractionDomains"
    private let appsKey = "distractionApps"
    private let delayKey = "activationDelay"
    private let analyticsKey = "analyticsEnabled"
    private let monitoringModeKey = "monitoringMode"
    private let localhostDisplayNamesKey = "localhostDisplayNames"
    
    // MARK: - Init
    
    init() {
        // Load domains from UserDefaults or use defaults
        if let savedDomains = UserDefaults.standard.stringArray(forKey: domainsKey) {
            self.distractionDomains = savedDomains
        } else {
            self.distractionDomains = Self.defaultDistractionDomains
        }

        // Load distraction apps from UserDefaults
        if let savedApps = UserDefaults.standard.stringArray(forKey: appsKey) {
            self.distractionApps = savedApps
        } else {
            self.distractionApps = []
        }
        
        // Load delay from UserDefaults or use default
        let savedDelay = UserDefaults.standard.double(forKey: delayKey)
        if savedDelay > 0 {
            self.activationDelay = savedDelay
        } else {
            self.activationDelay = Self.defaultActivationDelay
        }

        // Load analytics setting (defaults false / opt-in)
        self.isAnalyticsEnabled = UserDefaults.standard.bool(forKey: analyticsKey)

        // Load monitoring mode (defaults to greyscale)
        if let modeString = UserDefaults.standard.string(forKey: monitoringModeKey),
           let mode = MonitoringMode(rawValue: modeString) {
            self.monitoringMode = mode
        } else {
            self.monitoringMode = .greyscale
        }

        // Load localhost display names (defaults to OpenClaw on 18789)
        if let saved = UserDefaults.standard.dictionary(forKey: localhostDisplayNamesKey) as? [String: String] {
            self.localhostDisplayNames = saved
        } else {
            self.localhostDisplayNames = ["18789": "OpenClaw"]
        }
    }
    
    // MARK: - Persistence
    
    private func saveDomains() {
        UserDefaults.standard.set(distractionDomains, forKey: domainsKey)
    }

    private func saveApps() {
        UserDefaults.standard.set(distractionApps, forKey: appsKey)
    }

    private func saveDelay() {
        UserDefaults.standard.set(activationDelay, forKey: delayKey)
    }

    private func saveAnalytics() {
        UserDefaults.standard.set(isAnalyticsEnabled, forKey: analyticsKey)
    }

    private func saveMonitoringMode() {
        UserDefaults.standard.set(monitoringMode.rawValue, forKey: monitoringModeKey)
    }

    private func saveLocalhostDisplayNames() {
        UserDefaults.standard.set(localhostDisplayNames, forKey: localhostDisplayNamesKey)
    }

    // MARK: - Domain Management
    
    /// Add a new domain to the distraction list
    func addDomain(_ domain: String) {
        let normalized = normalizeDomain(domain)
        guard !normalized.isEmpty, !distractionDomains.contains(normalized) else { return }
        distractionDomains.append(normalized)
    }
    
    /// Remove a domain from the distraction list
    func removeDomain(_ domain: String) {
        distractionDomains.removeAll { $0 == domain }
    }
    
    /// Remove domains at specific indices
    func removeDomains(at offsets: IndexSet) {
        distractionDomains.remove(atOffsets: offsets)
    }

    /// Add a distraction app by bundle ID
    func addApp(_ bundleId: String) {
        let normalized = bundleId.trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty, !distractionApps.contains(normalized) else { return }
        distractionApps.append(normalized)
    }

    /// Remove a distraction app
    func removeApp(_ bundleId: String) {
        distractionApps.removeAll { $0 == bundleId }
    }

    /// Reset to default domains
    func resetToDefaults() {
        distractionDomains = Self.defaultDistractionDomains
        distractionApps = []
        activationDelay = Self.defaultActivationDelay
        isAnalyticsEnabled = false
        monitoringMode = .greyscale
        localhostDisplayNames = ["18789": "OpenClaw"]
    }

    // MARK: - Localhost Display Names

    /// Add or update a localhost display name
    func setLocalhostDisplayName(port: String, name: String) {
        localhostDisplayNames[port] = name
    }

    /// Remove a localhost display name
    func removeLocalhostDisplayName(port: String) {
        localhostDisplayNames.removeValue(forKey: port)
    }
    
    /// Check if a URL matches any distraction domain
    func isDistractingURL(_ urlString: String) -> Bool {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let host = url.host else {
            return false
        }
        
        return distractionDomains.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }
    
    // MARK: - Helpers
    
    /// Normalize domain input (remove protocol, path, whitespace)
    private func normalizeDomain(_ input: String) -> String {
        var domain = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Remove protocol if present
        if let urlComponents = URLComponents(string: domain), let host = urlComponents.host {
            domain = host
        } else if domain.hasPrefix("http://") {
            domain = String(domain.dropFirst(7))
        } else if domain.hasPrefix("https://") {
            domain = String(domain.dropFirst(8))
        }
        
        // Remove path if present
        if let slashIndex = domain.firstIndex(of: "/") {
            domain = String(domain[..<slashIndex])
        }
        
        // Remove port if present
        if let colonIndex = domain.firstIndex(of: ":") {
            domain = String(domain[..<colonIndex])
        }
        
        return domain
    }
}
