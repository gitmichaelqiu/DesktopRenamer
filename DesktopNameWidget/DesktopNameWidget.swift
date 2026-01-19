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
        
        // Fetch list of space names shared by SpaceManager
        var allNames = defaults?.stringArray(forKey: "widget_allSpaces") ?? []
        
        // Fallback: If list is empty (App hasn't written it yet), generate placeholders
        if allNames.isEmpty {
            let count = max(num, 4)
            // Use "Space X" as a more generic fallback than "Desktop X"
            allNames = (1...count).map { "Space \($0)" }
            // Ensure the current space name matches the display name
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
            allSpaceNames: ["Personal", "Work", "Code", "Music"],
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

// MARK: - 5. Sub-Views
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

struct DesktopListView: View {
    let entry: DesktopNameProvider.Entry
    let limit: Int
    
    var body: some View {
        VStack(spacing: 6) {
            let spaces = Array(entry.allSpaceNames.enumerated().prefix(limit))
            
            ForEach(spaces, id: \.offset) { index, name in
                let spaceNum = index + 1
                let isCurrent = spaceNum == entry.spaceNumber
                
                HStack(spacing: 8) {
                    // Number
                    Text("\(spaceNum)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                        .frame(width: 20, alignment: .trailing)
                    
                    // Name
                    Text(name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Removed redundant green dot
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.1))
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    }
                }
            }
            
            if entry.allSpaceNames.count > limit {
                Text("... and \(entry.allSpaceNames.count - limit) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 6. Entry View (Dispatcher)
struct DesktopNameWidgetEntryView: View {
    var entry: DesktopNameProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(entry: entry)
            case .systemMedium:
                MediumWidgetView(entry: entry)
            case .systemLarge:
                LargeWidgetView(entry: entry)
            default:
                SmallWidgetView(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            if entry.backgroundStyle == .transparent {
                Color.clear
            } else {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    Rectangle()
                        .fill(.regularMaterial)
                        .opacity(0.5)
                }
            }
        }
    }
}

// MARK: - 6a. Small Widget Layout
struct SmallWidgetView: View {
    let entry: DesktopNameProvider.Entry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: Top Indicators
            HStack(spacing: 6) {
                if entry.isDesktop {
                    // Limit to 8 spaces to prevent overflow
                    ForEach(Array(entry.allSpaceNames.prefix(8).enumerated()), id: \.offset) { index, name in
                        let spaceIndex = index + 1
                        let isCurrent = spaceIndex == entry.spaceNumber
                        
                        // Small Widget Requirement:
                        // Current desktop: show the number
                        // Other desktops: show the first letter instead of the number
                        let labelText: String = {
                            if isCurrent {
                                return "\(spaceIndex)"
                            } else {
                                return String(name.prefix(1)).uppercased()
                            }
                        }()
                        
                        ZStack {
                            // Background Square
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isCurrent ? Color.primary : Color.primary.opacity(0.1))
                            
                            // Border for inactive
                            if !isCurrent {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                            }
                            
                            // Content
                            Text(labelText)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(isCurrent ? Color(nsColor: .windowBackgroundColor) : Color.primary.opacity(0.6))
                        }
                        .frame(width: 22, height: 22)
                    }
                    
                    if entry.allSpaceNames.count > 8 {
                        Circle()
                            .fill(Color.primary.opacity(0.3))
                            .frame(width: 4, height: 4)
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
            AdaptiveText(text: entry.spaceName, family: .systemSmall)
                .foregroundStyle(.primary)
                .shadow(color: Color.black.opacity(entry.backgroundStyle == .transparent ? 0.35 : 0), radius: 3, x: 0, y: 1.5)
        }
        .padding(16)
    }
}

// MARK: - 6b. Medium Widget Layout
struct MediumWidgetView: View {
    let entry: DesktopNameProvider.Entry
    
    var body: some View {
        // Medium requirement:
        // 1. Big name at the bottom left corner.
        // 2. List on the right half.
        // 3. List style: Vertical buttons, Number before name, Mark current (handled by DesktopListView).
        
        HStack(alignment: .bottom, spacing: 16) {
            // Left Side: Name
            VStack(alignment: .leading) {
                Spacer()
                AdaptiveText(text: entry.spaceName, family: .systemSmall)
                    .foregroundStyle(.primary)
                    .shadow(color: Color.black.opacity(entry.backgroundStyle == .transparent ? 0.35 : 0), radius: 3, x: 0, y: 1.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Right Side: List
            VStack(alignment: .leading) {
                if entry.isDesktop {
                    // We fit about 4 items comfortably in medium height
                    DesktopListView(entry: entry, limit: 4)
                } else {
                    Spacer()
                    HStack {
                        Spacer()
                        Label("Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
    }
}

// MARK: - 6c. Large Widget Layout
struct LargeWidgetView: View {
    let entry: DesktopNameProvider.Entry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Large requirement: Top headline shows current desktop name
            Text(entry.spaceName)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(.primary)
                .shadow(color: Color.black.opacity(entry.backgroundStyle == .transparent ? 0.35 : 0), radius: 3, x: 0, y: 1.5)
            
            // Under it is a list
            if entry.isDesktop {
                // Large widget can fit more, maybe 8-10 depending on padding.
                DesktopListView(entry: entry, limit: 8)
            } else {
                Text("Fullscreen Mode")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
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
        // Added .systemLarge support
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
