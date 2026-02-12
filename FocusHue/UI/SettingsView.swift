//
//  SettingsView.swift
//  FocusHue
//
//  Settings panel for configuring distraction domains, activation delay, hotkey, and launch at login
//

import SwiftUI
import Carbon
import AppKit

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(HotkeyManager.self) private var hotkeyManager
    @Environment(LaunchAtLoginManager.self) private var launchAtLoginManager
    @Environment(DisplayController.self) private var displayController
    @Environment(AppMonitor.self) private var appMonitor
    @Environment(PermissionManager.self) private var permissionManager

    @Bindable var appState: AppState

    @State private var newDomain: String = ""
    @State private var showingResetConfirmation = false
    @State private var isRecordingHotkey = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // General Section
                    generalSection

                    Divider()

                    // Hotkey Section
                    hotkeySection

                    Divider()

                    // Activation Delay Section
                    delaySection

                    Divider()

                    // Distraction Domains Section
                    domainsSection

                    Divider()

                    // Debug & Testing Section
                    debugSection
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Button("Reset to Defaults") {
                    showingResetConfirmation = true
                }
                .foregroundColor(.red)

                Spacer()

                Button("Done") {
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 380, height: 600)
        .alert("Reset Settings?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                settingsManager.resetToDefaults()
                hotkeyManager.resetToDefault()
            }
        } message: {
            Text("This will restore the default distraction sites, activation delay, and hotkey settings.")
        }
    }

    // MARK: - General Section

    private var generalSection: some View {
        @Bindable var launchManager = launchAtLoginManager

        return VStack(alignment: .leading, spacing: 8) {
            Text("General")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack {
                Toggle("Enable Monitoring", isOn: $appState.isEnabled)
                    .toggleStyle(.switch)

                Spacer()
            }

            HStack {
                Toggle("Open at Login", isOn: $launchManager.isEnabled)
                    .toggleStyle(.switch)

                Spacer()
            }

            if launchAtLoginManager.requiresSystemSettings {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Approval required")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Button("Open Settings") {
                        launchAtLoginManager.openSystemSettings()
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            } else {
                Text(launchAtLoginManager.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Hotkey Section

    private var hotkeySection: some View {
        @Bindable var hotkey = hotkeyManager

        return VStack(alignment: .leading, spacing: 8) {
            Text("Keyboard Shortcut")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("Toggle grayscale instantly with a keyboard shortcut")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Toggle("Enable Hotkey", isOn: $hotkey.isHotkeyEnabled)
                    .toggleStyle(.switch)

                Spacer()
            }

            if hotkeyManager.isHotkeyEnabled {
                HStack {
                    Text("Shortcut:")
                        .foregroundColor(.secondary)

                    HotkeyRecorderButton(
                        shortcut: $hotkey.currentShortcut,
                        isRecording: $isRecordingHotkey
                    )

                    Spacer()

                    Button("Reset") {
                        hotkeyManager.resetToDefault()
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            }
        }
    }

    // MARK: - Delay Section

    private var isInstantActivation: Bool {
        settingsManager.activationDelay == 0
    }

    private var delaySection: some View {
        @Bindable var settings = settingsManager

        return VStack(alignment: .leading, spacing: 8) {
            Text("Activation Delay")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("How quickly grayscale activates on distraction")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("", selection: Binding(
                get: { isInstantActivation },
                set: { instant in
                    if instant {
                        settingsManager.activationDelay = 0
                    } else {
                        settingsManager.activationDelay = max(settingsManager.activationDelay, 5)
                    }
                }
            )) {
                Text("Instant").tag(true)
                Text("Delayed").tag(false)
            }
            .pickerStyle(.segmented)

            if !isInstantActivation {
                HStack {
                    TextField(
                        "Seconds",
                        value: $settings.activationDelay,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.center)

                    Text("seconds (1-120)")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Domains Section

    private var domainsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Distraction Sites")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("Grayscale will activate when you visit these domains")
                .font(.caption)
                .foregroundColor(.secondary)

            // Add new domain
            HStack {
                TextField("Add domain (e.g. youtube.com)", text: $newDomain)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addDomain()
                    }

                Button {
                    addDomain()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }

            // Domain list
            if settingsManager.distractionDomains.isEmpty {
                Text("No distraction sites configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 4) {
                    ForEach(settingsManager.distractionDomains, id: \.self) { domain in
                        HStack {
                            Text(domain)
                                .font(.system(.caption, design: .monospaced))

                            Spacer()

                            Button {
                                withAnimation {
                                    settingsManager.removeDomain(domain)
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }

    // MARK: - Debug Section

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Debug & Testing")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 8) {
                Button("Test Grayscale (5s)") {
                    displayController.testGrayscale(duration: 5.0)
                }
                .disabled(!permissionManager.hasAccessibilityPermission)

                Button("Test URL Grab") {
                    appMonitor.testURLGrabbing()
                }
                .disabled(!permissionManager.hasAnyBrowserAutomationPermission)
            }

            if !permissionManager.hasAccessibilityPermission {
                Button("Grant Accessibility Permission") {
                    permissionManager.requestAccessibilityPermission()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

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

    // MARK: - Actions

    private func addDomain() {
        let domain = newDomain.trimmingCharacters(in: .whitespaces)
        guard !domain.isEmpty else { return }

        withAnimation {
            settingsManager.addDomain(domain)
        }
        newDomain = ""
    }
}

// MARK: - Hotkey Recorder Button

struct HotkeyRecorderButton: View {
    @Binding var shortcut: KeyboardShortcut
    @Binding var isRecording: Bool

    var body: some View {
        ZStack {
            // Hidden key capture view when recording
            if isRecording {
                KeyCaptureView { keyCode, modifiers in
                    // Require at least one modifier for global hotkeys
                    if modifiers != 0 {
                        shortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
                        isRecording = false
                    }
                }
                .frame(width: 0, height: 0)
            }

            Button {
                isRecording.toggle()
            } label: {
                HStack(spacing: 4) {
                    if isRecording {
                        Text("Press keys...")
                            .foregroundColor(.accentColor)
                    } else {
                        Text(shortcut.displayString)
                            .fontWeight(.medium)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Key Capture View (NSViewRepresentable)

struct KeyCaptureView: NSViewRepresentable {
    let onKeyPress: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyPress = onKeyPress

        // Make the view first responder after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            view.window?.makeFirstResponder(view)
        }

        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKeyPress = onKeyPress
    }
}

class KeyCaptureNSView: NSView {
    var onKeyPress: ((UInt32, UInt32) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        let modifiers = carbonModifiers(from: event.modifierFlags)

        // Only trigger if we have at least one modifier
        if modifiers != 0 {
            onKeyPress?(keyCode, modifiers)
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonMods: UInt32 = 0
        if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonMods |= UInt32(optionKey) }
        if flags.contains(.control) { carbonMods |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        return carbonMods
    }
}
