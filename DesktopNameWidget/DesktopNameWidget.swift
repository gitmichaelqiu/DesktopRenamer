import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configuration Intent
struct DesktopWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Widget Settings"
    static var description: LocalizedStringResource = "Customize the widget appearance."

    @Parameter(title: "Transparent Background", default: false)
    var isTransparent: Bool
}

// MARK: - Timeline Entry
struct DesktopNameEntry: TimelineEntry {
    let date: Date
    let spaceName: String
    let spaceNumber: Int
    let isDesktop: Bool
    let isTransparent: Bool
}

// MARK: - Provider
struct DesktopNameProvider: AppIntentTimelineProvider {
    let appGroupIdentifier = "group.com.michaelqiu.DesktopRenamer"

    func placeholder(in context: Context) -> DesktopNameEntry {
        DesktopNameEntry(date: Date(), spaceName: "Desktop 1", spaceNumber: 1, isDesktop: true, isTransparent: false)
    }

    func snapshot(for configuration: DesktopWidgetConfigurationIntent, in context: Context) async -> DesktopNameEntry {
        getCurrentEntry(for: configuration)
    }

    func timeline(for configuration: DesktopWidgetConfigurationIntent, in context: Context) async -> Timeline<DesktopNameEntry> {
        let entry = getCurrentEntry(for: configuration)
        return Timeline(entries: [entry], policy: .never)
    }
    
    private func getCurrentEntry(for configuration: DesktopWidgetConfigurationIntent) -> DesktopNameEntry {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        let name = defaults?.string(forKey: "widget_spaceName") ?? "Work"
        let num = defaults?.integer(forKey: "widget_spaceNum") ?? 1
        let isDesktop = (defaults?.object(forKey: "widget_isDesktop") as? Bool) ?? true
        
        return DesktopNameEntry(
            date: Date(),
            spaceName: name,
            spaceNumber: num,
            isDesktop: isDesktop,
            isTransparent: configuration.isTransparent
        )
    }
}

// MARK: - Entry View
struct DesktopNameWidgetEntryView: View {
    var entry: DesktopNameProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Space Indicator Label
            Text(entry.isDesktop ? (entry.spaceNumber > 0 ? "SPACE \(entry.spaceNumber)" : "FULLSCREEN") : "FULLSCREEN")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(entry.isTransparent ? AnyView(Color.black.opacity(0.2)) : AnyView(Color.primary.opacity(0.1)))
                .clipShape(Capsule())
            
            Spacer()

            // Large Aesthetic Name
            Text(entry.spaceName)
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.bold)
                .minimumScaleFactor(0.4)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
        .padding(16)
        // This solves the "adopt containerBackground API" warning
        .containerBackground(for: .widget) {
            if entry.isTransparent {
                Color.clear
            } else {
                Color(NSColor.windowBackgroundColor)
            }
        }
    }
}

// MARK: - Widget
@main
struct DesktopNameWidget: Widget {
    let kind: String = "DesktopNameWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: DesktopWidgetConfigurationIntent.self, provider: DesktopNameProvider()) { entry in
            DesktopNameWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Current Desktop")
        .description("Shows the name of the currently active desktop.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
