//
//  OnboardingView.swift
//  FocusHue
//
//  Onboarding flow for first-time setup
//

import SwiftUI

struct OnboardingView: View {
    @Environment(PermissionManager.self) private var permissionManager
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 0) {
            // Content
            TabView(selection: $currentStep) {
                welcomeStep
                    .tag(0)

                accessibilityPermissionStep
                    .tag(1)

                automationPermissionStep
                    .tag(2)

                completionStep
                    .tag(3)
            }
            .tabViewStyle(.automatic)
            .frame(height: 320)

            Divider()

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                }

                Spacer()

                if currentStep < 3 {
                    Button(currentStep == 2 ? "Skip" : "Next") {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(currentStep == 1 && !permissionManager.hasAccessibilityPermission)
                } else {
                    Button("Get Started") {
                        hasCompletedOnboarding = true
                        dismissWindow(id: "onboarding")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 450, height: 420)
    }

    // MARK: - Step Views

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "eye.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.purple)

            Text("Welcome to FocusHue")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("FocusHue helps you stay focused by gradually turning your screen grayscale when you visit distracting websites like Twitter/X.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
        }
        .padding()
    }

    private var accessibilityPermissionStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(permissionManager.hasAccessibilityPermission ? .green : .orange)

            Text("Accessibility Permission")
                .font(.title)
                .fontWeight(.bold)

            Text("FocusHue needs Accessibility permission to control screen color filters and monitor which app is active.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)

            if permissionManager.hasAccessibilityPermission {
                Label("Permission Granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.headline)
            } else {
                VStack(spacing: 12) {
                    Button("Request Permission") {
                        permissionManager.requestAccessibilityPermission()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Open System Settings") {
                        permissionManager.openAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)

                    Text("After enabling, click Next to continue")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }

    private var automationPermissionStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 64))
                .foregroundStyle(permissionManager.hasAnyBrowserAutomationPermission ? .green : .orange)

            Text("Browser Automation")
                .font(.title)
                .fontWeight(.bold)

            Text("FocusHue needs Automation permission to detect which website you're viewing in your browser.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)

            VStack(spacing: 12) {
                // Chrome permission
                browserPermissionRow(
                    name: "Google Chrome",
                    icon: "globe",
                    status: permissionManager.chromeAutomationStatus,
                    onRequest: { permissionManager.requestChromeAutomationPermission() }
                )
                
                // Brave permission
                browserPermissionRow(
                    name: "Brave Browser",
                    icon: "shield.fill",
                    status: permissionManager.braveAutomationStatus,
                    onRequest: { permissionManager.requestBraveAutomationPermission() }
                )
            }
            .padding(.horizontal, 40)

            if permissionManager.hasBrowserAutomationDenied {
                Button("Open Automation Settings") {
                    permissionManager.openAutomationSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Text("If denied, enable FocusHue in System Settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func browserPermissionRow(name: String, icon: String, status: AutomationPermissionStatus, onRequest: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.purple)
            
            Text(name)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            switch status {
            case .granted:
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            case .denied:
                Label("Denied", systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            case .notDetermined, .targetNotRunning:
                Button("Request") {
                    onRequest()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            case .unknown:
                Text("Unknown")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private var completionStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "eye", text: "Look for the eye icon in your menu bar")
                featureRow(icon: "safari", text: "Open Twitter/X in Chrome to trigger grayscale")
                featureRow(icon: "slider.horizontal.3", text: "Use the menu to test or disable monitoring")
            }
            .padding(.horizontal, 40)
            
            if !permissionManager.hasAnyBrowserAutomationPermission {
                Text("⚠️ No browser permissions granted. URL detection won't work until you grant permission.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .padding()
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.purple)
            Text(text)
                .foregroundColor(.secondary)
        }
    }
}
