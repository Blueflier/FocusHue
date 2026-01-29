import Foundation
import ApplicationServices

@Observable
class PermissionManager {
    //this is during the onboarding phase to provide a way for the user to get help with onboarding
    var isAccessibilityGranted: Bool = false

    init() {
        checkAccessibilityPermission()
    }

    func checkAccessibilityPermission() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        isAccessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    // Poll for permission changes every 2 seconds when checking
    func startMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkAccessibilityPermission()
        }
    }
}
