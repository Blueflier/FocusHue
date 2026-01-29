//
//  MenuBarView.swift
//  FocusHue
//
//  Menu bar dropdown view with status, controls, and debug info
//

import SwiftUI

struct MenuBarView: View {
    @Binding var isEnabled: Bool
    @Environment(PermissionManager.self) private var permissionManager
    @Environment(DisplayController.self) private var displayController
    @Environment(AppMonitor.self) private var appMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status Section
            statusSection

            Divider()

            // Progress Section (when transitioning)
            if displayController.isTransitioning {
                progressSection
                Divider()
            }

            // Controls Section
            controlsSection

            Divider()

            // Debug Section
            debugSection

            Divider()

            // Quit
            Button("Quit FocusHue") {
                displayController.reset()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 280)
        .onChange(of: appMonitor.isOnDistractingSite) { _, isDistracted in
            handleDistractionChange(isDistracted: isDistracted)
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                displayController.reset()
            }
        }
    }

    // MARK: - Distraction Handling

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

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.headline)
            }

            if !permissionManager.hasAccessibilityPermission {
                Text("Accessibility permission required")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private var statusText: String {
        if !isEnabled {
            return "Disabled"
        } else if displayController.isGrayscaleEnabled {
            return "Grayscale Active"
        } else if displayController.isTransitioning {
            return "Transitioning..."
        } else if appMonitor.isOnDistractingSite {
            return "Distraction Detected"
        } else {
            return "Monitoring"
        }
    }

    private var statusColor: Color {
        if !isEnabled {
            return .gray
        } else if displayController.isGrayscaleEnabled {
            return .purple
        } else if displayController.isTransitioning {
            return .orange
        } else if appMonitor.isOnDistractingSite {
            return .red
        } else {
            return .green
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Grayscale in \(remainingSeconds)s")
                .font(.caption)
                .foregroundColor(.secondary)

            ProgressView(value: displayController.transitionProgress)
                .progressViewStyle(.linear)
        }
    }

    private var remainingSeconds: Int {
        let remaining = (1.0 - displayController.transitionProgress) * 15.0
        return max(0, Int(remaining.rounded()))
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enable Monitoring", isOn: $isEnabled)
                .toggleStyle(.switch)

            Button("Test Grayscale (5s)") {
                displayController.testGrayscale(duration: 5.0)
            }
            .disabled(!permissionManager.hasAccessibilityPermission)

            if !permissionManager.hasAccessibilityPermission {
                Button("Grant Accessibility Permission") {
                    permissionManager.requestAccessibilityPermission()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Debug Section

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Debug Info")
                .font(.caption)
                .foregroundColor(.secondary)

            Group {
                HStack {
                    Text("App:")
                        .foregroundColor(.secondary)
                    Text(appMonitor.currentAppName.isEmpty ? "-" : appMonitor.currentAppName)
                }

                HStack {
                    Text("URL:")
                        .foregroundColor(.secondary)
                    Text(appMonitor.currentURL.isEmpty ? "-" : truncatedURL)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Text("Distracting:")
                        .foregroundColor(.secondary)
                    Text(appMonitor.isOnDistractingSite ? "Yes" : "No")
                        .foregroundColor(appMonitor.isOnDistractingSite ? .red : .green)
                }

                HStack {
                    Text("Grayscale:")
                        .foregroundColor(.secondary)
                    Text(displayController.isGrayscaleEnabled ? "On" : "Off")
                }
            }
            .font(.caption)
        }
    }

    private var truncatedURL: String {
        let url = appMonitor.currentURL
        if url.count > 40 {
            return String(url.prefix(37)) + "..."
        }
        return url
    }
}
