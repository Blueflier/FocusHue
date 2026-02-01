//
//  HotkeyManager.swift
//  FocusHue
//
//  Manages global keyboard shortcuts using Carbon Event APIs
//

import Foundation
import Carbon
import AppKit

/// Represents a keyboard shortcut with modifiers and key code
struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32  // Carbon modifier flags
    
    /// Human-readable display string for the shortcut
    var displayString: String {
        var parts: [String] = []
        
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        
        if let keyString = keyCodeToString(keyCode) {
            parts.append(keyString)
        }
        
        return parts.joined()
    }
    
    /// Default shortcut: ⌘⇧U (Command + Shift + U)
    static let defaultShortcut = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_U),
        modifiers: UInt32(cmdKey | shiftKey)
    )
}

/// Convert a key code to a human-readable string
private func keyCodeToString(_ keyCode: UInt32) -> String? {
    let keyCodeMap: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩",
        UInt32(kVK_Tab): "⇥", UInt32(kVK_Escape): "⎋",
        UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
    ]
    return keyCodeMap[keyCode]
}

/// Convert NSEvent modifier flags to Carbon modifier flags
func carbonModifiers(from nsModifiers: NSEvent.ModifierFlags) -> UInt32 {
    var carbonMods: UInt32 = 0
    if nsModifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
    if nsModifiers.contains(.option) { carbonMods |= UInt32(optionKey) }
    if nsModifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
    if nsModifiers.contains(.shift) { carbonMods |= UInt32(shiftKey) }
    return carbonMods
}

// MARK: - Hotkey Manager

@Observable
final class HotkeyManager {
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private static let hotkeyID = EventHotKeyID(signature: OSType(0x464855), id: 1) // "FHU" + 1
    
    var isHotkeyEnabled: Bool = false {
        didSet {
            if isHotkeyEnabled {
                registerHotkey()
            } else {
                unregisterHotkey()
            }
            saveSettings()
        }
    }
    
    var currentShortcut: KeyboardShortcut = .defaultShortcut {
        didSet {
            if isHotkeyEnabled {
                // Re-register with new shortcut
                unregisterHotkey()
                registerHotkey()
            }
            saveSettings()
        }
    }
    
    /// Callback triggered when hotkey is pressed
    var onHotkeyPressed: (() -> Void)?
    
    // UserDefaults keys
    private let enabledKey = "hotkeyEnabled"
    private let shortcutKey = "hotkeyShortcut"
    
    init() {
        loadSettings()
        setupEventHandler()
        
        if isHotkeyEnabled {
            registerHotkey()
        }
    }
    
    deinit {
        unregisterHotkey()
        removeEventHandler()
    }
    
    // MARK: - Settings Persistence
    
    private func loadSettings() {
        isHotkeyEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        
        if let data = UserDefaults.standard.data(forKey: shortcutKey),
           let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) {
            currentShortcut = shortcut
        }
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(isHotkeyEnabled, forKey: enabledKey)
        
        if let data = try? JSONEncoder().encode(currentShortcut) {
            UserDefaults.standard.set(data, forKey: shortcutKey)
        }
    }
    
    // MARK: - Event Handler Setup
    
    private func setupEventHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            
            var hotkeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotkeyID
            )
            
            // Check if this is our hotkey
            if hotkeyID.signature == HotkeyManager.hotkeyID.signature &&
               hotkeyID.id == HotkeyManager.hotkeyID.id {
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.onHotkeyPressed?()
                }
            }
            
            return noErr
        }
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }
    
    private func removeEventHandler() {
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
    
    // MARK: - Hotkey Registration
    
    private func registerHotkey() {
        guard hotkeyRef == nil else { return }
        
        var hotkeyID = Self.hotkeyID
        
        let status = RegisterEventHotKey(
            currentShortcut.keyCode,
            currentShortcut.modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        
        if status != noErr {
            print("Failed to register hotkey: \(status)")
        }
    }
    
    private func unregisterHotkey() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
    }
    
    /// Reset hotkey to default
    func resetToDefault() {
        currentShortcut = .defaultShortcut
    }
}
