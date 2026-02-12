//
//  UsageView.swift
//  FocusHue
//
//  Displays daily usage analytics — per-app and per-site time breakdowns
//

import SwiftUI

struct UsageView: View {
    let usageTracker: UsageTracker

    @State private var selectedDate = Date()
    @State private var metrics: DailyMetrics?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()

                Button("Calculate") {
                    metrics = usageTracker.calculateMetrics(for: selectedDate)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            if let metrics {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Total time
                        HStack {
                            Text("Total Tracked Time")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(formattedDuration(metrics.totalTrackedTime))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.accentColor)
                        }

                        Divider()

                        // Per-app breakdown
                        Text("Apps")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if metrics.appMetrics.isEmpty {
                            Text("No app data for this date")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(metrics.appMetrics) { app in
                                HStack {
                                    Text(app.name)
                                        .font(.caption)
                                    Spacer()
                                    Text(formattedDuration(app.duration))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Divider()

                        // Per-site breakdown
                        Text("Sites")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if metrics.siteMetrics.isEmpty {
                            Text("No site data for this date")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(metrics.siteMetrics) { site in
                                HStack {
                                    Text(site.host)
                                        .font(.system(.caption, design: .monospaced))
                                    Spacer()
                                    Text(formattedDuration(site.duration))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                }
            } else {
                Spacer()
                Text("Select a date and press Calculate")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .frame(width: 380, height: 450)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60

        if h > 0 {
            return "\(h)h \(m)m"
        } else if m > 0 {
            return "\(m)m \(s)s"
        } else {
            return "\(s)s"
        }
    }
}
