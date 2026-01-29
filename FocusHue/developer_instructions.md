```markdown
# Grayscale Screen Filter for Distraction Blocking - MVP Spec

## Product Intent
A macOS app that progressively turns the screen grayscale when the user switches from productive applications (like iTerm/terminal) to distracting websites (specifically Twitter/X in Chrome). The gradual desaturation acts as a behavioral nudge to reduce time spent on distracting content.

## Core Functionality

### 1. Application Monitoring
- Detect which application is currently active/in focus
- Specifically track when Chrome browser becomes active
- Identify when user switches from iTerm (or other terminal apps) to Chrome

**Keywords for Documentation:**
- `NSWorkspace.shared.frontmostApplication`
- macOS Accessibility API
- Screen Recording permissions
- Active window detection

### 2. Tab/Website Detection
- Monitor active Chrome tab
- Detect when Twitter/X (twitter.com or x.com) is the active tab

**Keywords for Documentation:**
- Chrome tab monitoring
- Browser extension communication (if needed)
- URL detection from active window
- AppleScript for Chrome tab queries

### 3. Grayscale Control
- Programmatically enable/disable macOS grayscale color filter
- Gradually increase grayscale intensity (progressive desaturation)
- Return to full color when switching back to productive apps

**Keywords for Documentation:**
- `com.apple.universalaccess` preferences
- `colorFiltersEnabled` plist key
- `colorFiltersType` plist key (value: 0 for grayscale)
- `UserDefaults` with suite name
- `killall universalaccessd` to apply changes
- `NSAppleScript` for sudo execution

### 4. Menu Bar Interface
- App runs as menu bar utility (NSStatusItem)
- Icon in menu bar showing current state
- Dropdown menu with controls

**Menu Bar Requirements:**
- Icon: Shows grayscale state (e.g., colored icon = normal, gray icon = grayscale active)
- Menu items:
  - "Test Grayscale" button - manually trigger grayscale for testing
  - Current status indicator (e.g., "Monitoring: Active" or "Grayscale: 45%")
  - "Quit" option

**Keywords for Documentation:**
- `NSStatusBar.system.statusBar`
- `NSStatusItem`
- `NSMenu` and `NSMenuItem`
- Menu bar app configuration
- `LSUIElement` (hide from Dock, show only in menu bar)
- SF Symbols for menu bar icons
- Asset catalog for menu bar icons

### 5. Permission Handling
- Request Accessibility permissions (for app monitoring)
- Handle sudo/administrator privileges (for restarting accessibility daemon)
- One-time setup script for passwordless sudo

**Keywords for Documentation:**
- macOS Accessibility permissions
- `SMAppService` for privilege escalation
- Sudoers file modification
- `/etc/sudoers.d/` directory

## Technical Implementation Path

### Phase 1: Menu Bar App Setup
```swift
// Create menu bar item
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Grayscale Monitor")

// Create menu
let menu = NSMenu()
menu.addItem(NSMenuItem(title: "Test Grayscale", action: #selector(testGrayscale), keyEquivalent: "t"))
menu.addItem(NSMenuItem.separator())
menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
statusItem.menu = menu
```

### Phase 2: Core Grayscale Toggle
```swift
// Write to preferences
UserDefaults(suiteName: "com.apple.universalaccess")?.set(true, forKey: "colorFiltersEnabled")
UserDefaults(suiteName: "com.apple.universalaccess")?.set(0, forKey: "colorFiltersType")

// Apply changes immediately
NSAppleScript(source: "do shell script \"killall universalaccessd\" with administrator privileges")
```

### Phase 3: Test Button Implementation
```swift
@objc func testGrayscale() {
    isTestMode = true
    enableGrayscale()
    
    // Auto-disable after 5 seconds
    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
        if self.isTestMode {
            self.disableGrayscale()
            self.isTestMode = false
        }
    }
}
```

### Phase 4: Application Detection
```swift
// Monitor active application
NSWorkspace.shared.frontmostApplication

// Accessibility API for window title/URL detection
```

### Phase 5: Gradual Transition
- Timer-based progressive grayscale increase
- Interpolate between full color (0% gray) and full grayscale (100% gray) over time
- Reverse animation when switching away
- Update menu bar icon to reflect current grayscale percentage

### Phase 6: Setup Script
```bash
#!/bin/bash
# One-time setup for passwordless accessibility daemon restart
echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/killall universalaccessd" | sudo tee -a /etc/sudoers.d/grayscale-blocker
```

## Menu Bar UI Components

### Status Icon States
1. **Normal (Full Color)**: Default icon, monitoring but no grayscale active
2. **Grayscale Active**: Gray/desaturated version of icon or different symbol
3. **Test Mode**: Distinct indicator showing manual test is running

### Menu Structure
```
[Icon in menu bar]
├── Test Grayscale (⌘T)
├── ────────────────
├── Status: Monitoring Chrome
├── Current App: iTerm
├── Grayscale: 0%
├── ────────────────
├── Preferences... (future)
├── ────────────────
└── Quit (⌘Q)
```

## Distribution Method
- GitHub repository
- Users clone/download and compile locally
- Run setup script once with sudo
- Launch app (appears only in menu bar, not Dock)

## User Experience Flow
1. User downloads from GitHub
2. Runs `setup.sh` with sudo (one-time password prompt)
3. Launches app (icon appears in menu bar)
4. User can click "Test Grayscale" to verify it works
5. App monitors active application in background
6. When user switches to Chrome with Twitter/X open:
   - Screen slowly desaturates over ~10-30 seconds
   - Menu bar icon updates to gray
   - Menu shows grayscale percentage increasing
7. When user switches back to iTerm or closes Twitter tab:
   - Screen returns to full color
   - Menu bar icon returns to normal

## Key Documentation Resources to Review
- **macOS Accessibility API**: Application and window monitoring
- **NSWorkspace**: Active application detection
- **NSStatusBar/NSStatusItem**: Menu bar app implementation
- **NSMenu/NSMenuItem**: Menu bar dropdown interface
- **LSUIElement in Info.plist**: Hide app from Dock
- **UserDefaults/plist manipulation**: System preference modification
- **Process/NSAppleScript**: Running shell commands with privileges
- **Sudoers configuration**: Passwordless sudo setup
- **Chrome AppleScript**: Tab URL detection (if needed)
- **Timer/Animation**: Gradual transition implementation
- **SF Symbols**: System icons for menu bar

## MVP Constraints
- Requires sudo (acceptable for GitHub distribution)
- macOS only
- Targets Chrome browser specifically
- Twitter/X domain detection only (expandable later)
- Manual compilation from source
- Menu bar app only (no dock presence)
```
