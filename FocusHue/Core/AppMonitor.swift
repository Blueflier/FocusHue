//
//  AppMonitor.swift
//  FocusHue
//
//  Monitors active application and Chrome tab URLs for distraction detection
//

import Foundation
import AppKit
import Combine

@Observable
final class AppMonitor {
    private(set) var currentAppName: String = ""
    private(set) var currentAppBundleId: String = ""
    private(set) var currentURL: String = ""
    private(set) var isOnDistractingSite: Bool = false
    private(set) var hasAutomationPermission: Bool = true
    private(set) var automationErrorMessage: String = ""

    private var workspaceObserver: NSObjectProtocol?
    private var urlPollingTimer: Timer?
    private let urlPollingInterval: TimeInterval = 0.5
    
    // Reference to settings manager for configurable domains
    private let settingsManager: SettingsManager

    // Browser bundle IDs to monitor
    private let browserBundleIds = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "org.chromium.Chromium"
    ]

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        setupWorkspaceObserver()
        updateCurrentApp()
    }

    deinit {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        stopURLPolling()
    }

    // MARK: - App Monitoring

    private func setupWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppActivation(notification)
        }
    }

    private func handleAppActivation(_ notification: Notification) {
        updateCurrentApp()
    }

    private func updateCurrentApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            currentAppName = ""
            currentAppBundleId = ""
            stopURLPolling()
            return
        }

        currentAppName = app.localizedName ?? "Unknown"
        currentAppBundleId = app.bundleIdentifier ?? ""

        // Start or stop URL polling based on whether a browser is frontmost
        if browserBundleIds.contains(currentAppBundleId) {
            startURLPolling()
        } else {
            stopURLPolling()
            currentURL = ""
            isOnDistractingSite = false
        }
    }

    // MARK: - URL Polling

    /// Manually trigger URL fetch for testing
    func testURLGrabbing() {
        pollCurrentURL()
    }

    private func startURLPolling() {
        stopURLPolling()
        pollCurrentURL()
        urlPollingTimer = Timer.scheduledTimer(withTimeInterval: urlPollingInterval, repeats: true) { [weak self] _ in
            self?.pollCurrentURL()
        }
    }

    private func stopURLPolling() {
        urlPollingTimer?.invalidate()
        urlPollingTimer = nil
    }

    private func pollCurrentURL() {
        fetchChromeURL { [weak self] url in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.currentURL = url ?? ""
                self.updateDistractionStatus()
            }
        }
    }

    // MARK: - Chrome URL Detection via AppleScript

    private func fetchChromeURL(completion: @escaping (String?) -> Void) {
        let script: String

        switch currentAppBundleId {
        case "com.google.Chrome", "com.google.Chrome.canary":
            script = """
                tell application "Google Chrome"
                    if (count of windows) > 0 then
                        return URL of active tab of front window
                    end if
                end tell
                return ""
            """
        case "com.brave.Browser":
            script = """
                tell application "Brave Browser"
                    if (count of windows) > 0 then
                        return URL of active tab of front window
                    end if
                end tell
                return ""
            """
        default:
            completion(nil)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            let appleScript = NSAppleScript(source: script)
            let result = appleScript?.executeAndReturnError(&error)

            if let errorInfo = error {
                let errorNum = errorInfo[NSAppleScript.errorNumber] as? Int
                print("AppleScript error: \(errorInfo)")

                DispatchQueue.main.async {
                    if errorNum == -1743 {
                        // Not authorized to send Apple events
                        self?.hasAutomationPermission = false
                        self?.automationErrorMessage = "Automation permission required for Chrome"
                    }
                }
                completion(nil)
                return
            }

            DispatchQueue.main.async {
                self?.hasAutomationPermission = true
                self?.automationErrorMessage = ""
            }
            completion(result?.stringValue)
        }
    }

    // MARK: - Distraction Detection

    private func updateDistractionStatus() {
        // Check if current app is a distraction app
        if settingsManager.distractionApps.contains(currentAppBundleId) {
            isOnDistractingSite = true
            return
        }

        // Check if URL is distracting
        guard !currentURL.isEmpty else {
            isOnDistractingSite = false
            return
        }

        isOnDistractingSite = settingsManager.isDistractingURL(currentURL)
    }
}
