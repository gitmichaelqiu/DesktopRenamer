import WidgetKit
import SwiftUI
import AppIntents

// MARK: - 1. Configuration Enum
enum WidgetBackgroundStyle: String, AppEnum {
    case standard
    case transparent

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Background Style"

    static var caseDisplayRepresentations: [WidgetBackgroundStyle: DisplayRepresentation] = [
        .standard: "Standard (Adaptive)",
        .transparent: "Transparent"
    ]
}

// MARK: - 2. Widget Configuration Intent
struct DesktopWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Widget Settings"
    static var description: LocalizedStringResource = "Customize the background style of your desktop widget."

    @Parameter(title: "Background Style", default: .standard)
    var backgroundStyle: WidgetBackgroundStyle
}

// MARK: - 3. Timeline Entry
struct DesktopNameEntry: TimelineEntry {
    let date: Date
    let spaceName: String
    let spaceNumber: Int
    let isDesktop: Bool
    let allSpaceNames: [String]
    let backgroundStyle: WidgetBackgroundStyle
}

// MARK: - 4. Provider
struct DesktopNameProvider: AppIntentTimelineProvider {
    typealias Entry = DesktopNameEntry
    typealias Intent = DesktopWidgetIntent
    
    let appGroupIdentifier = "group.com.michaelqiu.DesktopRenamer"

    private func fetchSharedData(for configuration: DesktopWidgetIntent) -> DesktopNameEntry {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        let name = defaults?.string(forKey: "widget_spaceName") ?? "Desktop"
        let num = defaults?.integer(forKey: "widget_spaceNum") ?? 1
        let isDesktop = (defaults?.object(forKey: "widget_isDesktop") as? Bool) ?? true
        
        // Fetch existing list or create a fallback to prevent "Single Square" issue
        var allNames = defaults?.stringArray(forKey: "widget_allSpaces") ?? []
        
        // FIX: If the array is missing or empty, generate a fallback list
        // so the user sees multiple squares instead of just one.
        if allNames.isEmpty {
            let count = max(num, 4) // Ensure we show at least 4, or up to current space
            allNames = (1...count).map { "Desktop \($0)" }
            // Ensure current name matches the specific saved name
            if num > 0 && num <= allNames.count {
                allNames[num - 1] = name
            }
        }
        
        return DesktopNameEntry(
            date: Date(),
            spaceName: name,
            spaceNumber: num,
            isDesktop: isDesktop,
            allSpaceNames: allNames,
            backgroundStyle: configuration.backgroundStyle
        )
    }

    func placeholder(in context: Context) -> DesktopNameEntry {
        DesktopNameEntry(
            date: Date(),
            spaceName: "Work",
            spaceNumber: 2,
            isDesktop: true,
            allSpaceNames: ["Personal", "Work", "Dev", "Music"],
            backgroundStyle: .standard
        )
    }

    func snapshot(for configuration: DesktopWidgetIntent, in context: Context) async -> DesktopNameEntry {
        fetchSharedData(for: configuration)
    }

    func timeline(for configuration: DesktopWidgetIntent, in context: Context) async -> Timeline<DesktopNameEntry> {
        let entry = fetchSharedData(for: configuration)
        return Timeline(entries: [entry], policy: .never)
    }
}

// MARK: - 5. Dynamic Text View
struct AdaptiveText: View {
    let text: String
    let family: WidgetFamily
    
    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text)
                .font(.system(size: family == .systemSmall ? 34 : 48, weight: .bold, design: .rounded))
            Text(text)
                .font(.system(size: family == .systemSmall ? 26 : 36, weight: .bold, design: .rounded))
            Text(text)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
        }
        .lineLimit(1)
    }
}

// MARK: - 6. Entry View
struct DesktopNameWidgetEntryView: View {
    var entry: DesktopNameProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // MARK: Desktop Indicators
            HStack(spacing: 6) {
                if entry.isDesktop {
                    // Iterate using indices to ensure stability
                    ForEach(0..<entry.allSpaceNames.count, id: \.self) { index in
                        let name = entry.allSpaceNames[index]
                        let isCurrent = (index + 1) == entry.spaceNumber
                        
                        ZStack {
                            // Background Square
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isCurrent ? Color.primary : Color.primary.opacity(0.15))
                            
                            // Content: Number if current, Letter if not
                            Text(isCurrent ? "\(entry.spaceNumber)" : String(name.prefix(1)).uppercased())
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(isCurrent ? Color(nsColor: .windowBackgroundColor) : Color.primary.opacity(0.7))
                        }
                        .frame(width: 24, height: 24)
                    }
                } else {
                    Label("FULLSCREEN", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                
                Spacer()
            }
            .padding(.bottom, 8)
            
            Spacer()
            
            // Dynamic Name
            AdaptiveText(text: entry.spaceName, family: family)
                .foregroundStyle(.primary)
                .shadow(color: Color.black.opacity(entry.backgroundStyle == .transparent ? 0.35 : 0), radius: 3, x: 0, y: 1.5)
        }
        .padding(16)
        // FIX: Replaced custom NSViewRepresentable with standard SwiftUI views
        // This prevents the "Yellow Block" crash on some system versions.
        .containerBackground(for: .widget) {
            if entry.backgroundStyle == .transparent {
                Color.clear
            } else {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    // Standard SwiftUI material instead of AppKit wrapper
                    Rectangle()
                        .fill(.regularMaterial)
                        .opacity(0.5)
                }
            }
        }
    }
}

// MARK: - 7. Widget Configuration
@main
struct DesktopNameWidget: Widget {
    let kind: String = "DesktopNameWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: DesktopWidgetIntent.self,
            provider: DesktopNameProvider()
        ) { entry in
            DesktopNameWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Current Desktop")
        .description("Displays your active Space name with dynamic sizing.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
