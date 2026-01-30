//
//  SettingsView.swift
//  FocusHue
//
//  Settings panel for configuring distraction domains, activation delay, hotkey, and launch at login
//

import SwiftUI
import Carbon

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(HotkeyManager.self) private var hotkeyManager
    @Environment(LaunchAtLoginManager.self) private var launchAtLoginManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var newDomain: String = ""
    @State private var showingResetConfirmation = false
    @State private var isRecordingHotkey = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
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
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 380, height: 550)
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
    
    private var delaySection: some View {
        @Bindable var settings = settingsManager
        
        return VStack(alignment: .leading, spacing: 8) {
            Text("Activation Delay")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text("Seconds before grayscale activates (1-120)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                TextField(
                    "Seconds",
                    value: $settings.activationDelay,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .multilineTextAlignment(.center)
                
                Text("seconds")
                    .foregroundColor(.secondary)
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
        .focusable()
        .onKeyPress { keyPress in
            guard isRecording else { return .ignored }
            
            // Get the key code from the key press
            if let keyCode = keyCodeFromKeyEquivalent(keyPress.key) {
                let carbonMods = carbonModifiersFromEventModifiers(keyPress.modifiers)
                
                // Require at least one modifier for global hotkeys
                if carbonMods != 0 {
                    shortcut = KeyboardShortcut(keyCode: keyCode, modifiers: carbonMods)
                    isRecording = false
                    return .handled
                }
            }
            
            return .ignored
        }
    }
    
    /// Convert SwiftUI EventModifiers to Carbon modifier flags
    private func carbonModifiersFromEventModifiers(_ modifiers: SwiftUI.EventModifiers) -> UInt32 {
        var carbonMods: UInt32 = 0
        if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbonMods |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        return carbonMods
    }
    
    /// Convert KeyEquivalent to Carbon key code
    private func keyCodeFromKeyEquivalent(_ key: KeyEquivalent) -> UInt32? {
        // Map common keys to Carbon key codes
        let char = key.character
        let keyMap: [Character: UInt32] = [
            "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C),
            "d": UInt32(kVK_ANSI_D), "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F),
            "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H), "i": UInt32(kVK_ANSI_I),
            "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
            "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O),
            "p": UInt32(kVK_ANSI_P), "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R),
            "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T), "u": UInt32(kVK_ANSI_U),
            "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
            "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
            "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
            "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
            "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
            "9": UInt32(kVK_ANSI_9),
            " ": UInt32(kVK_Space),
        ]
        return keyMap[char]
    }
}
