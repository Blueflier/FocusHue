//
//  LaunchAtLoginManager.swift
//  FocusHue
//
//  Manages launch at login using ServiceManagement framework
//

import Foundation
import ServiceManagement
import AppKit

@Observable
final class LaunchAtLoginManager {
    
    /// Whether launch at login is currently enabled
    var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                return legacyIsEnabled
            }
        }
        set {
            setLaunchAtLogin(enabled: newValue)
        }
    }
    
    /// Status message for UI display
    var statusMessage: String {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                return "Opens automatically at login"
            case .notRegistered:
                return "Will not open at login"
            case .notFound:
                return "Service not found"
            case .requiresApproval:
                return "Requires approval in System Settings"
            @unknown default:
                return "Unknown status"
            }
        } else {
            return legacyIsEnabled ? "Opens automatically at login" : "Will not open at login"
        }
    }
    
    /// Whether the setting requires user to go to System Settings
    var requiresSystemSettings: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .requiresApproval
        }
        return false
    }
    
    // Legacy support for macOS 12 and earlier
    private var legacyIsEnabled: Bool {
        // Check if app is in login items using legacy method
        // This is a simplified check - in production you'd use the deprecated SMLoginItemSetEnabled
        return UserDefaults.standard.bool(forKey: "launchAtLoginEnabled")
    }
    
    init() {
        // Nothing to load - we check the system directly
    }
    
    // MARK: - Actions
    
    /// Enable or disable launch at login
    func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
            }
        } else {
            // Legacy fallback - store preference (actual login item management would need more code)
            UserDefaults.standard.set(enabled, forKey: "launchAtLoginEnabled")
        }
    }
    
    /// Open System Settings to the Login Items page
    func openSystemSettings() {
        if #available(macOS 13.0, *) {
            // Open directly to Login Items in System Settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        } else {
            // Open to Users & Groups for older macOS
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.users") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    /// Toggle launch at login
    func toggle() {
        isEnabled.toggle()
    }
}
