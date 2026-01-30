//
//  MenuBarView.swift
//  FocusHue
//
//  Menu bar dropdown view with status, controls, and debug info
//

import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(PermissionManager.self) private var permissionManager
    @Environment(DisplayController.self) private var displayController
    @Environment(AppMonitor.self) private var appMonitor
    
    @State private var showingSettings = false

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
        if !appState.isEnabled {
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
        if !appState.isEnabled {
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
        let remaining = (1.0 - displayController.transitionProgress) * settingsManager.activationDelay
        return max(0, Int(remaining.rounded()))
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enable Monitoring", isOn: $appState.isEnabled)
                .toggleStyle(.switch)

            Button("Test Grayscale (5s)") {
                displayController.testGrayscale(duration: 5.0)
            }
            .disabled(!permissionManager.hasAccessibilityPermission)
            
            Button {
                showingSettings = true
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environment(settingsManager)
            }

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

            // Automation permission warning
            if !appMonitor.hasAutomationPermission || !permissionManager.hasAnyBrowserAutomationPermission {
                automationWarningSection
            }
        }
    }

    // MARK: - Automation Warning Section

    private var automationWarningSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Browser Automation Required")
                    .font(.caption)
                    .fontWeight(.medium)
            }

            Text("Grant permission to detect browser URLs")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                if permissionManager.hasBrowserAutomationDenied {
                    Button("Open Settings") {
                        permissionManager.openAutomationSettings()
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button("Grant for Chrome") {
                        permissionManager.requestChromeAutomationPermission()
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
    }

    private var truncatedURL: String {
        let url = appMonitor.currentURL
        if url.count > 40 {
            return String(url.prefix(37)) + "..."
        }
        return url
    }
}
