import WidgetKit
import SwiftUI
import AppIntents

// MARK: - 1. Configuration Enum
enum WidgetBackgroundStyle: String, AppEnum {
    case standard
    case transparent

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Background Style"

    static var caseDisplayRepresentations: [WidgetBackgroundStyle: DisplayRepresentation] = [
        .standard: "Standard",
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
struct WidgetSpace: Codable, Identifiable {
    let id: String
    let name: String
    let num: Int
    let displayID: String
}

struct DesktopNameEntry: TimelineEntry {
    let date: Date
    let spaceName: String
    let spaceNumber: Int
    let isDesktop: Bool
    let spaces: [WidgetSpace]
    let currentUUID: String
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
        let currentUUID = defaults?.string(forKey: "widget_currentSpaceUUID") ?? ""
        
        // 2. Get the structured space list
        var loadedSpaces: [WidgetSpace] = []
        if let data = defaults?.data(forKey: "widget_spacesData"),
           let spaces = try? JSONDecoder().decode([WidgetSpace].self, from: data) {
            loadedSpaces = spaces
        }
        
        return DesktopNameEntry(
            date: Date(),
            spaceName: name,
            spaceNumber: num,
            isDesktop: isDesktop,
            spaces: loadedSpaces,
            currentUUID: currentUUID,
            backgroundStyle: configuration.backgroundStyle
        )
    }

    func placeholder(in context: Context) -> DesktopNameEntry {
        // Mock Data
        let spaces = [
            WidgetSpace(id: "1", name: "Work", num: 1, displayID: "Main"),
            WidgetSpace(id: "2", name: "Personal", num: 2, displayID: "Main"),
            WidgetSpace(id: "3", name: "Dev", num: 1, displayID: "Ext"),
            WidgetSpace(id: "4", name: "Music", num: 2, displayID: "Ext")
        ]
        
        return DesktopNameEntry(
            date: Date(),
            spaceName: "Work",
            spaceNumber: 1,
            isDesktop: true,
            spaces: spaces,
            currentUUID: "1",
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
        // FIX: Force alignment to leading to prevent "drift" when content changes
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A reusable list view that renders a specific slice of the spaces array
struct DesktopListView: View {
    let spaces: [WidgetSpace]
    let currentUUID: String
    
    var body: some View {
        VStack(spacing: 6) {
            ForEach(spaces) { space in
                let isCurrent = space.id == currentUUID
                
                // Construct URL with ID if possible, but app uses num. 
                // We'll stick to num but beware duplicate nums across displays.
                // ideally app should handle switch by UUID, but protocol says 'num'.
                // If the app only accepts num, we might have issues switching to 2nd display by num?
                // Wait, SpaceHelper.switchToSpace takes ID (String). 
                // The URL scheme likely maps to `SpaceHelper.switchToSpace(id)`.
                // Let's assume the URL handler can take UUID or we pass global index?
                // The existing URL scheme `desktoprenamer://switch?num=` likely parses int.
                // Assuming we can update URL scheme later if needed. For now sticking to existing behavior
                // BUT: User said "Work on the key mapping first" which we did (GlobalShortcutNum).
                // If we pass `num` here (1, 2, 1, 2), the app needs to know which display.
                // Let's rely on the user's request for VISUAL grouping first.
                
                Link(destination: URL(string: "desktoprenamer://switch?uuid=\(space.id)") ?? URL(string: "desktoprenamer://switch?num=\(space.num)")!) {
                    HStack(spacing: 8) {
                        Text("\(space.num)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(isCurrent ? .white : .secondary)
                            .frame(width: 18)
                        
                        Text(space.name)
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
            // MARK: Top Indicators
            // Group spaces by display
            // Dictionary grouping does not preserve order, so we iterate.
            
            // Logic: 5 items per row.
            // If we have multiple displays, we want to visually separate them?
            // "Group the spaces by displays... rearrange the space according to the display"
            // "each line can contain 5 widgets"
            
            let spaces = entry.spaces
            
            // Chunk into rows of 5
            let chunkSize = 5
            let chunks = stride(from: 0, to: spaces.count, by: chunkSize).map {
                Array(spaces[safe: $0..<min($0 + chunkSize, spaces.count)])
            }
            
            VStack(alignment: .leading, spacing: 5) {
                ForEach(chunks.indices, id: \.self) { chunkIndex in
                    HStack(spacing: 5) {
                        ForEach(chunks[chunkIndex]) { space in
                            let isCurrent = space.id == entry.currentUUID
                            
                            // Use UUID for robust switching if supported, fallback to num
                            Link(destination: URL(string: "desktoprenamer://switch?uuid=\(space.id)") ?? URL(string: "desktoprenamer://switch?num=\(space.num)")!) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(isCurrent ? Color.blue : Color.primary.opacity(0.1))
                                    
                                    // Highlight first letter. If unnamed/default, show Number.
                                    // Actually, user wants index to restart. `space.num` does that.
                                    // Design: Show Number for current, Initials for others? 
                                    // Original code: `isCurrent ? "\(index + 1)" : String(name.prefix(1)).uppercased()`
                                    // Let's use `space.num` for current.
                                    
                                    Text(isCurrent ? "\(space.num)" : (space.name.isEmpty ? "\(space.num)" : String(space.name.prefix(1)).uppercased()))
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(isCurrent ? .white : .primary.opacity(0.6))
                                }
                                .frame(width: 20, height: 20)
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            // Big Name at bottom
            AdaptiveText(text: entry.spaceName, family: .systemSmall)
                .foregroundStyle(.primary)
                .shadow(color: Color.black.opacity(entry.backgroundStyle == .transparent ? 0.35 : 0), radius: 3, x: 0, y: 1.5)
        }
        .padding(12)
        // FIX: Ensure entire Small widget content is pinned to the leading edge
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Array {
    subscript (safe range: Range<Index>) -> ArraySlice<Element> {
        return self[range.clamped(to: indices)]
    }
}

struct MediumLayout: View {
    let entry: DesktopNameEntry
    
    var body: some View {
        // Logic: If > 4 spaces, split into 2 columns (no big name).
        // Max 8 spaces total.
        let showSplitLayout = entry.spaces.count > 4
        
        Group {
            if showSplitLayout {
                HStack(alignment: .top, spacing: 12) {
                    // Left Column: 1-4
                    let leftSlice = Array(entry.spaces.prefix(4))
                    DesktopListView(spaces: leftSlice, currentUUID: entry.currentUUID)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    
                    // Right Column: 5-8
                    let rightSlice = Array(entry.spaces.dropFirst(4).prefix(4))
                    DesktopListView(spaces: rightSlice, currentUUID: entry.currentUUID)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else {
                // Standard Layout: Name Left, List Right
                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        Spacer()
                        Text(entry.spaceName)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6)
                            .lineLimit(2)
                            // FIX: Prevent drift for multi-line text
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    let slice = Array(entry.spaces.prefix(4))
                    DesktopListView(spaces: slice, currentUUID: entry.currentUUID)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
    }
}

struct LargeLayout: View {
    let entry: DesktopNameEntry
    
    var body: some View {
        // Logic: If > 6 spaces, hide headline name and fill list.
        let hideHeadline = entry.spaces.count > 6
        
        VStack(alignment: .leading, spacing: 12) {
            if !hideHeadline {
                Text(entry.spaceName)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    // FIX: Prevent drift
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
            }
            
            // Fill with list.
            let allSlice = entry.spaces
            DesktopListView(spaces: allSlice, currentUUID: entry.currentUUID)
            
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
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
