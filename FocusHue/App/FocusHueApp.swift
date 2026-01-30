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
    @State private var isEnabled = true

    var body: some Scene {
        // Menu bar icon with rich SwiftUI content
        MenuBarExtra {
            MenuBarView(isEnabled: $isEnabled)
                .environment(appState.settingsManager)
                .environment(appState.permissionManager)
                .environment(appState.displayController)
                .environment(appState.appMonitor)
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
    }

    private var menuBarIcon: String {
        if appState.displayController.isGrayscaleEnabled {
            return "eye.circle.fill"
        } else if appState.displayController.isTransitioning {
            return "eye.trianglebadge.exclamationmark"
        } else if appState.appMonitor.isOnDistractingSite && isEnabled {
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
    
    init() {
        // Initialize settings first since other managers depend on it
        self.settingsManager = SettingsManager()
        self.permissionManager = PermissionManager()
        self.displayController = DisplayController(settingsManager: settingsManager)
        self.appMonitor = AppMonitor(settingsManager: settingsManager)
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
