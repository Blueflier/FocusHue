# FocusHue

macOS menu bar app that turns the screen grayscale when you visit distracting websites. Built with SwiftUI, uses Accessibility API for display control and AppleScript for browser URL detection.

## Architecture

```
App/FocusHueApp.swift    — App entry, AppState container, AppDelegate, DistractionCoordinator
Core/
  SettingsManager.swift   — UserDefaults-backed settings (domains, delay, analytics toggle)
  AppMonitor.swift        — Polls active app + browser URL via NSWorkspace + AppleScript
  DisplayController.swift — Grayscale control via Accessibility API (CGDisplaySetFormulaForChannel)
  UsageTracker.swift      — Usage analytics engine (session tracking, compact JSON storage)
  HotkeyManager.swift     — Global hotkey registration via Carbon
  PermissionManager.swift — Accessibility + Automation permission checks
  LaunchAtLoginManager.swift — SMAppService login item
UI/
  MenuBarView.swift       — Menu bar popover
  SettingsView.swift      — Settings panel
  UsageView.swift         — Usage report window
  OnboardingView.swift    — First-launch onboarding
```

## Key Patterns

- **`@Observable`** on all state classes, injected via `.environment()` in SwiftUI
- **`AppState`** owns all managers, wires them together in `init()`, runs a 100ms polling loop in `startObserving()` for distraction detection + analytics
- **No Combine** — polling loop uses `Task` with `Task.sleep` instead

## Usage Analytics (`UsageTracker.swift`)

Opt-in feature (`SettingsManager.isAnalyticsEnabled`). Records app/site usage to daily JSON files.

### How it works
- `AppState`'s 100ms polling loop detects app/URL changes and calls `usageTracker.handleAppChange()`
- Sessions are buffered in memory (`pendingSessions`) and flushed to disk every 60 seconds
- Sleep/wake observers end sessions on sleep, resume tracking on wake
- Terminate observer flushes pending sessions on quit

### Disk format & consolidation
Data stored in `~/Library/Application Support/FocusHue/analytics/`.

**Structure:**
```
analytics/
  apps.json                   — Global registry
  YYYY-MM-DD.json             — Today's raw data
  daily/YYYY-MM-DD.agg.json   — Consolidated daily files
  weekly/YYYY-WNN.agg.json    — Weekly aggregates
  monthly/YYYY-MM.agg.json    — Monthly aggregates
```

**Global registry (`apps.json`):**
- `apps`: abbreviation → [appName, bundleId] (e.g. `"gc"` → `["Google Chrome", "com.google.Chrome"]`)
- `hosts`: abbreviation → hostname (e.g. `"cc"` → `"code.claude.com"`)
- Auto-generated abbreviations: multi-word → initials, single word → first 2 chars

**Raw daily files (`YYYY-MM-DD.json`):**
```json
{"b":803,"m":{"0":[["gh"],["gc",2,"cc"]],"3":[["xc"]]}}
```
- `b`: base minute (minutes since midnight)
- `m`: dict of minute offset → array of sessions (greyscale mode)
- `mon`: dict of minute offset → array of sessions (normal mode)
- Each session is a JSON array: `[appAbbrev]`, `[appAbbrev, endDelta]`, or `[appAbbrev, endDelta, hostAbbrev]`
- `endDelta`: minutes past the bucket's minute when session ended (0 omitted if no host)

**Aggregated files (`.agg.json`):**
```json
{
  "type": "daily",
  "date": "2026-02-12",
  "apps": {"gc": {"g": 3600, "n": 1200}},
  "sites": {"x": {"g": 1800, "n": 600}},
  "total": {"g": 10800, "n": 1800}
}
```
- `g`: greyscale seconds, `n`: normal seconds
- Created on app launch by consolidating yesterday's raw data
- Raw files deleted after consolidation

**Consolidation schedule:**
- Raw files kept for 7 days for viewing historical data
- Files 7+ days old consolidated to daily/.agg.json on app launch
- Weekly/monthly aggregation: framework in place (not auto-triggered yet)

### URL handling
- Only `http`/`https` URLs recorded (filters out `chrome://`, `chrome-extension://`, etc.)
- Stored as host only (no path/query)
- Localhost ports mapped to display names via `SettingsManager.localhostDisplayNames` (default: `18789` → `"OpenClaw"`)
