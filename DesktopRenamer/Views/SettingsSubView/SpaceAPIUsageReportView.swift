import AppKit
import Charts
import SwiftUI

enum SpaceAPIUsageRange: String, CaseIterable, Identifiable {
    case last24Hours
    case last7Days

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .last24Hours: "Last 24 Hours"
        case .last7Days: "Last 7 Days"
        }
    }

    var chartDescription: LocalizedStringKey {
        switch self {
        case .last24Hours: "Requests per hour"
        case .last7Days: "Requests per day"
        }
    }
}

struct SpaceAPIUsageReportView: View {
    let usage: SpaceAPIUsageStatistics.AppUsage
    @ObservedObject var usageStatistics: SpaceAPIUsageStatistics
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRange = SpaceAPIUsageRange.last7Days

    private var currentUsage: SpaceAPIUsageStatistics.AppUsage? {
        usageStatistics.appUsages.first { $0.id == usage.id }
    }

    private var activity: [SpaceAPIUsageStatistics.ActivityBucket] {
        switch selectedRange {
        case .last24Hours:
            usageStatistics.hourlyActivity(for: usage.id)
        case .last7Days:
            usageStatistics.dailyActivity(for: usage.id)
        }
    }

    private var periodRequestCount: Int {
        activity.reduce(0) { $0 + $1.requestCount }
    }

    private var displayedRequestCount: Int {
        currentUsage?.hasDetailedHistory == true ? periodRequestCount : currentUsage?.requestCount ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: usage.applicationPath))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text(usage.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            Picker("Activity Period", selection: $selectedRange) {
                ForEach(SpaceAPIUsageRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayedRequestCount, format: .number)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                VStack(alignment: .leading, spacing: 2) {
                    Text("Requests")
                        .font(.headline)
                    Text(currentUsage?.hasDetailedHistory == true ? selectedRange.title : "Total Requests")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if currentUsage?.hasDetailedHistory == true {
                activityChart
                    .frame(height: 190)

                if periodRequestCount == 0 {
                    Text("No requests in this period.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Detailed activity will appear after the next request.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            }

            Divider()

            HStack {
                Text("Total Requests")
                Spacer()
                Text(currentUsage?.requestCount ?? 0, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Last Request")
                Spacer()
                Text((currentUsage?.lastUsed ?? usage.lastUsed).formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500, height: 460)
    }

    private var activityChart: some View {
        Chart(activity) { bucket in
            BarMark(
                x: .value("Time", bucket.date),
                y: .value("Requests", bucket.requestCount)
            )
            .foregroundStyle(Color.accentColor.gradient)
        }
        .chartXAxis {
            if selectedRange == .last24Hours {
                AxisMarks(values: .stride(by: .hour, count: 4))
            } else {
                AxisMarks(values: .stride(by: .day))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .accessibilityLabel(selectedRange.chartDescription)
    }
}
