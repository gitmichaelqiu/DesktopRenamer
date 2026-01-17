import WidgetKit
import SwiftUI
import AppKit // Required for NSColor

// Make sure this matches the ID used in SpaceManager.swift and your Xcode Capabilities
let appGroupIdentifier = "group.com.michaelqiu.DesktopRenamer"

// MARK: - Timeline Entry
struct DesktopNameEntry: TimelineEntry {
    let date: Date
    let spaceName: String
    let spaceNumber: Int
    let isDesktop: Bool
}

// MARK: - Provider
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
        let entry = getCurrentEntry()
        // Policy .never because the main app triggers reloads manually
        let timeline = Timeline(entries: [entry], policy: .never)
        NSLog("Widget: Timeline created for \(entry.spaceName)")
        completion(timeline)
    }
    
    private func getCurrentEntry() -> DesktopNameEntry {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("Widget Error: App Group \(appGroupIdentifier) inaccessible")
            return DesktopNameEntry(date: Date(), spaceName: "Check App Group", spaceNumber: 0, isDesktop: true)
        }
        
        let name = defaults.string(forKey: "widget_spaceName")
        let num = defaults.integer(forKey: "widget_spaceNum")
        // Default to true (Desktop) if key is missing to avoid "Fullscreen" flash on first run
        let isDesktop = (defaults.object(forKey: "widget_isDesktop") as? Bool) ?? true
        
        let displayName = name ?? "Unknown"
        
        if displayName == "Unknown" && num == 0 {
            return DesktopNameEntry(date: Date(), spaceName: "Waiting for App...", spaceNumber: 0, isDesktop: true)
        }
        
        return DesktopNameEntry(date: Date(), spaceName: displayName, spaceNumber: num, isDesktop: isDesktop)
    }
}

// MARK: - Entry View
struct DesktopNameWidgetEntryView: View {
    var entry: DesktopNameProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header Label
            if entry.isDesktop {
                if entry.spaceNumber > 0 {
                    Text("Space \(entry.spaceNumber)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                } else {
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

            // Space Name
            Text(entry.spaceName)
                .font(.title2)
                .fontWeight(.bold)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .foregroundColor(.primary)
            
            // Debug Timestamp (Optional: remove in production)
            Text("Updated: \(Date(), style: .time)")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .opacity(0.5)
        }
        .padding() // Standard padding for content
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetBackground(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Background Modifier
struct WidgetBackgroundModifier: ViewModifier {
    let color: Color
    
    func body(content: Content) -> some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                color
            }
        } else {
            ZStack {
                ContainerRelativeShape()
                    .fill(color)
                content
            }
        }
    }
}

extension View {
    func widgetBackground(_ color: Color) -> some View {
        modifier(WidgetBackgroundModifier(color: color))
    }
}

// MARK: - Configuration
@main
struct DesktopNameWidget: Widget {
    let kind: String = "DesktopNameWidget"

    // NOTE: If widget does not appear, run 'killall chronod' in Terminal.
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DesktopNameProvider()) { entry in
            DesktopNameWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Current Desktop")
        .description("Shows the name of the currently active desktop.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled() // Important for proper macOS 14+ background rendering
    }
}

// MARK: - Preview
struct DesktopNameWidget_Previews: PreviewProvider {
    static var previews: some View {
        DesktopNameWidgetEntryView(entry: DesktopNameEntry(date: Date(), spaceName: "Work Mode", spaceNumber: 1, isDesktop: true))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
