# FocusHue

## Product Requirements Document

*Context-Aware Display Manager for Digital Well-Being*

**Version 1.0 | January 2026**

---

## 1. Executive Summary

FocusHue is a macOS Menu Bar utility designed for digital well-being. It monitors the frontmost application and active browser URLs to determine if the user is in a productive or distracting context. When a user navigates to a pre-defined distracting URL or app, the system triggers a visual intervention (grayscale filter or dimming overlay) to reduce the dopamine response of the content.

**Target Platform:** macOS 14 (Sonoma) and later

**Distribution:** Direct download (notarized, outside App Store)

**Development Timeline:** 6 sprints, 2 weeks each (12 weeks total)

---

## 2. Technical Risk Assessment

Before development begins, the team must understand the key technical constraints that shaped this architecture.

| Risk | Description | Severity |
|------|-------------|----------|
| System Grayscale API | No public API exists to toggle macOS system grayscale. Must use private `CGDisplaySetForceToGray()` or overlay-based approach. | 🔴 High |
| Firefox Support | Firefox is not scriptable via AppleScript. Would require a separate browser extension. | 🟡 Medium |
| Scripting Bridge Latency | URL extraction from browsers takes 50-200ms, causing visible delay before overlay appears. | 🟡 Medium |
| Accessibility Deep-Link | Cannot reliably deep-link to Accessibility pane in System Settings on macOS Ventura+. | 🟢 Low |

### 2.1 Architectural Decisions

Based on the risk assessment, the following decisions have been made:

| Decision | Rationale |
|----------|-----------|
| Use `CGDisplaySetForceToGray()` for grayscale | Only reliable method for true system-wide grayscale. Private API but stable across recent macOS versions. Falls back to dimming overlay if it fails. |
| Exclude Firefox from initial release | Would require building and maintaining a separate WebExtension. Can be added in v2 if demand exists. |
| Speculative overlay pattern | Apply overlay immediately on browser focus, then remove if URL is non-distracting. Better UX than delayed application. |
| Manual navigation to Accessibility settings | Provide clear instructions in onboarding rather than relying on brittle deep-links. |

---

## 3. Sprint Plans

---

### Sprint 1: Foundation (Weeks 1-2)

**Goal:** Establish project structure, build permissions infrastructure, and validate core technical assumptions.

#### Deliverables

| Task | Description | Estimate |
|------|-------------|----------|
| Project Setup | Create Xcode project configured as menu bar app, disable sandbox, enable hardened runtime | 4h |
| Entitlements Configuration | Configure entitlements for Apple Events automation, create Info.plist with usage descriptions | 2h |
| Permission Manager | Implement `AXIsProcessTrustedWithOptions()` check and prompt, create permission status observable | 4h |
| Onboarding UI | Build SwiftUI onboarding flow showing permission status with grant buttons and manual instructions | 6h |
| Menu Bar Shell | Create NSStatusItem with basic popover showing enable/disable toggle and settings access | 4h |
| Grayscale Proof of Concept | Test `CGDisplaySetForceToGray()` on target macOS versions, document behavior | 4h |

#### Acceptance Criteria

1. App launches as menu bar icon with no dock presence
2. Clicking menu bar icon shows popover with toggle switch
3. App correctly detects whether Accessibility permission is granted
4. Clicking "Grant" button triggers macOS permission dialog
5. Manual test: `CGDisplaySetForceToGray(true)` turns screen grayscale
6. Manual test: `CGDisplaySetForceToGray(false)` restores color

#### Test Plan

| Test | Method | Pass Criteria |
|------|--------|---------------|
| Menu bar presence | Manual | Icon visible in menu bar, no dock icon |
| Permission detection (denied) | Manual - revoke permission first | UI shows "Not Granted" status |
| Permission detection (granted) | Manual - grant permission | UI shows "Granted" status within 2 seconds |
| Permission prompt | Manual - click Grant when denied | macOS Accessibility prompt appears |
| Grayscale toggle on | Manual - call API directly | Entire display becomes grayscale |
| Grayscale toggle off | Manual - call API directly | Display returns to full color |

---

### Sprint 2: App Switching Detection (Weeks 3-4)

**Goal:** Detect application focus changes and retrieve basic app information.

#### Deliverables

| Task | Description | Estimate |
|------|-------------|----------|
| Focus Observer | Implement `NSWorkspace.didActivateApplicationNotification` listener | 4h |
| App Context Model | Create data model for app context: bundle ID, name, window title | 2h |
| Context Publisher | Expose current context as `@Published` property for UI binding | 2h |
| Debug View | Build debug panel in popover showing real-time app switch events with timestamps | 4h |
| App Blocklist Storage | Implement UserDefaults storage for list of distracting app bundle IDs | 3h |
| App Blocklist UI | Create settings view to add/remove apps from blocklist with app picker | 6h |
| Basic Trigger Logic | When app in blocklist activates, log to debug view (no overlay yet) | 3h |

#### Acceptance Criteria

1. Debug view shows app name and bundle ID when switching between apps
2. App switches are detected within 100ms (verify via timestamps)
3. Can add app to blocklist via settings UI
4. Can remove app from blocklist via settings UI
5. Blocklist persists after app restart
6. Debug view shows "BLOCKED" indicator when switching to blocklisted app

#### Test Plan

| Test | Method | Pass Criteria |
|------|--------|---------------|
| App switch detection | Manual - switch between apps | Each switch logged with correct bundle ID |
| Detection latency | Manual - observe timestamps | Time between switch and log < 100ms |
| Add to blocklist | Manual - use settings UI | App appears in blocklist |
| Remove from blocklist | Manual - use settings UI | App removed from blocklist |
| Persistence | Manual - restart app | Blocklist unchanged after restart |
| Blocked app detection | Manual - switch to blocked app | "BLOCKED" appears in debug view |

---

### Sprint 3: Browser URL Extraction (Weeks 5-6)

**Goal:** Extract active tab URLs from Safari and Chrome using Scripting Bridge.

#### Deliverables

| Task | Description | Estimate |
|------|-------------|----------|
| Generate Safari Headers | Run sdef/sdp to create Safari.h, add to bridging header | 2h |
| Generate Chrome Headers | Run sdef/sdp to create GoogleChrome.h, add to bridging header | 2h |
| URL Fetcher - Safari | Implement `getSafariURL()` using Scripting Bridge | 4h |
| URL Fetcher - Chrome | Implement `getChromeURL()` using Scripting Bridge | 4h |
| URL Blocklist Storage | Implement UserDefaults storage for URL patterns (domain-based) | 3h |
| URL Blocklist UI | Create settings view to add/remove URL patterns | 4h |
| Pattern Matcher | Implement domain matching logic (e.g., "youtube.com" matches any YouTube URL) | 3h |
| Async URL Fetch | Integrate URL fetching into Focus Observer on background thread | 4h |
| Debug View Update | Show extracted URL and match status in debug panel | 2h |

#### Acceptance Criteria

1. When Safari is frontmost, debug view shows current tab URL
2. When Chrome is frontmost, debug view shows current tab URL
3. URL extraction completes within 300ms of app switch
4. Can add URL pattern to blocklist (e.g., "youtube.com")
5. Pattern "youtube.com" matches "https://www.youtube.com/watch?v=xyz"
6. Debug view shows "URL BLOCKED" when on blocklisted site
7. Switching tabs within browser triggers new URL check

#### Test Plan

| Test | Method | Pass Criteria |
|------|--------|---------------|
| Safari URL extraction | Manual - open Safari, various sites | Correct URL shown in debug view |
| Chrome URL extraction | Manual - open Chrome, various sites | Correct URL shown in debug view |
| Extraction latency | Manual - observe timestamps | URL appears < 300ms after switch |
| Pattern matching - exact | Manual - add "youtube.com", visit YouTube | Shows as blocked |
| Pattern matching - subdomain | Manual - visit music.youtube.com | Shows as blocked |
| Pattern matching - negative | Manual - visit youtubekids.com | Shows as NOT blocked (different domain) |
| Tab switch detection | Manual - switch tabs in browser | URL updates for new tab |

---

### Sprint 4: Display Intervention (Weeks 7-8)

**Goal:** Implement grayscale and dimming overlays that activate based on context.

#### Deliverables

| Task | Description | Estimate |
|------|-------------|----------|
| Grayscale Controller | Wrap `CGDisplaySetForceToGray()` with enable/disable methods and error handling | 4h |
| Dimming Overlay Window | Create NSWindow-based overlay with configurable opacity | 4h |
| Multi-Display Support | Ensure overlay covers all connected displays | 3h |
| Intervention Manager | Orchestrate grayscale vs dimming based on user preference | 4h |
| Settings - Mode Selection | Add UI to choose between grayscale, dimming, or both | 3h |
| Settings - Dimming Level | Add slider for dimming intensity (0-100%) | 2h |
| Speculative Application | Apply overlay immediately on browser focus, remove if URL is safe | 6h |
| Edge Case Handling | Handle rapid app switching, ensure overlay removed when app disabled | 4h |

#### Acceptance Criteria

1. Switching to blocklisted app triggers grayscale within 50ms
2. Switching away from blocklisted app restores color within 50ms
3. Dimming overlay covers entire screen including menu bar
4. Dimming overlay does not intercept mouse clicks
5. Can adjust dimming level via slider, effect updates in real-time
6. With external monitor connected, both displays affected
7. Rapidly switching apps 10 times does not leave overlay stuck
8. Disabling FocusHue via menu bar removes overlay within 50ms

#### Test Plan

| Test | Method | Pass Criteria |
|------|--------|---------------|
| Grayscale activation | Manual - switch to blocked app | Screen goes grayscale |
| Grayscale deactivation | Manual - switch to safe app | Color restores |
| Dimming activation | Manual - enable dimming mode | Overlay appears at set opacity |
| Click-through | Manual - click while dimmed | Clicks pass through to underlying window |
| Multi-display | Manual - connect external monitor | Both screens affected |
| Rapid switching | Manual - alt-tab rapidly | No stuck overlays |
| Master disable | Manual - toggle off in menu | Overlay removed, stays off |

---

### Sprint 5: Polish and Tab Monitoring (Weeks 9-10)

**Goal:** Add tab change detection, refine UX, and prepare for distribution.

#### Deliverables

| Task | Description | Estimate |
|------|-------------|----------|
| Tab Change Polling | Poll browser URL every 500ms when browser is frontmost | 4h |
| Intelligent Polling | Only poll when browser is active, stop when other app focused | 3h |
| Transition Animation | Add subtle fade for dimming overlay (100ms ease) | 3h |
| Status Indicator | Show small colored dot on menu bar icon when intervention active | 2h |
| Quick Toggle Shortcut | Add global keyboard shortcut to enable/disable (configurable) | 4h |
| Whitelist Mode | Add option to invert logic: only allow specific sites, block everything else | 4h |
| Default Blocklist | Pre-populate with common distracting sites (youtube, twitter, reddit, etc.) | 2h |
| First Launch Experience | Show onboarding on first launch, skip on subsequent launches | 3h |
| Error Handling | Add user-facing alerts for permission issues, API failures | 4h |

#### Acceptance Criteria

1. Switching tabs in Safari triggers URL recheck within 600ms
2. Switching tabs in Chrome triggers URL recheck within 600ms
3. No polling occurs when non-browser app is focused (verify via logs)
4. Menu bar icon shows red dot when grayscale/dimming is active
5. Pressing configured shortcut toggles FocusHue on/off
6. Fresh install shows onboarding, subsequent launches go straight to menu bar
7. If Accessibility permission revoked, user sees clear error with instructions

#### Test Plan

| Test | Method | Pass Criteria |
|------|--------|---------------|
| Tab switch - Safari | Manual - switch tabs | Overlay updates for new tab content |
| Tab switch - Chrome | Manual - switch tabs | Overlay updates for new tab content |
| Polling stops | Manual - switch to Finder, check logs | No URL fetch attempts logged |
| Status indicator | Manual - trigger intervention | Red dot appears on icon |
| Keyboard shortcut | Manual - press shortcut | FocusHue toggles |
| First launch | Manual - delete preferences, launch | Onboarding appears |
| Permission revoked | Manual - revoke in System Settings | Error alert shown |

---

### Sprint 6: Distribution (Weeks 11-12)

**Goal:** Sign, notarize, and distribute the app. Create documentation and landing page.

#### Deliverables

| Task | Description | Estimate |
|------|-------------|----------|
| Developer ID Certificate | Obtain or verify Developer ID Application certificate from Apple | 2h |
| Build Script | Create shell script for archive, export, and notarization pipeline | 4h |
| Notarization Testing | Submit test builds, resolve any notarization issues | 6h |
| DMG Creation | Create branded DMG with background image and Applications symlink | 4h |
| Landing Page | Create simple website with download link, screenshots, feature list | 6h |
| README | Write comprehensive README with installation, usage, troubleshooting | 3h |
| Privacy Policy | Draft privacy policy (app collects no data, runs locally) | 2h |
| GitHub Repository | Set up public repo with releases, issues enabled | 2h |
| Final QA | Complete test pass on fresh macOS install | 6h |

#### Acceptance Criteria

1. DMG opens showing app icon and Applications folder
2. Dragging app to Applications installs successfully
3. App launches without Gatekeeper warning on fresh Mac
4. `spctl --assess --verbose FocusHue.app` returns "accepted"
5. Landing page loads, download link works
6. README covers installation, first launch, adding blocklist items
7. Full feature test pass completes with no critical bugs

#### Test Plan

| Test | Method | Pass Criteria |
|------|--------|---------------|
| Notarization status | CLI - `xcrun stapler validate` | Returns "valid on disk" |
| Gatekeeper | Manual - download from web, open | No warning dialog |
| Fresh install flow | Manual - new user account | Onboarding to working state |
| All features | Manual - full regression | No critical or major bugs |
| Landing page | Manual - visit URL | Page loads, download works |
| Documentation | Manual - follow README steps | Successfully install and configure |

---

## 4. Technical Specifications

### 4.1 System Requirements

| Requirement | Specification |
|-------------|---------------|
| Operating System | macOS 14.0 (Sonoma) or later |
| Architecture | Universal Binary (Apple Silicon + Intel) |
| Disk Space | < 10 MB |
| Memory | < 50 MB typical usage |
| Permissions Required | Accessibility (required), Automation for Safari/Chrome (prompted on first use) |

### 4.2 Supported Browsers

| Browser | Support Level | Notes |
|---------|---------------|-------|
| Safari | Full | Native Scripting Bridge support |
| Google Chrome | Full | Native Scripting Bridge support |
| Microsoft Edge | Full | Uses Chrome scripting interface |
| Brave | Full | Uses Chrome scripting interface |
| Arc | Full | Uses Chrome scripting interface |
| Firefox | Not Supported | Requires separate extension (future consideration) |

### 4.3 Key APIs and Frameworks

| Component | API/Framework | Purpose |
|-----------|---------------|---------|
| App Switching | `NSWorkspace.didActivateApplicationNotification` | Detect when user changes focus |
| URL Extraction | Scripting Bridge (Safari.h, GoogleChrome.h) | Read active tab URL from browsers |
| Grayscale | `CGDisplaySetForceToGray()` [Private] | System-wide grayscale toggle |
| Dimming | `NSWindow`, `NSPanel` | Overlay window with configurable opacity |
| Permissions | `AXIsProcessTrustedWithOptions()` | Check and request Accessibility access |
| Settings Storage | `UserDefaults` | Persist blocklists and preferences |
| Distribution | `notarytool`, `stapler` | Sign and notarize for Gatekeeper |

---

## 5. Risk Mitigations

### 5.1 Private API Risk

`CGDisplaySetForceToGray()` is a private API. While it has been stable across macOS versions, Apple could remove or change it.

**Mitigation:** The app includes a fallback dimming overlay mode. If grayscale fails (detected via try/catch or runtime check), the app automatically switches to dimming mode and logs a warning. Users can also manually select dimming mode in preferences.

### 5.2 Browser Update Risk

Browser updates could change Scripting Bridge interfaces or remove scriptability.

**Mitigation:** URL extraction is wrapped in error handling. If Scripting Bridge calls fail, the app logs the error and treats the browser as "unknown context" (no intervention applied). Users are notified via the debug panel if a browser becomes unsupported.

### 5.3 Performance Risk

Continuous polling and overlay management could impact system performance.

**Mitigation:** Polling only occurs when a browser is frontmost. Polling interval (500ms) is configurable. Memory and CPU usage are monitored during QA with target limits (< 50MB RAM, < 1% CPU idle).

---

## 6. Out of Scope (v1)

The following features are explicitly excluded from version 1.0 and may be considered for future releases:

| Feature | Reason for Exclusion |
|---------|---------------------|
| Firefox support | Requires building and maintaining a separate WebExtension |
| iOS/iPadOS version | Different platform, different APIs, different distribution |
| Time-based scheduling | Adds complexity; users can toggle manually for now |
| Usage statistics/tracking | Privacy concerns; keeping v1 simple and local-only |
| Window-specific overlays | Technical complexity of tracking individual windows across spaces |
| App Store distribution | Requires sandbox, which prevents core functionality |

---

## 7. Appendix

### 7.1 Default URL Blocklist

The following domains are pre-populated in the blocklist. Users can modify this list.

| Domain | Category |
|--------|----------|
| youtube.com | Video |
| twitter.com | Social Media |
| x.com | Social Media |
| reddit.com | Social Media |
| facebook.com | Social Media |
| instagram.com | Social Media |
| tiktok.com | Social Media |
| twitch.tv | Streaming |
| netflix.com | Streaming |
| hulu.com | Streaming |

### 7.2 Build Commands Reference

**Archive:**
```bash
xcodebuild -project FocusHue.xcodeproj \
           -scheme FocusHue \
           -configuration Release \
           archive \
           -archivePath build/FocusHue.xcarchive
```

**Export:**
```bash
xcodebuild -exportArchive \
           -archivePath build/FocusHue.xcarchive \
           -exportPath build/export \
           -exportOptionsPlist ExportOptions.plist
```

**Notarize:**
```bash
xcrun notarytool submit build/FocusHue.zip \
                        --apple-id YOUR_EMAIL \
                        --team-id YOUR_TEAM_ID \
                        --password YOUR_APP_SPECIFIC_PASSWORD \
                        --wait
```

**Staple:**
```bash
xcrun stapler staple build/export/FocusHue.app
```

**Create DMG:**
```bash
hdiutil create -volname "FocusHue" \
               -srcfolder "build/export/FocusHue.app" \
               -ov -format UDZO \
               "build/FocusHue.dmg"
```

### 7.3 ExportOptions.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
</dict>
</plist>
```

### 7.4 Entitlements File

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    <key>com.apple.security.hardened-runtime</key>
    <true/>
</dict>
</plist>
```
