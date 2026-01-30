//
//  PermissionManager.swift
//  FocusHue
//
//  Manages Accessibility and Automation permission checking and requesting
//

import Foundation
import AppKit
import ApplicationServices
import Carbon

/// Result of checking automation permission for a target app
enum AutomationPermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
    case targetNotRunning
    case unknown(OSStatus)
    
    var isGranted: Bool {
        if case .granted = self { return true }
        return false
    }
    var isDenied: Bool {
        if case .denied = self { return true }
        return false
    }
    var needsPrompt: Bool {
        if case .notDetermined = self { return true }
        return false
    }
}

@Observable
final class PermissionManager {
    private(set) var hasAccessibilityPermission: Bool = false
    private(set) var chromeAutomationStatus: AutomationPermissionStatus = .notDetermined
    private(set) var braveAutomationStatus: AutomationPermissionStatus = .notDetermined
    
    /// Combined status: true if at least one supported browser has automation permission
    var hasAnyBrowserAutomationPermission: Bool {
        chromeAutomationStatus.isGranted || braveAutomationStatus.isGranted
    }
    
    /// True if any browser permission was explicitly denied
    var hasBrowserAutomationDenied: Bool {
        chromeAutomationStatus.isDenied || braveAutomationStatus.isDenied
    }

    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 2.0
    
    // Bundle IDs for supported browsers
    static let chromeBundleId = "com.google.Chrome"
    static let braveBundleId = "com.brave.Browser"

    init() {
        checkAccessibilityPermission()
        checkAllAutomationPermissions()
        startPolling()
    }

    deinit {
        stopPolling()
    }

    // MARK: - Accessibility Permission

    /// Check if the app has Accessibility permission
    func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    /// Request Accessibility permission by opening System Settings
    /// This will prompt the user to grant permission
    func requestAccessibilityPermission() {
        // This prompts the system dialog if not yet trusted
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // Also check immediately in case already granted
        checkAccessibilityPermission()
    }

    /// Open System Settings to the Accessibility > Privacy pane
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - Automation Permission
    
    /// Check automation permission for all supported browsers
    func checkAllAutomationPermissions() {
        chromeAutomationStatus = checkAutomationPermission(for: Self.chromeBundleId, prompt: false)
        braveAutomationStatus = checkAutomationPermission(for: Self.braveBundleId, prompt: false)
    }
    
    /// Check automation permission for a specific app bundle ID
    /// - Parameters:
    ///   - bundleId: The target app's bundle identifier
    ///   - prompt: If true, prompts the user if permission hasn't been determined
    /// - Returns: The current permission status
    func checkAutomationPermission(for bundleId: String, prompt: Bool = false) -> AutomationPermissionStatus {
        guard let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundleId).aeDesc else {
            return .targetNotRunning
        }
        
        let status = AEDeterminePermissionToAutomateTarget(
            descriptor,
            typeWildCard,
            typeWildCard,
            prompt
        )
        
        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventNotPermitted):  // -1743: User denied
            return .denied
        case OSStatus(errAEEventWouldRequireUserConsent):  // -1744: Not yet asked
            return .notDetermined
        case OSStatus(procNotFound):  // -600: Target app not running
            return .targetNotRunning
        default:
            return .unknown(status)
        }
    }
    
    /// Request automation permission for Chrome (will prompt user if not determined)
    /// Note: Chrome must be running for this to work
    func requestChromeAutomationPermission() {
        // Launch Chrome if not running
        if !isAppRunning(bundleId: Self.chromeBundleId) {
            launchApp(bundleId: Self.chromeBundleId)
            // Give Chrome time to launch before requesting
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.chromeAutomationStatus = self?.checkAutomationPermission(for: Self.chromeBundleId, prompt: true) ?? .targetNotRunning
            }
        } else {
            chromeAutomationStatus = checkAutomationPermission(for: Self.chromeBundleId, prompt: true)
        }
    }
    
    /// Request automation permission for Brave (will prompt user if not determined)
    func requestBraveAutomationPermission() {
        if !isAppRunning(bundleId: Self.braveBundleId) {
            launchApp(bundleId: Self.braveBundleId)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.braveAutomationStatus = self?.checkAutomationPermission(for: Self.braveBundleId, prompt: true) ?? .targetNotRunning
            }
        } else {
            braveAutomationStatus = checkAutomationPermission(for: Self.braveBundleId, prompt: true)
        }
    }

    /// Open System Settings to the Automation > Privacy pane
    func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - Helper Methods
    
    /// Check if an app is currently running
    private func isAppRunning(bundleId: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleId }
    }
    
    /// Launch an app by bundle ID
    private func launchApp(bundleId: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Polling

    /// Start polling for permission changes
    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.checkAccessibilityPermission()
            self?.checkAllAutomationPermissions()
        }
    }

    /// Stop polling for permission changes
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
}
