//
//  PermissionManager.swift
//  FocusHue
//
//  Manages Accessibility permission checking and requesting
//

import Foundation
import AppKit
import ApplicationServices

@Observable
final class PermissionManager {
    private(set) var hasAccessibilityPermission: Bool = false

    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 2.0

    init() {
        checkAccessibilityPermission()
        startPolling()
    }

    deinit {
        stopPolling()
    }

    // MARK: - Public API

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

    /// Open System Settings to the Automation > Privacy pane
    func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Polling

    /// Start polling for permission changes
    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.checkAccessibilityPermission()
        }
    }

    /// Stop polling for permission changes
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
}
