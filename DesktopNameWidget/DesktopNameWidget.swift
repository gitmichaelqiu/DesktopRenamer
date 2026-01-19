import WidgetKit
import SwiftUI
import AppIntents

// MARK: - 1. Configuration Enum
/// Use AppEnum to provide the options in the "Edit Widget" menu.
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
/// This structure must be clean for macOS to generate the "Edit Widget" UI.
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
    let backgroundStyle: WidgetBackgroundStyle
}

// MARK: - 4. Provider
struct DesktopNameProvider: AppIntentTimelineProvider {
    // Explicitly define types to help the compiler
    typealias Entry = DesktopNameEntry
    typealias Intent = DesktopWidgetIntent
    
    let appGroupIdentifier = "group.com.michaelqiu.DesktopRenamer"

    private func fetchSharedData(for configuration: DesktopWidgetIntent) -> DesktopNameEntry {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        let name = defaults?.string(forKey: "widget_spaceName") ?? "Desktop"
        let num = defaults?.integer(forKey: "widget_spaceNum") ?? 1
        let isDesktop = (defaults?.object(forKey: "widget_isDesktop") as? Bool) ?? true
        
        return DesktopNameEntry(
            date: Date(),
            spaceName: name,
            spaceNumber: num,
            isDesktop: isDesktop,
            backgroundStyle: configuration.backgroundStyle
        )
    }

    func placeholder(in context: Context) -> DesktopNameEntry {
        DesktopNameEntry(date: Date(), spaceName: "Work", spaceNumber: 1, isDesktop: true, backgroundStyle: .standard)
    }

    func snapshot(for configuration: DesktopWidgetIntent, in context: Context) async -> DesktopNameEntry {
        fetchSharedData(for: configuration)
    }

    func timeline(for configuration: DesktopWidgetIntent, in context: Context) async -> Timeline<DesktopNameEntry> {
        let entry = fetchSharedData(for: configuration)
        // policy: .never implies the main app will call WidgetCenter.shared.reloadTimelines
        return Timeline(entries: [entry], policy: .never)
    }
}

// MARK: - 5. Dynamic Text View
struct AdaptiveText: View {
    let text: String
    let family: WidgetFamily
    
    var body: some View {
        // ViewThatFits is the most reliable way to handle "Dynamic Size" in SwiftUI
        // It picks the largest view that doesn't overflow horizontally.
        ViewThatFits(in: .horizontal) {
            // Priority 1: Large
            Text(text)
                .font(.system(size: family == .systemSmall ? 34 : 48, weight: .bold, design: .rounded))
            
            // Priority 2: Medium
            Text(text)
                .font(.system(size: family == .systemSmall ? 26 : 36, weight: .bold, design: .rounded))
            
            // Priority 3: Small + Scaling fallback
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
            // Top Badge (Space Number)
            HStack {
                Label {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                } icon: {
                    Image(systemName: entry.isDesktop ? "macwindow" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                
                Spacer()
            }
            
            Spacer()
            
            // Dynamic Name
            AdaptiveText(text: entry.spaceName, family: family)
                .foregroundStyle(.primary)
                // Shadow helps readability if the user chooses 'Transparent' over a busy wallpaper
                .shadow(color: Color.black.opacity(entry.backgroundStyle == .transparent ? 0.35 : 0), radius: 3, x: 0, y: 1.5)
        }
        .padding(16)
        // Use containerBackground for modern Widget API (Required for macOS Sonoma+)
        .containerBackground(for: .widget) {
            if entry.backgroundStyle == .transparent {
                Color.clear
            } else {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    VisualEffectView().opacity(0.5)
                }
            }
        }
    }
    
    private var badgeText: String {
        if entry.isDesktop {
            return entry.spaceNumber > 0 ? "SPACE \(entry.spaceNumber)" : "DESKTOP"
        } else {
            return "FULLSCREEN"
        }
    }
}

// Helper for macOS Background Blur
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.state = .active
        view.material = .headerView
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - 7. Widget Configuration
@main
struct DesktopNameWidget: Widget {
    let kind: String = "DesktopNameWidget"

    var body: some WidgetConfiguration {
        // AppIntentConfiguration allows the "Edit Widget" menu to appear on macOS
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
