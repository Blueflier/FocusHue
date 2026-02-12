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
