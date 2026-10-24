import AppKit
import Charts
import SwiftUI

enum SpaceAPIUsageRange: String, CaseIterable, Identifiable {
    case last24Hours
    case last7Days

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .last24Hours: "Last 24 hours"
        case .last7Days: "Last 7 days"
        }
    }

    var compactTitle: LocalizedStringKey {
        switch self {
        case .last24Hours: "24 hours"
        case .last7Days: "7 days"
        }
    }

    var chartDescription: LocalizedStringKey {
        switch self {
        case .last24Hours: "Requests per hour"
        case .last7Days: "Requests per day"
        }
    }
}

struct SpaceAPIUsageRangePicker: View {
    @Binding var selection: SpaceAPIUsageRange

    var body: some View {
        if #available(macOS 27.0, *) {
            picker
                .pickerStyle(.tabs)
                .controlSize(.large)
        } else if #available(macOS 26.0, *) {
            picker
                .pickerStyle(.segmented)
                .controlSize(.large)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    private var picker: some View {
        Picker("Activity Period", selection: $selection) {
            ForEach(SpaceAPIUsageRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .labelsHidden()
    }
}

private enum SpaceAPIUsageRequestType: String, CaseIterable, Identifiable {
    case read
    case write
    case unclassified

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .read: "Read"
        case .write: "Write"
        case .unclassified: "Unclassified"
        }
    }

    var localizedTitle: String {
        switch self {
        case .read: String(localized: "Read")
        case .write: String(localized: "Write")
        case .unclassified: String(localized: "Unclassified")
        }
    }

    var color: Color {
        switch self {
        case .read: .blue
        case .write: .orange
        case .unclassified: .gray
        }
    }

    func requestCount(in bucket: SpaceAPIUsageStatistics.ActivityBucket) -> Int {
        switch self {
        case .read: bucket.readRequestCount
        case .write: bucket.writeRequestCount
        case .unclassified: bucket.unclassifiedRequestCount
        }
    }
}

struct SpaceAPIUsageReportView: View {
    let usage: SpaceAPIUsageStatistics.AppUsage
    @ObservedObject var usageStatistics: SpaceAPIUsageStatistics
    let onDone: () -> Void

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

    private var visibleRequestTypes: [SpaceAPIUsageRequestType] {
        SpaceAPIUsageRequestType.allCases.filter { type in
            type != .unclassified || activity.contains { $0.unclassifiedRequestCount > 0 }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Button(action: onDone) {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.plain)
                        .help("Back")

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

                    SpaceAPIUsageRangePicker(selection: $selectedRange)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(displayedRequestCount, format: .number)
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .monospacedDigit()

                        Text(currentUsage?.hasDetailedHistory == true ? "requests /" : "total requests")
                            .font(.headline)

                        if currentUsage?.hasDetailedHistory == true {
                            Text(selectedRange.compactTitle)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    if currentUsage?.hasDetailedHistory == true {
                        activityChart
                            .frame(height: 160)

                        if periodRequestCount == 0 {
                            Text("No requests in this period.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(visibleRequestTypes) { type in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(type.color)
                                    .frame(width: 7, height: 7)
                                Text(type.title)
                                Text("requests")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(activity.reduce(0) { $0 + type.requestCount(in: $1) }, format: .number)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
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
                        .frame(maxWidth: .infinity, minHeight: 120)
                    }

                    Divider()

                    HStack {
                        Text("Lifetime requests")
                        Spacer()
                        Text(currentUsage?.requestCount ?? 0, format: .number)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Last request")
                        Spacer()
                        Text((currentUsage?.lastUsed ?? usage.lastUsed).formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.trailing, 16)
                .padding(.vertical, 2)
            }

            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var activityChart: some View {
        Chart {
            ForEach(activity) { bucket in
                ForEach(visibleRequestTypes) { type in
                    BarMark(
                        x: .value("Time", bucket.date),
                        y: .value("Requests", type.requestCount(in: bucket))
                    )
                    .foregroundStyle(type.color)
                    .position(by: .value("Request Type", type.localizedTitle))
                }
            }
        }
        .chartXAxis {
            if selectedRange == .last24Hours {
                AxisMarks(values: .stride(by: .hour, count: 4)) {
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                }
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
