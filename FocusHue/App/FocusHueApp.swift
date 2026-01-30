//
//  FocusHueApp.swift
//  FocusHue
//
//  Created by Joseph Hartono on 1/6/26.
//

import SwiftUI
import Combine

@main
struct FocusHueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var appState = AppState()

    var body: some Scene {
        // Menu bar icon with rich SwiftUI content
        MenuBarExtra {
            MenuBarView(appState: appState)
                .environment(appState.settingsManager)
                .environment(appState.permissionManager)
                .environment(appState.displayController)
                .environment(appState.appMonitor)
                .environment(appState.hotkeyManager)
                .environment(appState.launchAtLoginManager)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        // Onboarding window (shows on first launch)
        Window("Welcome to FocusHue", id: "onboarding") {
            OnboardingView()
                .environment(appState.permissionManager)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        
        // Settings window (opened from menu bar)
        Window("FocusHue Settings", id: "settings") {
            SettingsView()
                .environment(appState.settingsManager)
                .environment(appState.hotkeyManager)
                .environment(appState.launchAtLoginManager)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    private var menuBarIcon: String {
        if appState.displayController.isGrayscaleEnabled {
            return "eye.circle.fill"
        } else if appState.displayController.isTransitioning {
            return "eye.trianglebadge.exclamationmark"
        } else if appState.appMonitor.isOnDistractingSite && appState.isEnabled {
            return "exclamationmark.triangle"
        } else {
            return "eye.circle"
        }
    }
}

// MARK: - App State Container
/// Holds all app state objects with proper initialization order
@Observable
final class AppState {
    let settingsManager: SettingsManager
    let permissionManager: PermissionManager
    let displayController: DisplayController
    let appMonitor: AppMonitor
    let hotkeyManager: HotkeyManager
    let launchAtLoginManager: LaunchAtLoginManager
    
    var isEnabled: Bool = true {
        didSet {
            if !isEnabled {
                displayController.reset()
            }
        }
    }
    
    private var observationTask: Task<Void, Never>?
    
    init() {
        // Initialize settings first since other managers depend on it
        self.settingsManager = SettingsManager()
        self.permissionManager = PermissionManager()
        self.displayController = DisplayController(settingsManager: settingsManager)
        self.appMonitor = AppMonitor(settingsManager: settingsManager)
        self.hotkeyManager = HotkeyManager()
        self.launchAtLoginManager = LaunchAtLoginManager()
        
        // Setup hotkey callback to toggle grayscale
        setupHotkeyCallback()
        
        // Start observing distraction changes immediately
        startObserving()
    }
    
    private func setupHotkeyCallback() {
        hotkeyManager.onHotkeyPressed = { [weak self] in
            guard let self = self else { return }
            
            // Toggle grayscale state
            if self.displayController.isGrayscaleEnabled || self.displayController.isTransitioning {
                self.displayController.reset()
            } else {
                self.displayController.enableGrayscale()
            }
        }
    }
    
    private func startObserving() {
        // Use a polling approach to watch for changes since we can't use Combine with @Observable
        observationTask = Task { @MainActor [weak self] in
            var lastDistractionState = false
            
            while !Task.isCancelled {
                guard let self = self else { break }
                
                let currentState = self.appMonitor.isOnDistractingSite
                
                // Only react to changes
                if currentState != lastDistractionState {
                    lastDistractionState = currentState
                    self.handleDistractionChange(isDistracted: currentState)
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
    }
    
    private func handleDistractionChange(isDistracted: Bool) {
        guard isEnabled && permissionManager.hasAccessibilityPermission else { return }
        
        if isDistracted {
            // Start gradual transition to grayscale
            if !displayController.isGrayscaleEnabled && !displayController.isTransitioning {
                displayController.startGradualTransition(toGrayscale: true)
            }
        } else {
            // Cancel transition or disable grayscale
            displayController.startGradualTransition(toGrayscale: false)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check if onboarding needed and open window
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if !hasCompletedOnboarding {
            // Small delay to ensure window is registered
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let window = NSApp.windows.first(where: { $0.title == "Welcome to FocusHue" }) {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }
}

// MARK: - Distraction Coordinator

/// Coordinates between AppMonitor and DisplayController to trigger grayscale on distractions
@Observable
final class DistractionCoordinator {
    private let appMonitor: AppMonitor
    private let displayController: DisplayController
    private var isEnabled: Bool = true
    private var cancellables = Set<AnyCancellable>()

    init(appMonitor: AppMonitor, displayController: DisplayController) {
        self.appMonitor = appMonitor
        self.displayController = displayController
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            displayController.reset()
        }
    }

    func checkAndUpdateGrayscale() {
        guard isEnabled else { return }

        if appMonitor.isOnDistractingSite {
            if !displayController.isGrayscaleEnabled && !displayController.isTransitioning {
                displayController.startGradualTransition(toGrayscale: true)
            }
        } else {
            if displayController.isGrayscaleEnabled || displayController.isTransitioning {
                displayController.startGradualTransition(toGrayscale: false)
            }
        }
    }
}
