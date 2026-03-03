//
//  UsageView.swift
//  FocusHue
//
//  Displays daily usage analytics — per-app and per-site time breakdowns
//

import SwiftUI
import Charts

struct UsageView: View {
    let usageTracker: UsageTracker
    @Environment(SettingsManager.self) private var settingsManager

    @State private var selectedDate = Date()
    @State private var metrics: DailyMetrics?
    @State private var hourlyData: [HourlyUsage] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header with date picker
            HStack {
                Button {
                    changeDate(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBack)

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
                .disabled(!canGoForward)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let metrics {
                        // Total time header
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formattedDateHeader)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(formattedDuration(metrics.totalTrackedTime))
                                .font(.system(size: 36, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

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
                                .frame(height: 120)
                                .padding(.horizontal)
                            }
                        }

                        Divider()
                            .padding(.vertical, 8)

                        // Most Used Apps
                        VStack(alignment: .leading, spacing: 12) {
                            Text("MOST USED")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)

                            let topApps = filteredAppMetrics(metrics.appMetrics).prefix(10)
                            if topApps.isEmpty {
                                Text("No app usage data")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 20)
                            } else {
                                ForEach(Array(topApps)) { app in
                                    AppRow(app: app, maxDuration: topApps.first?.totalDuration ?? 1)
                                }
                            }
                        }

                        // Distraction Sites
                        let distractionSites = filteredDistractionSites(metrics.siteMetrics)
                        if !distractionSites.isEmpty {
                            Divider()
                                .padding(.vertical, 8)

                            VStack(alignment: .leading, spacing: 12) {
                                Text("DISTRACTION SITES")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)

                                ForEach(distractionSites.prefix(10)) { site in
                                    SiteRow(site: site, maxDuration: distractionSites.first?.totalDuration ?? 1)
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No data available")
                                .font(.headline)
                            Text("Usage data will appear here once tracking begins")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                }
                .padding(.vertical)
            }
        }
        .frame(width: 500, height: 550)
        .onAppear {
            loadData()
        }
    }

    // MARK: - Date Navigation

    private var canGoBack: Bool {
        // Can go back if there's data older than 7 days ago
        true
    }

    private var canGoForward: Bool {
        Calendar.current.isDateInToday(selectedDate) == false
    }

    private func changeDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            selectedDate = newDate
        }
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

    // MARK: - Data Loading

    private func loadData() {
        metrics = usageTracker.calculateMetrics(for: selectedDate)
        hourlyData = usageTracker.calculateHourlyBreakdown(for: selectedDate)
    }

    // MARK: - Helpers

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
        if hour == 0 {
            return "12A"
        } else if hour < 12 {
            return "\(hour)A"
        } else if hour == 12 {
            return "12P"
        } else {
            return "\(hour - 12)P"
        }
    }
}

// MARK: - App Row (Apple-style horizontal bar)

struct AppRow: View {
    let app: AppMetric
    let maxDuration: TimeInterval

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(app.name)
                    .font(.callout)
                Spacer()
                Text(formattedDuration(app.totalDuration))
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            // Horizontal bar
            GeometryReader { geo in
                HStack(spacing: 0) {
                    // Greyscale portion
                    if app.greyscaleDuration > 0 {
                        Rectangle()
                            .fill(Color.purple)
                            .frame(width: geo.size.width * (app.greyscaleDuration / maxDuration))
                    }
                    // Normal portion
                    if app.normalDuration > 0 {
                        Rectangle()
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: geo.size.width * (app.normalDuration / maxDuration))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 4)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(2)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
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
}

// MARK: - Site Row (similar to App Row)

struct SiteRow: View {
    let site: SiteMetric
    let maxDuration: TimeInterval

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(site.host)
                    .font(.callout)
                Spacer()
                Text(formattedDuration(site.totalDuration))
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            // Horizontal bar
            GeometryReader { geo in
                HStack(spacing: 0) {
                    // Greyscale portion
                    if site.greyscaleDuration > 0 {
                        Rectangle()
                            .fill(Color.purple)
                            .frame(width: geo.size.width * (site.greyscaleDuration / maxDuration))
                    }
                    // Normal portion
                    if site.normalDuration > 0 {
                        Rectangle()
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: geo.size.width * (site.normalDuration / maxDuration))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 4)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(2)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
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
}
