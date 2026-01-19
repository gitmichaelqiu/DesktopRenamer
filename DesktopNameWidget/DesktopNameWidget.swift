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
        
        // 1. Get current space info
        let name = defaults?.string(forKey: "widget_spaceName") ?? "Desktop"
        let num = defaults?.integer(forKey: "widget_spaceNum") ?? 1
        let isDesktop = (defaults?.object(forKey: "widget_isDesktop") as? Bool) ?? true
        
        // 2. Get the ACTUAL customized names list saved by SpaceManager
        // This key MUST match what is saved in SpaceManager.performWidgetUpdate
        let allNames = defaults?.stringArray(forKey: "widget_allSpaces") ?? []
        
        // Fallback logic if the array is empty
        let finalSpaceNames: [String]
        if allNames.isEmpty {
            finalSpaceNames = [name]
        } else {
            finalSpaceNames = allNames
        }
        
        return DesktopNameEntry(
            date: Date(),
            spaceName: name,
            spaceNumber: num,
            isDesktop: isDesktop,
            allSpaceNames: finalSpaceNames,
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

// MARK: - 5. Visual Components

struct DesktopListView: View {
    let entry: DesktopNameEntry
    let limit: Int
    
    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<min(entry.allSpaceNames.count, limit), id: \.self) { index in
                let spaceName = entry.allSpaceNames[index]
                let spaceNum = index + 1
                let isCurrent = spaceNum == entry.spaceNumber
                
                HStack(spacing: 8) {
                    Text("\(spaceNum)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(isCurrent ? .white : .secondary)
                        .frame(width: 18)
                    
                    Text(spaceName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isCurrent ? .white : .primary)
                        .lineLimit(1)
                    
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        // Blue Highlight for Current Desktop
                        .fill(isCurrent ? Color.blue : Color.primary.opacity(0.05))
                }
            }
        }
    }
}

// MARK: - 6. Entry Views

struct DesktopNameWidgetEntryView: View {
    var entry: DesktopNameEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallLayout(entry: entry)
            case .systemMedium:
                MediumLayout(entry: entry)
            case .systemLarge:
                LargeLayout(entry: entry)
            default:
                SmallLayout(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            if entry.backgroundStyle == .transparent {
                Color.clear
            } else {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    Rectangle().fill(.regularMaterial).opacity(0.5)
                }
            }
        }
    }
}

struct SmallLayout: View {
    let entry: DesktopNameEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<min(entry.allSpaceNames.count, 5), id: \.self) { index in
                    let isCurrent = (index + 1) == entry.spaceNumber
                    let name = entry.allSpaceNames[index]
                    
                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isCurrent ? Color.blue : Color.primary.opacity(0.1))
                        Text(isCurrent ? "\(index + 1)" : String(name.prefix(1)).uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(isCurrent ? .white : .primary.opacity(0.6))
                    }
                    .frame(width: 20, height: 20)
                }
            }
            Spacer()
            Text(entry.spaceName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .padding(12)
    }
}

struct MediumLayout: View {
    let entry: DesktopNameEntry
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Spacer()
                Text(entry.spaceName)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            DesktopListView(entry: entry, limit: 4)
                .frame(maxWidth: .infinity)
        }
        .padding(12)
    }
}

struct LargeLayout: View {
    let entry: DesktopNameEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.spaceName)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .lineLimit(1)
            
            Divider()
            
            DesktopListView(entry: entry, limit: 8)
        }
        .padding(16)
    }
}

@main
struct DesktopNameWidget: Widget {
    let kind: String = "DesktopNameWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: DesktopWidgetIntent.self, provider: DesktopNameProvider()) { entry in
            DesktopNameWidgetEntryView(entry: entry)
        }
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
