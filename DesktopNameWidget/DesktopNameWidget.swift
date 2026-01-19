import WidgetKit
import SwiftUI
import AppIntents

// MARK: - 1. Configuration Enum (Right-Click Option)
// This creates a professional dropdown in the widget settings
enum WidgetBackgroundStyle: String, AppEnum {
    case standard
    case transparent

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Background Style"

    static var caseDisplayRepresentations: [WidgetBackgroundStyle: DisplayRepresentation] = [
        .standard: "Standard (Window Color)",
        .transparent: "Transparent"
    ]
}

// MARK: - 2. Widget Intent
struct DesktopWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Appearance"
    static var description: LocalizedStringResource = "Customize the look of your desktop widget."

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

// MARK: - 4. Provider (Data Logic)
struct DesktopNameProvider: AppIntentTimelineProvider {
    // IMPORTANT: Ensure this matches your Entitlements exactly.
    let appGroupIdentifier = "group.com.michaelqiu.DesktopRenamer"

    // Helper to safely fetch data even if App quits
    private func fetchSharedData(for configuration: DesktopWidgetIntent) -> DesktopNameEntry {
        // Fallback data prevents crashes (which cause the 'Please adopt...' error)
        let fallbackName = "Desktop"
        let fallbackNum = 1
        
        // Attempt to load shared defaults
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        
        let name = defaults?.string(forKey: "widget_spaceName") ?? fallbackName
        let num = defaults?.integer(forKey: "widget_spaceNum") ?? fallbackNum
        // Use object(forKey:) to safely check boolean presence, default to true
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
        // .never policy means the main app must call WidgetCenter.shared.reloadAllTimelines()
        return Timeline(entries: [entry], policy: .never)
    }
}

// MARK: - 5. Entry View (Styling & Fix)
struct DesktopNameWidgetEntryView: View {
    var entry: DesktopNameProvider.Entry
    
    // Aesthetic Constants
    private let secondaryOpacity: Double = 0.6
    private let badgeOpacity: Double = 0.1

    var body: some View {
        // ZStack ensures containerBackground is applied to the root wrapper
        ZStack {
            VStack(alignment: .leading, spacing: 6) {
                
                // Top Badge (Space Number / Fullscreen)
                HStack {
                    Label {
                        Text(badgeText)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    } icon: {
                        // Dynamic icon based on state
                        Image(systemName: entry.isDesktop ? "macwindow" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Material.regular, in: Capsule())
                    .opacity(0.8)
                    
                    Spacer()
                }
                
                Spacer()
                
                // Main Desktop Name
                // ViewThatFits handles long names gracefully without layout breaks
                ViewThatFits(in: .horizontal) {
                    Text(entry.spaceName)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    
                    Text(entry.spaceName)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    
                    Text(entry.spaceName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.primary)
                .lineLimit(1)
                .shadow(color: .black.opacity(entry.backgroundStyle == .transparent ? 0.2 : 0), radius: 2, x: 0, y: 1)
            }
            .padding(12) // Consistent internal padding
        }
        // FIXED: The containerBackground modifier is now applied to the root ZStack.
        // This ensures the system always finds it, preventing the "Adopt API" error.
        .containerBackground(for: .widget) {
            switch entry.backgroundStyle {
            case .transparent:
                Color.clear
            case .standard:
                // Uses the native macOS window background color
                Color(nsColor: .windowBackgroundColor)
            }
        }
    }
    
    // Computed property for the badge text
    private var badgeText: String {
        if entry.isDesktop {
            return entry.spaceNumber > 0 ? "SPACE \(entry.spaceNumber)" : "DESKTOP"
        } else {
            return "FULLSCREEN"
        }
    }
}

// MARK: - 6. Widget Configuration
@main
struct DesktopNameWidget: Widget {
    let kind: String = "DesktopNameWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: DesktopWidgetIntent.self, provider: DesktopNameProvider()) { entry in
            DesktopNameWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Current Desktop")
        .description("Shows the name of the currently active desktop.")
        .supportedFamilies([.systemSmall, .systemMedium])
        // contentMarginsDisabled allows the text to look cleaner,
        // especially in transparent mode where you don't want a forced bezel.
        .contentMarginsDisabled()
    }
}
