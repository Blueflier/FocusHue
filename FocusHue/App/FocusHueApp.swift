//
//  FocusHueApp.swift
//  FocusHue
//
//  Created by Joseph Hartono on 1/6/26.
//

import SwiftUI

@main
struct FocusHueApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var permissionManager = PermissionManager()
    @State private var isEnabled = true

    var body: some Scene {
        // Menu bar icon
        MenuBarExtra {
            MenuBarView(isEnabled: $isEnabled)
                .environment(permissionManager)
        } label: {
            Image(systemName: "eye.circle")
        }

        // Onboarding window (shows on first launch)
        Window("Onboarding", id: "onboarding") {
            OnboardingView()
                .environment(permissionManager)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
