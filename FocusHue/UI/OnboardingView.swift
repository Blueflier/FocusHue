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

                permissionStep
                    .tag(1)

                completionStep
                    .tag(2)
            }
            .tabViewStyle(.automatic)
            .frame(height: 300)

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

                if currentStep < 2 {
                    Button("Next") {
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
        .frame(width: 450, height: 380)
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

    private var permissionStep: some View {
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
