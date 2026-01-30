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
    
    /// Check automation permission for all supported browsers (only if running)
    func checkAllAutomationPermissions() {
        // Only check if the browser is running to avoid console spam
        if isAppRunning(bundleId: Self.chromeBundleId) {
            chromeAutomationStatus = checkAutomationPermission(for: Self.chromeBundleId, prompt: false)
        }
        if isAppRunning(bundleId: Self.braveBundleId) {
            braveAutomationStatus = checkAutomationPermission(for: Self.braveBundleId, prompt: false)
        }
    }
    
    /// Check automation permission for a specific app bundle ID
    /// - Parameters:
    ///   - bundleId: The target app's bundle identifier
    ///   - prompt: If true, prompts the user if permission hasn't been determined
    /// - Returns: The current permission status
    func checkAutomationPermission(for bundleId: String, prompt: Bool = false) -> AutomationPermissionStatus {
        // Don't check if app isn't running - avoids procNotFound spam
        guard isAppRunning(bundleId: bundleId) else {
            return .targetNotRunning
        }
        
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
    
    /// Request automation permission for Chrome by actually sending an Apple Event
    /// This is required to make the app appear in System Settings > Automation
    func requestChromeAutomationPermission() {
        requestAutomationPermission(
            bundleId: Self.chromeBundleId,
            appName: "Google Chrome"
        ) { [weak self] status in
            self?.chromeAutomationStatus = status
        }
    }
    
    /// Request automation permission for Brave by actually sending an Apple Event
    func requestBraveAutomationPermission() {
        requestAutomationPermission(
            bundleId: Self.braveBundleId,
            appName: "Brave Browser"
        ) { [weak self] status in
            self?.braveAutomationStatus = status
        }
    }
    
    /// Request automation permission by sending an actual Apple Event
    /// This triggers the system permission dialog and registers the app in System Settings
    private func requestAutomationPermission(bundleId: String, appName: String, completion: @escaping (AutomationPermissionStatus) -> Void) {
        // Launch the app if not running
        if !isAppRunning(bundleId: bundleId) {
            launchApp(bundleId: bundleId)
        }
        
        // Give the app time to launch, then send an Apple Event
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            
            // Actually send an Apple Event - this is what triggers the permission dialog
            // and registers our app in System Settings > Privacy > Automation
            let script = NSAppleScript(source: """
                tell application "\(appName)"
                    if (count of windows) > 0 then
                        return name of front window
                    else
                        return ""
                    end if
                end tell
            """)
            
            var error: NSDictionary?
            DispatchQueue.global(qos: .userInitiated).async {
                script?.executeAndReturnError(&error)
                
                DispatchQueue.main.async {
                    if let errorInfo = error {
                        let errorNum = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
                        if errorNum == -1743 {
                            completion(.denied)
                        } else {
                            completion(.notDetermined)
                        }
                    } else {
                        completion(.granted)
                    }
                }
            }
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
