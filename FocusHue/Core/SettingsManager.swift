//
//  SettingsManager.swift
//  FocusHue
//
//  Manages user-configurable settings for distraction detection
//

import Foundation
import SwiftUI

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

    // MARK: - UserDefaults Keys

    private let domainsKey = "distractionDomains"
    private let delayKey = "activationDelay"
    private let analyticsKey = "analyticsEnabled"
    
    // MARK: - Init
    
    init() {
        // Load domains from UserDefaults or use defaults
        if let savedDomains = UserDefaults.standard.stringArray(forKey: domainsKey) {
            self.distractionDomains = savedDomains
        } else {
            self.distractionDomains = Self.defaultDistractionDomains
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
    }
    
    // MARK: - Persistence
    
    private func saveDomains() {
        UserDefaults.standard.set(distractionDomains, forKey: domainsKey)
    }
    
    private func saveDelay() {
        UserDefaults.standard.set(activationDelay, forKey: delayKey)
    }

    private func saveAnalytics() {
        UserDefaults.standard.set(isAnalyticsEnabled, forKey: analyticsKey)
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
    
    /// Reset to default domains
    func resetToDefaults() {
        distractionDomains = Self.defaultDistractionDomains
        activationDelay = Self.defaultActivationDelay
        isAnalyticsEnabled = false
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
