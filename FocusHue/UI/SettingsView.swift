//
//  SettingsView.swift
//  FocusHue
//
//  Settings panel with tabs for General, Distractions, Analytics, and Debug
//

import SwiftUI
import Carbon
import AppKit
import Charts

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(HotkeyManager.self) private var hotkeyManager
    @Environment(LaunchAtLoginManager.self) private var launchAtLoginManager
    @Environment(DisplayController.self) private var displayController
    @Environment(AppMonitor.self) private var appMonitor
    @Environment(PermissionManager.self) private var permissionManager

    @Bindable var appState: AppState

    @Environment(\.openWindow) private var openWindow

    @State private var newDomain: String = ""
    @State private var newApp: String = ""
    @State private var showingResetConfirmation = false
    @State private var isRecordingHotkey = false
    @State private var showingDeleteDataConfirmation = false
    @State private var selectedTab = 0
    @State private var selectedRunningApp: RunningAppInfo?
    @State private var newLocalhostPort: String = ""
    @State private var newLocalhostName: String = ""

    struct RunningAppInfo: Identifiable, Hashable {
        let id: String  // bundle ID
        let name: String
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                analyticsTab
                    .tabItem { Label("Analytics", systemImage: "chart.bar") }
                    .tag(0)

                generalTab
                    .tabItem { Label("Options", systemImage: "gear") }
                    .tag(1)

                distractionsTab
                    .tabItem { Label("Setup", systemImage: "slider.horizontal.3") }
                    .tag(2)

                debugTab
                    .tabItem { Label("Debug", systemImage: "wrench") }
                    .tag(3)
            }
            .padding(.top, 8)

            Divider()

            // Footer
            HStack {
                // Show Reset button only on non-Analytics tabs
                if selectedTab != 0 {
                    Button("Reset to Defaults") {
                        showingResetConfirmation = true
                    }
                    .foregroundColor(.red)
                }

                Spacer()

                Button("Done") {
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 450, height: 550)
        .alert("Reset Settings?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                settingsManager.resetToDefaults()
                hotkeyManager.resetToDefault()
            }
        } message: {
            Text("This will restore default settings.")
        }
    }

    // MARK: - Options Tab

    private var generalTab: some View {
        @Bindable var launchManager = launchAtLoginManager
        @Bindable var settings = settingsManager
        @Bindable var hotkey = hotkeyManager

        return ScrollView {
            VStack(spacing: 20) {
                // Monitoring Section
                GroupBox {
                    VStack(spacing: 16) {
                        // Mode Picker
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Mode", systemImage: "eye")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(settings.monitoringMode == .greyscale
                                     ? "Grayscale activates when visiting distraction sites"
                                     : "Tracks usage without changing screen appearance")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Picker("", selection: $settings.monitoringMode) {
                                Text("Greyscale Mode").tag(MonitoringMode.greyscale)
                                Text("Normal").tag(MonitoringMode.normal)
                            }
                            .pickerStyle(.segmented)
                        }

                        Divider()

                        // Toggle Switches
                        VStack(spacing: 12) {
                            Toggle(isOn: $appState.isEnabled) {
                                HStack {
                                    Image(systemName: appState.isEnabled ? "power.circle.fill" : "power.circle")
                                        .foregroundColor(appState.isEnabled ? .green : .secondary)
                                    Text("Enable Monitoring")
                                        .font(.subheadline)
                                }
                            }
                            .toggleStyle(.switch)

                            Toggle(isOn: $launchManager.isEnabled) {
                                HStack {
                                    Image(systemName: "arrow.clockwise.circle")
                                        .foregroundColor(.secondary)
                                    Text("Open at Login")
                                        .font(.subheadline)
                                }
                            }
                            .toggleStyle(.switch)

                            if launchAtLoginManager.requiresSystemSettings {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Text("System approval required")
                                        .font(.caption)
                                        .foregroundColor(.orange)

                                    Spacer()

                                    Button("Open Settings") {
                                        launchAtLoginManager.openSystemSettings()
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                .padding(8)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                    }
                    .padding(4)
                }

                // Activation Delay Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Activation Delay", systemImage: "timer")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("How quickly grayscale activates on distraction")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Picker("", selection: Binding(
                            get: { settings.activationDelay == 0 },
                            set: { instant in
                                if instant {
                                    settings.activationDelay = 0
                                } else {
                                    settings.activationDelay = max(settings.activationDelay, 5)
                                }
                            }
                        )) {
                            Text("Instant").tag(true)
                            Text("Delayed").tag(false)
                        }
                        .pickerStyle(.segmented)

                        if settings.activationDelay > 0 {
                            HStack(spacing: 8) {
                                TextField(
                                    "Seconds",
                                    value: $settings.activationDelay,
                                    format: .number
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .multilineTextAlignment(.center)

                                Text("seconds")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Text("1-120 seconds")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(4)
                }

                // Keyboard Shortcut Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Keyboard Shortcut", systemImage: "command")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("Toggle grayscale instantly with a hotkey")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Toggle("Enable", isOn: $hotkey.isHotkeyEnabled)
                                .toggleStyle(.switch)
                                .frame(width: 120)

                            if hotkeyManager.isHotkeyEnabled {
                                Spacer()

                                HotkeyRecorderButton(
                                    shortcut: $hotkey.currentShortcut,
                                    isRecording: $isRecordingHotkey
                                )

                                Button("Reset") {
                                    hotkeyManager.resetToDefault()
                                }
                                .font(.caption)
                                .buttonStyle(.borderless)
                                .foregroundColor(.blue)
                            }
                        }
                    }
                    .padding(4)
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Distractions Tab

    private var distractionsTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Distraction Sites
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Distraction Sites", systemImage: "safari")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("Grayscale activates when visiting these domains")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Add new domain
                        HStack {
                            TextField("youtube.com", text: $newDomain)
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

                        // Domain list (collapsible)
                        if !settingsManager.distractionDomains.isEmpty {
                            DisclosureGroup("\(settingsManager.distractionDomains.count) domains configured") {
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
                                        .padding(.vertical, 4)
                                    }
                                }
                                .padding(.top, 4)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(4)
                }

                // Distraction Apps
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Distraction Apps", systemImage: "app.badge")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("Grayscale activates when using these apps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Add from running apps dropdown
                        HStack {
                            Picker("Select running app", selection: $selectedRunningApp) {
                                Text("Select a running app...").tag(nil as RunningAppInfo?)
                                ForEach(getRunningApps()) { app in
                                    Text(app.name).tag(app as RunningAppInfo?)
                                }
                            }
                            .frame(maxWidth: .infinity)

                            Button("Add") {
                                if let app = selectedRunningApp {
                                    withAnimation {
                                        settingsManager.addApp(app.id)
                                        selectedRunningApp = nil
                                    }
                                }
                            }
                            .disabled(selectedRunningApp == nil)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        // Manual entry
                        HStack {
                            TextField("Or enter bundle ID", text: $newApp)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    addApp()
                                }

                            Button {
                                addApp()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .disabled(newApp.trimmingCharacters(in: .whitespaces).isEmpty)
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }

                        // App list (collapsible)
                        if !settingsManager.distractionApps.isEmpty {
                            DisclosureGroup("\(settingsManager.distractionApps.count) apps configured") {
                                VStack(spacing: 4) {
                                    ForEach(settingsManager.distractionApps, id: \.self) { bundleId in
                                        HStack {
                                            Text(bundleId)
                                                .font(.system(.caption, design: .monospaced))

                                            Spacer()

                                            Button {
                                                withAnimation {
                                                    settingsManager.removeApp(bundleId)
                                                }
                                            } label: {
                                                Image(systemName: "minus.circle.fill")
                                                    .foregroundColor(.red)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                    }
                                }
                                .padding(.top, 4)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(4)
                }

                // Localhost Display Names
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Localhost Mappings", systemImage: "network")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("localhost:18789 → OpenClaw")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Add new mapping
                        HStack {
                            TextField("18789", text: $newLocalhostPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)

                            TextField("(e.g. OpenClaw)", text: $newLocalhostName)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                addLocalhostMapping()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .disabled(newLocalhostPort.trimmingCharacters(in: .whitespaces).isEmpty ||
                                      newLocalhostName.trimmingCharacters(in: .whitespaces).isEmpty)
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }

                        // Mapping list (collapsible)
                        if !settingsManager.localhostDisplayNames.isEmpty {
                            DisclosureGroup("\(settingsManager.localhostDisplayNames.count) mappings configured") {
                                VStack(spacing: 4) {
                                    ForEach(Array(settingsManager.localhostDisplayNames.keys.sorted()), id: \.self) { port in
                                        HStack {
                                            Text(":\(port)")
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            Image(systemName: "arrow.right")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text(settingsManager.localhostDisplayNames[port] ?? "")
                                                .font(.system(.caption, design: .monospaced))

                                            Spacer()

                                            Button {
                                                withAnimation {
                                                    settingsManager.removeLocalhostDisplayName(port: port)
                                                }
                                            } label: {
                                                Image(systemName: "minus.circle.fill")
                                                    .foregroundColor(.red)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                    }
                                }
                                .padding(.top, 4)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(4)
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Analytics Tab

    private var analyticsTab: some View {
        @Bindable var settings = settingsManager

        return VStack(spacing: 0) {
            if settingsManager.isAnalyticsEnabled {
                // Embedded usage report
                InlineUsageView(
                    usageTracker: appState.usageTracker,
                    showingDeleteConfirmation: $showingDeleteDataConfirmation
                )
            } else {
                // Analytics disabled state
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("Analytics Disabled")
                        .font(.headline)

                    Text("Enable analytics to track app and website usage")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Picker("", selection: $settings.isAnalyticsEnabled) {
                        Text("Off").tag(false)
                        Text("On").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)

                    Spacer()
                }
                .padding()
            }
        }
        .alert("Delete All Analytics Data?", isPresented: $showingDeleteDataConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                appState.usageTracker.deleteAllData()
            }
        } message: {
            Text("This will permanently remove all recorded usage data. This cannot be undone.")
        }
    }

    // MARK: - Debug Tab

    private var debugTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Test Actions
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("Test Grayscale (5s)") {
                            displayController.testGrayscale(duration: 5.0)
                        }
                        .disabled(!permissionManager.hasAccessibilityPermission)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        if !permissionManager.hasAccessibilityPermission {
                            Button("Grant Accessibility Permission") {
                                permissionManager.requestAccessibilityPermission()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                // Current State
                GroupBox {
                    VStack(spacing: 8) {
                        HStack {
                            Text("App:")
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Text(appMonitor.currentAppName.isEmpty ? "-" : appMonitor.currentAppName)
                            Spacer()
                        }

                        HStack {
                            Text("Bundle ID:")
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Text(appMonitor.currentAppBundleId.isEmpty ? "-" : appMonitor.currentAppBundleId)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }

                        HStack {
                            Text("URL:")
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Text(appMonitor.currentURL.isEmpty ? "-" : truncatedURL)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }

                        HStack {
                            Text("Distracting:")
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Text(appMonitor.isOnDistractingSite ? "Yes" : "No")
                                .foregroundColor(appMonitor.isOnDistractingSite ? .red : .green)
                            Spacer()
                        }

                        HStack {
                            Text("Grayscale:")
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Text(displayController.isGrayscaleEnabled ? "On" : "Off")
                            Spacer()
                        }
                    }
                    .font(.caption)
                    .padding(4)
                }

                // Automation permission warning
                if !appMonitor.hasAutomationPermission || !permissionManager.hasAnyBrowserAutomationPermission {
                    automationWarningSection
                }

                Spacer()
            }
            .padding()
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

    private func addApp() {
        let bundleId = newApp.trimmingCharacters(in: .whitespaces)
        guard !bundleId.isEmpty else { return }

        withAnimation {
            settingsManager.addApp(bundleId)
        }
        newApp = ""
    }

    private func getRunningApps() -> [RunningAppInfo] {
        var seenBundleIds = Set<String>()
        var apps: [RunningAppInfo] = []

        for app in NSWorkspace.shared.runningApplications {
            // Filter out system apps and apps without bundle IDs
            guard let bundleId = app.bundleIdentifier,
                  let appName = app.localizedName,
                  !bundleId.isEmpty,
                  !settingsManager.distractionApps.contains(bundleId),
                  !seenBundleIds.contains(bundleId) else {
                continue
            }

            seenBundleIds.insert(bundleId)
            apps.append(RunningAppInfo(
                id: bundleId,
                name: appName
            ))
        }

        return apps.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func addLocalhostMapping() {
        let port = newLocalhostPort.trimmingCharacters(in: .whitespaces)
        let name = newLocalhostName.trimmingCharacters(in: .whitespaces)
        guard !port.isEmpty, !name.isEmpty else { return }

        withAnimation {
            settingsManager.setLocalhostDisplayName(port: port, name: name)
        }
        newLocalhostPort = ""
        newLocalhostName = ""
    }
}

// MARK: - Inline Usage View (embedded in Settings)

struct InlineUsageView: View {
    let usageTracker: UsageTracker
    @Binding var showingDeleteConfirmation: Bool
    @Environment(SettingsManager.self) private var settingsManager

    @State private var selectedDate = Date()
    @State private var metrics: DailyMetrics?
    @State private var hourlyData: [HourlyUsage] = []
    @State private var selectedView = 0  // 0=Day, 1=Week, 2=Month
    @State private var storageSize: String?
    @State private var showStorageInfo = false

    var body: some View {
        VStack(spacing: 0) {
            // View selector tabs
            Picker("", selection: $selectedView) {
                Text("Day").tag(0)
                Text("Week").tag(1)
                Text("Month").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .onChange(of: selectedView) { _, _ in
                loadData()
            }

            Divider()

            // Date navigation (only for Day view)
            if selectedView == 0 {
                HStack {
                    Button {
                        changeDate(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!canGoForward)

                    Spacer()

                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .onChange(of: selectedDate) { _, _ in
                            loadData()
                        }

                    Spacer()

                    Button {
                        changeDate(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!canGoBack)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if selectedView == 0 {
                        // DAY VIEW
                        dayView
                    } else if selectedView == 1 {
                        // WEEK VIEW
                        weekView
                    } else {
                        // MONTH VIEW
                        monthView
                    }

                    // Data Management Section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Data Management", systemImage: "folder")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                            }

                            if showStorageInfo {
                                HStack {
                                    Text("Storage:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(storageSize ?? "Calculating...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                            }

                            HStack(spacing: 12) {
                                if !showStorageInfo {
                                    Button("Show Storage Info") {
                                        storageSize = usageTracker.calculateStorageSize()
                                        showStorageInfo = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }

                                Button("View Raw Data") {
                                    usageTracker.openRawDataFile()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Spacer()

                                Button("Clear All Data") {
                                    showingDeleteConfirmation = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .foregroundColor(.red)
                            }
                        }
                        .padding(4)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            loadData()
        }
    }

    // MARK: - Day View

    @ViewBuilder
    private var dayView: some View {
        if let metrics {
            // Total time header
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDateHeader)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formattedDuration(metrics.totalTrackedTime))
                    .font(.system(size: 28, weight: .semibold))
                if metrics.activeModeTime > 0 {
                    Text("\(formattedDuration(metrics.activeModeTime)) in greyscale")
                        .font(.caption)
                        .foregroundColor(.purple)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Hourly bar chart
            if !hourlyData.isEmpty && hourlyData.contains(where: { $0.totalDuration > 0 }) {
                VStack(alignment: .leading, spacing: 8) {
                    Chart(hourlyData) { item in
                        BarMark(
                            x: .value("Hour", item.hour),
                            y: .value("Time", item.greyscaleDuration / 60)
                        )
                        .foregroundStyle(Color.purple)
                        .position(by: .value("Type", "Greyscale"))

                        BarMark(
                            x: .value("Hour", item.hour),
                            y: .value("Time", item.normalDuration / 60)
                        )
                        .foregroundStyle(Color.blue.opacity(0.6))
                        .position(by: .value("Type", "Normal"))
                    }
                    .chartXAxis {
                        AxisMarks(values: [0, 6, 12, 18]) { value in
                            if let hour = value.as(Int.self) {
                                AxisValueLabel {
                                    Text(formatHour(hour))
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine()
                        }
                    }
                    .frame(height: 100)
                }
            }

            Divider()
                .padding(.vertical, 8)

            // Most Used Apps
            VStack(alignment: .leading, spacing: 8) {
                Text("MOST USED")
                    .font(.caption)
                    .foregroundColor(.secondary)

                let topApps = filteredAppMetrics(metrics.appMetrics).prefix(5)
                if topApps.isEmpty {
                    Text("No app usage data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                } else {
                    ForEach(Array(topApps)) { app in
                        CompactAppRow(app: app, maxDuration: topApps.first?.totalDuration ?? 1)
                    }
                }
            }

            // Distraction Sites
            let distractionSites = filteredDistractionSites(metrics.siteMetrics)
            if !distractionSites.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("DISTRACTION SITES")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(distractionSites.prefix(5)) { site in
                        CompactSiteRow(site: site, maxDuration: distractionSites.first?.totalDuration ?? 1)
                    }
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text("No data available")
                    .font(.subheadline)
                Text("Usage data will appear here once tracking begins")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
    }

    // MARK: - Week View

    @ViewBuilder
    private var weekView: some View {
        let cal = Calendar.current
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart)!
        let weekData = usageTracker.calculateMultiDayMetrics(from: weekStart, to: weekEnd)

        if !weekData.isEmpty {
            let totalTime = weekData.reduce(0) { $0 + $1.metrics.totalTrackedTime }
            let greyscaleTime = weekData.reduce(0) { $0 + $1.metrics.activeModeTime }

            VStack(alignment: .leading, spacing: 4) {
                Text("This Week")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formattedDuration(totalTime))
                    .font(.system(size: 28, weight: .semibold))
                if greyscaleTime > 0 {
                    Text("\(formattedDuration(greyscaleTime)) in greyscale")
                        .font(.caption)
                        .foregroundColor(.purple)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Chart(weekData, id: \.date) { item in
                BarMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Time", item.metrics.totalTrackedTime / 3600)
                )
                .foregroundStyle(Color.purple.gradient)
            }
            .frame(height: 100)
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                }
            }

            Divider()
                .padding(.vertical, 8)

            let weekApps = aggregateApps(weekData)
            VStack(alignment: .leading, spacing: 8) {
                Text("TOP APPS THIS WEEK")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(weekApps.prefix(5)) { app in
                    CompactAppRow(app: app, maxDuration: weekApps.first?.totalDuration ?? 1)
                }
            }
        } else {
            Text("No data available for this week")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
        }
    }

    // MARK: - Month View

    @ViewBuilder
    private var monthView: some View {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        let monthEnd = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!
        let monthData = usageTracker.calculateMultiDayMetrics(from: monthStart, to: monthEnd)

        if !monthData.isEmpty {
            let totalTime = monthData.reduce(0) { $0 + $1.metrics.totalTrackedTime }

            VStack(alignment: .leading, spacing: 4) {
                Text("This Month")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formattedDuration(totalTime))
                    .font(.system(size: 28, weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Chart(monthData, id: \.date) { item in
                BarMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Time", item.metrics.totalTrackedTime / 3600)
                )
                .foregroundStyle(Color.purple.gradient)
            }
            .frame(height: 100)
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                }
            }

            Divider()
                .padding(.vertical, 8)

            let monthApps = aggregateApps(monthData)
            VStack(alignment: .leading, spacing: 8) {
                Text("TOP APPS THIS MONTH")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(monthApps.prefix(5)) { app in
                    CompactAppRow(app: app, maxDuration: monthApps.first?.totalDuration ?? 1)
                }
            }
        } else {
            Text("No data available for this month")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 40)
        }
    }

    // MARK: - Date Navigation

    private var canGoBack: Bool {
        Calendar.current.isDateInToday(selectedDate) == false
    }

    private var canGoForward: Bool {
        true
    }

    private func changeDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            selectedDate = newDate
        }
    }

    private func aggregateApps(_ data: [(date: Date, metrics: DailyMetrics)]) -> [AppMetric] {
        var appTotals: [String: (name: String, greyscale: TimeInterval, normal: TimeInterval)] = [:]

        for item in data {
            for app in item.metrics.appMetrics {
                let existing = appTotals[app.bundleId]
                appTotals[app.bundleId] = (
                    name: app.name,
                    greyscale: (existing?.greyscale ?? 0) + app.greyscaleDuration,
                    normal: (existing?.normal ?? 0) + app.normalDuration
                )
            }
        }

        return appTotals.map { bundleId, data in
            AppMetric(
                name: data.name,
                bundleId: bundleId,
                greyscaleDuration: data.greyscale,
                normalDuration: data.normal,
                isBrowser: false,
                siteBreakdown: nil
            )
        }
        .sorted { $0.totalDuration > $1.totalDuration }
    }

    private var formattedDateHeader: String {
        if Calendar.current.isDateInToday(selectedDate) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(selectedDate) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: selectedDate)
        }
    }

    private func loadData() {
        metrics = usageTracker.calculateMetrics(for: selectedDate)
        hourlyData = usageTracker.calculateHourlyBreakdown(for: selectedDate)
    }

    private func filteredAppMetrics(_ metrics: [AppMetric]) -> [AppMetric] {
        metrics.filter { $0.totalDuration >= 60 }
    }

    private func filteredDistractionSites(_ metrics: [SiteMetric]) -> [SiteMetric] {
        metrics.filter { site in
            site.totalDuration >= 60 && isDistractionSite(site.host)
        }
    }

    private func isDistractionSite(_ host: String) -> Bool {
        settingsManager.distractionDomains.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60

        if h > 0 {
            return "\(h)h \(m)m"
        } else if m > 0 {
            return "\(m)m"
        } else {
            return "0m"
        }
    }

    private func formatHour(_ hour: Int) -> String {
        if hour == 0 { return "12A" }
        else if hour < 12 { return "\(hour)A" }
        else if hour == 12 { return "12P" }
        else { return "\(hour - 12)P" }
    }
}

// Compact versions for settings panel
struct CompactAppRow: View {
    let app: AppMetric
    let maxDuration: TimeInterval

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(app.name)
                    .font(.caption)
                Spacer()
                Text(formattedDuration(app.totalDuration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            GeometryReader { geo in
                HStack(spacing: 0) {
                    if app.greyscaleDuration > 0 {
                        Rectangle()
                            .fill(Color.purple)
                            .frame(width: geo.size.width * (app.greyscaleDuration / maxDuration))
                    }
                    if app.normalDuration > 0 {
                        Rectangle()
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: geo.size.width * (app.normalDuration / maxDuration))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 3)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(1.5)
        }
        .padding(.vertical, 2)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        else if m > 0 { return "\(m)m" }
        else { return "0m" }
    }
}

struct CompactSiteRow: View {
    let site: SiteMetric
    let maxDuration: TimeInterval

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(site.host)
                    .font(.caption)
                Spacer()
                Text(formattedDuration(site.totalDuration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            GeometryReader { geo in
                HStack(spacing: 0) {
                    if site.greyscaleDuration > 0 {
                        Rectangle()
                            .fill(Color.purple)
                            .frame(width: geo.size.width * (site.greyscaleDuration / maxDuration))
                    }
                    if site.normalDuration > 0 {
                        Rectangle()
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: geo.size.width * (site.normalDuration / maxDuration))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 3)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(1.5)
        }
        .padding(.vertical, 2)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        else if m > 0 { return "\(m)m" }
        else { return "0m" }
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
