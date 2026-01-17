import WidgetKit
import SwiftUI
import AppKit // Required for NSColor

// Make sure this matches the ID used in SpaceManager.swift and your Xcode Capabilities
let appGroupIdentifier = "group.com.michaelqiu.DesktopRenamer"

struct DesktopNameEntry: TimelineEntry {
    let date: Date
    let spaceName: String
    let spaceNumber: Int
    let isDesktop: Bool
}

struct DesktopNameProvider: TimelineProvider {
    func placeholder(in context: Context) -> DesktopNameEntry {
        DesktopNameEntry(date: Date(), spaceName: "Desktop 1", spaceNumber: 1, isDesktop: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (DesktopNameEntry) -> ()) {
        NSLog("Widget: getSnapshot called")
        let entry = getCurrentEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DesktopNameEntry>) -> ()) {
        NSLog("Widget: getTimeline called")
        // Create a timeline with a single entry representing "now".
        // The policy is .never because the main app calls reloadAllTimelines() when the space changes.
        let entry = getCurrentEntry()
        let timeline = Timeline(entries: [entry], policy: .never)
        NSLog("Widget: Timeline created with entry: \(entry.spaceName) (Space \(entry.spaceNumber))")
        completion(timeline)
    }
    
    private func getCurrentEntry() -> DesktopNameEntry {
        NSLog("Widget: Reading from App Group \(appGroupIdentifier)")
        // Defensive check: Ensure App Group is accessible
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("Widget Error: Could not load UserDefaults for suite: \(appGroupIdentifier). Check capabilities.")
            return DesktopNameEntry(date: Date(), spaceName: "Check App Group ID", spaceNumber: 0, isDesktop: true)
        }
        
        let name = defaults.string(forKey: "widget_spaceName")
        let num = defaults.integer(forKey: "widget_spaceNum")
        // Use object(forKey:) to check if value exists; default to true (Desktop) if missing to avoid "Fullscreen" flash
        let isDesktop = (defaults.object(forKey: "widget_isDesktop") as? Bool) ?? true
        
        NSLog("Widget Read: Name: \(String(describing: name)), Num: \(num), IsDesktop: \(isDesktop)")
        
        let displayName = name ?? "Unknown"
        
        // If data is missing (e.g. fresh install or app hasn't run yet)
        if displayName == "Unknown" && num == 0 {
            NSLog("Widget: Data appears empty/default. Returning 'Waiting for App...'")
            return DesktopNameEntry(date: Date(), spaceName: "Waiting for App...", spaceNumber: 0, isDesktop: true)
        }
        
        return DesktopNameEntry(date: Date(), spaceName: displayName, spaceNumber: num, isDesktop: isDesktop)
    }
}

struct DesktopNameWidgetEntryView: View {
    var entry: DesktopNameProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            // Use windowBackgroundColor for standard widget background
            ContainerRelativeShape()
                .fill(Color(nsColor: .windowBackgroundColor))
            
            VStack(alignment: .leading, spacing: 4) {
                // Header Label (Space Number or Fullscreen Status)
                if entry.isDesktop {
                    if entry.spaceNumber > 0 {
                        Text("Space \(entry.spaceNumber)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                    } else {
                        // Fallback for desktops without numbers
                        Text("Fullscreen")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                    }
                } else {
                    Text("Fullscreen")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }

                // The Space Name
                Text(entry.spaceName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                // DEBUG: Timestamp to verify updates
                Text("Updated: \(Date(), style: .time)")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .opacity(0.5)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@main
struct DesktopNameWidget: Widget {
    let kind: String = "DesktopNameWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DesktopNameProvider()) { entry in
            DesktopNameWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Current Desktop")
        .description("Shows the name of the currently active desktop.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview Provider
// This allows you to verify the widget UI in Xcode's Canvas without running the simulator.
struct DesktopNameWidget_Previews: PreviewProvider {
    static var previews: some View {
        DesktopNameWidgetEntryView(entry: DesktopNameEntry(date: Date(), spaceName: "Work Mode", spaceNumber: 1, isDesktop: true))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
