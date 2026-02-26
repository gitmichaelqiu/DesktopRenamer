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
    let isConnected: Bool // Indicates if data was successfully fetched from the app
}

// MARK: - 4. Async Data Fetcher (IPC without App Groups)
class StandaloneDataFetcher {
    static func fetch(backgroundStyle: WidgetBackgroundStyle) async -> DesktopNameEntry {
        return await withCheckedContinuation { continuation in
            var activeSpaceUUID = ""
            var activeSpaceName = "Desktop"
            var activeSpaceNum = 1
            var spaces: [WidgetSpace] = []
            
            var receivedActive = false
            var receivedList = false
            
            let dnc = DistributedNotificationCenter.default()
            var observers: [Any] = []
            var isFinished = false
            
            // Completion handler to gather results
            let finish = {
                if isFinished { return }
                isFinished = true
                
                for obs in observers { dnc.removeObserver(obs) }
                
                let isDesktop = activeSpaceUUID != "FULLSCREEN"
                let isConnected = receivedActive || receivedList
                
                // If not connected, provide a placeholder state pointing to launch the app
                let finalName = isConnected ? activeSpaceName : "Launch App"
                let finalSpaces = isConnected ? spaces : [WidgetSpace(id: "1", name: "Launch TopMenu", num: 1, displayID: "")]
                
                let entry = DesktopNameEntry(
                    date: Date(),
                    spaceName: finalName,
                    spaceNumber: activeSpaceNum,
                    isDesktop: isDesktop,
                    spaces: finalSpaces,
                    currentUUID: activeSpaceUUID,
                    backgroundStyle: backgroundStyle,
                    isConnected: isConnected
                )
                continuation.resume(returning: entry)
            }
            
            // Timeout in case the main app is completely closed or SpaceAPI is disabled
            // 0.5s is usually plenty for local IPC, max 1.5s to not block WidgetKit indefinitely
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !receivedActive || !receivedList {
                    finish()
                }
            }
            
            // Setup Observers for SpaceAPI notifications
            let obs1 = dnc.addObserver(forName: NSNotification.Name("com.michaelqiu.DesktopRenamer.ReturnActiveSpace"), object: nil, queue: .main) { notif in
                guard let userInfo = notif.userInfo else { return }
                activeSpaceUUID = userInfo["spaceUUID"] as? String ?? ""
                activeSpaceName = userInfo["spaceName"] as? String ?? "Desktop"
                activeSpaceNum = (userInfo["spaceNumber"] as? NSNumber)?.intValue ?? 1
                receivedActive = true
                if receivedList { finish() }
            }
            
            let obs2 = dnc.addObserver(forName: NSNotification.Name("com.michaelqiu.DesktopRenamer.ReturnSpaceList"), object: nil, queue: .main) { notif in
                guard let userInfo = notif.userInfo, let spacesList = userInfo["spaces"] as? [[String: Any]] else { return }
                
                spaces = spacesList.compactMap { dict in
                    guard let id = dict["spaceUUID"] as? String,
                          let name = dict["spaceName"] as? String,
                          let num = (dict["spaceNumber"] as? NSNumber)?.intValue else { return nil }
                    let displayID = dict["displayID"] as? String ?? ""
                    return WidgetSpace(id: id, name: name, num: num, displayID: displayID)
                }
                receivedList = true
                if receivedActive { finish() }
            }
            
            observers = [obs1, obs2]
            
            // Broadcast the requests to the main app
            dnc.postNotificationName(NSNotification.Name("com.michaelqiu.DesktopRenamer.GetActiveSpace"), object: nil, userInfo: nil, deliverImmediately: true)
            dnc.postNotificationName(NSNotification.Name("com.michaelqiu.DesktopRenamer.GetSpaceList"), object: nil, userInfo: nil, deliverImmediately: true)
        }
    }
}

// MARK: - 5. Provider
struct DesktopNameProvider: AppIntentTimelineProvider {
    typealias Entry = DesktopNameEntry
    typealias Intent = DesktopWidgetIntent

    func placeholder(in context: Context) -> DesktopNameEntry {
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
            backgroundStyle: .standard,
            isConnected: true
        )
    }

    func snapshot(for configuration: DesktopWidgetIntent, in context: Context) async -> DesktopNameEntry {
        return await StandaloneDataFetcher.fetch(backgroundStyle: configuration.backgroundStyle)
    }

    func timeline(for configuration: DesktopWidgetIntent, in context: Context) async -> Timeline<DesktopNameEntry> {
        let entry = await StandaloneDataFetcher.fetch(backgroundStyle: configuration.backgroundStyle)
        // Refresh every 5 minutes as a fallback, but normally the main app tells WidgetKit to reload when spaces change.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

// MARK: - 6. Visual Components

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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DesktopListView: View {
    let spaces: [WidgetSpace]
    let currentUUID: String
    let isConnected: Bool
    
    var body: some View {
        VStack(spacing: 6) {
            ForEach(spaces) { space in
                let isCurrent = space.id == currentUUID
                
                Link(destination: URL(string: "desktoprenamer://switch?uuid=\(space.id)") ?? URL(string: "desktoprenamer://switch?num=\(space.num)")!) {
                    HStack(spacing: 8) {
                        if isConnected {
                            Text("\(space.num)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(isCurrent ? .white : .secondary)
                                .frame(width: 18)
                        }
                        
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
                            .fill(isCurrent ? Color.blue : Color.primary.opacity(0.05))
                    }
                }
            }
        }
    }
}

// MARK: - 7. Entry Views

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
            // Group spaces by display logic
            let spaces = entry.spaces
            let chunkSize = 5
            let chunks = stride(from: 0, to: spaces.count, by: chunkSize).map {
                Array(spaces[safe: $0..<min($0 + chunkSize, spaces.count)])
            }
            
            VStack(alignment: .leading, spacing: 5) {
                ForEach(chunks.indices, id: \.self) { chunkIndex in
                    HStack(spacing: 5) {
                        ForEach(chunks[chunkIndex]) { space in
                            let isCurrent = space.id == entry.currentUUID
                            
                            Link(destination: URL(string: "desktoprenamer://switch?uuid=\(space.id)") ?? URL(string: "desktoprenamer://switch?num=\(space.num)")!) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(isCurrent ? Color.blue : Color.primary.opacity(0.1))
                                    
                                    if entry.isConnected {
                                        Text(isCurrent ? "\(space.num)" : (space.name.isEmpty ? "\(space.num)" : String(space.name.prefix(1)).uppercased()))
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .foregroundStyle(isCurrent ? .white : .primary.opacity(0.6))
                                    } else {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundStyle(.primary.opacity(0.6))
                                    }
                                }
                                .frame(width: 20, height: 20)
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            AdaptiveText(text: entry.spaceName, family: .systemSmall)
                .foregroundStyle(entry.isConnected ? .primary : Color.red)
                .shadow(color: Color.black.opacity(entry.backgroundStyle == .transparent ? 0.35 : 0), radius: 3, x: 0, y: 1.5)
        }
        .padding(12)
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
        let showSplitLayout = entry.spaces.count > 4
        
        Group {
            if showSplitLayout {
                HStack(alignment: .top, spacing: 12) {
                    let leftSlice = Array(entry.spaces.prefix(4))
                    DesktopListView(spaces: leftSlice, currentUUID: entry.currentUUID, isConnected: entry.isConnected)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    
                    let rightSlice = Array(entry.spaces.dropFirst(4).prefix(4))
                    DesktopListView(spaces: rightSlice, currentUUID: entry.currentUUID, isConnected: entry.isConnected)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        Spacer()
                        Text(entry.spaceName)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(entry.isConnected ? .primary : Color.red)
                            .minimumScaleFactor(0.6)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    let slice = Array(entry.spaces.prefix(4))
                    DesktopListView(spaces: slice, currentUUID: entry.currentUUID, isConnected: entry.isConnected)
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
        let hideHeadline = entry.spaces.count > 6
        
        VStack(alignment: .leading, spacing: 12) {
            if !hideHeadline {
                Text(entry.spaceName)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.isConnected ? .primary : Color.red)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
            }
            
            let allSlice = entry.spaces
            DesktopListView(spaces: allSlice, currentUUID: entry.currentUUID, isConnected: entry.isConnected)
            
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
