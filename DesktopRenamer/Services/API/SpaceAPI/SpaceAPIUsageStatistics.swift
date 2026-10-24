import Combine
import Foundation

@MainActor
final class SpaceAPIUsageStatistics: ObservableObject {
    struct AppUsage: Codable, Equatable, Identifiable {
        let id: String
        var name: String
        var applicationPath: String
        var requestCount: Int
        var lastUsed: Date
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)

        if let data = defaults.data(forKey: Self.historyKey),
           let history = try? JSONDecoder().decode([AppUsage].self, from: data) {
            appUsages = history
        }
    }

    func record(requestingApplication application: SpaceAPIApprovedClient) {
        guard isEnabled else { return }

        if let index = appUsages.firstIndex(where: { $0.id == application.id }) {
            appUsages[index].name = application.name
            appUsages[index].applicationPath = application.applicationPath
            appUsages[index].requestCount += 1
            appUsages[index].lastUsed = Date()
        } else {
            appUsages.append(AppUsage(
                id: application.id,
                name: application.name,
                applicationPath: application.applicationPath,
                requestCount: 1,
                lastUsed: Date()
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

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(appUsages) else { return }
        defaults.set(data, forKey: Self.historyKey)
    }
}
