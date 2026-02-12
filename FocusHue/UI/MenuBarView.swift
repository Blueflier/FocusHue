//
//  MenuBarView.swift
//  FocusHue
//
//  Menu bar dropdown view with status, settings, and quit
//

import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState
    @Environment(DisplayController.self) private var displayController
    @Environment(AppMonitor.self) private var appMonitor
    @Environment(PermissionManager.self) private var permissionManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status Section
            statusSection

            Divider()

            HStack {
                // Settings
                Button {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)

                Spacer()

                // Quit
                Button("Quit") {
                    displayController.reset()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.headline)
            }

            // Accessibility permission warning
            if !permissionManager.hasAccessibilityPermission {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Accessibility permission required")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Text("Needed to control screen color filters")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Button("Request Permission") {
                            permissionManager.requestAccessibilityPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("Open Settings") {
                            permissionManager.openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }

            // Automation permission warning (only if accessibility is granted)
            if permissionManager.hasAccessibilityPermission && !permissionManager.hasAnyBrowserAutomationPermission {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Browser automation permission needed")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Text("Needed to detect which website you're viewing")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        // Chrome button
                        if permissionManager.chromeAutomationStatus != .granted {
                            Button("Allow Chrome") {
                                permissionManager.requestChromeAutomationPermission()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        // Brave button
                        if permissionManager.braveAutomationStatus != .granted {
                            Button("Allow Brave") {
                                permissionManager.requestBraveAutomationPermission()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }

                    if permissionManager.hasBrowserAutomationDenied {
                        Button("Open Automation Settings") {
                            permissionManager.openAutomationSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
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
            return "FocusHue Monitoring"
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
}
