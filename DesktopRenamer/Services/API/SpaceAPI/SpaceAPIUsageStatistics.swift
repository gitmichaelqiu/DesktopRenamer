import Combine
import Foundation

@MainActor
final class SpaceAPIUsageStatistics: ObservableObject {
    struct HourlyUsage: Codable, Equatable, Identifiable {
        let hourStart: Date
        var requestCount: Int

        var id: Date { hourStart }
    }

    struct ActivityBucket: Equatable, Identifiable {
        let date: Date
        let requestCount: Int

        var id: Date { date }
    }

    struct AppUsage: Codable, Equatable, Identifiable {
        let id: String
        var name: String
        var applicationPath: String
        var requestCount: Int
        var lastUsed: Date
        var hourlyUsage: [HourlyUsage]
        var hasDetailedHistory: Bool

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case applicationPath
            case requestCount
            case lastUsed
            case hourlyUsage
            case hasDetailedHistory
        }

        init(
            id: String,
            name: String,
            applicationPath: String,
            requestCount: Int,
            lastUsed: Date,
            hourlyUsage: [HourlyUsage],
            hasDetailedHistory: Bool
        ) {
            self.id = id
            self.name = name
            self.applicationPath = applicationPath
            self.requestCount = requestCount
            self.lastUsed = lastUsed
            self.hourlyUsage = hourlyUsage
            self.hasDetailedHistory = hasDetailedHistory
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            name = try values.decode(String.self, forKey: .name)
            applicationPath = try values.decode(String.self, forKey: .applicationPath)
            requestCount = try values.decode(Int.self, forKey: .requestCount)
            lastUsed = try values.decode(Date.self, forKey: .lastUsed)
            hourlyUsage = try values.decodeIfPresent([HourlyUsage].self, forKey: .hourlyUsage) ?? []
            hasDetailedHistory = try values.decodeIfPresent(Bool.self, forKey: .hasDetailedHistory) ?? false
        }
    }

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    @Published private(set) var appUsages: [AppUsage] = []

    private let defaults: UserDefaults
    private static let enabledKey = "SpaceAPIUsageStatisticsEnabled"
    private static let historyKey = "SpaceAPIUsageStatisticsHistory"
    private static let maximumTrackedApps = 100
    private static let historyRetentionInterval: TimeInterval = 7 * 24 * 60 * 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)

        if let data = defaults.data(forKey: Self.historyKey),
           let history = try? JSONDecoder().decode([AppUsage].self, from: data) {
            let cutoff = Date().addingTimeInterval(-Self.historyRetentionInterval)
            appUsages = history.map { usage in
                var usage = usage
                usage.hourlyUsage.removeAll { $0.hourStart < cutoff }
                return usage
            }
            if appUsages != history {
                persistHistory()
            }
        }
    }

    func record(requestingApplication application: SpaceAPIApprovedClient) {
        guard isEnabled else { return }
        let now = Date()
        let calendar = Calendar.current
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let cutoff = now.addingTimeInterval(-Self.historyRetentionInterval)

        for index in appUsages.indices {
            appUsages[index].hourlyUsage.removeAll { $0.hourStart < cutoff }
        }

        if let index = appUsages.firstIndex(where: { $0.id == application.id }) {
            var usage = appUsages[index]
            usage.name = application.name
            usage.applicationPath = application.applicationPath
            usage.requestCount += 1
            usage.lastUsed = now
            usage.hasDetailedHistory = true
            if let bucketIndex = usage.hourlyUsage.firstIndex(where: { $0.hourStart == hourStart }) {
                usage.hourlyUsage[bucketIndex].requestCount += 1
            } else {
                usage.hourlyUsage.append(HourlyUsage(hourStart: hourStart, requestCount: 1))
            }
            appUsages[index] = usage
        } else {
            appUsages.append(AppUsage(
                id: application.id,
                name: application.name,
                applicationPath: application.applicationPath,
                requestCount: 1,
                lastUsed: now,
                hourlyUsage: [HourlyUsage(hourStart: hourStart, requestCount: 1)],
                hasDetailedHistory: true
            ))
        }

        appUsages.sort { $0.lastUsed > $1.lastUsed }
        if appUsages.count > Self.maximumTrackedApps {
            appUsages.removeLast(appUsages.count - Self.maximumTrackedApps)
        }
        persistHistory()
    }

    func clearHistory() {
        appUsages.removeAll()
        defaults.removeObject(forKey: Self.historyKey)
    }

    func hourlyActivity(for applicationID: String, endingAt now: Date = Date()) -> [ActivityBucket] {
        let calendar = Calendar.current
        guard let currentHour = calendar.dateInterval(of: .hour, for: now)?.start else { return [] }
        let usage = appUsages.first { $0.id == applicationID }
        let hourlyCounts = usage?.hourlyUsage.reduce(into: [Date: Int]()) { counts, bucket in
            counts[bucket.hourStart, default: 0] += bucket.requestCount
        } ?? [:]

        return (-23...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .hour, value: offset, to: currentHour) else { return nil }
            return ActivityBucket(date: date, requestCount: hourlyCounts[date, default: 0])
        }
    }

    func dailyActivity(for applicationID: String, endingAt now: Date = Date()) -> [ActivityBucket] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let usage = appUsages.first { $0.id == applicationID }
        let dailyCounts = usage?.hourlyUsage.reduce(into: [Date: Int]()) { counts, bucket in
            let day = calendar.startOfDay(for: bucket.hourStart)
            counts[day, default: 0] += bucket.requestCount
        } ?? [:]

        return (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return ActivityBucket(date: date, requestCount: dailyCounts[date, default: 0])
        }
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(appUsages) else { return }
        defaults.set(data, forKey: Self.historyKey)
    }
}
