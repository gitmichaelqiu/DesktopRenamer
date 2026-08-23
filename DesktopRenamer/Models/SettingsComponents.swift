import SwiftUI
import AVKit
import AVFoundation

struct AnimatedSettingsValue: View {
    let text: String
    @State private var displayedText: String

    init(text: String) {
        self.text = text
        _displayedText = State(initialValue: text)
    }

    var body: some View {
        Text(displayedText)
            .monospacedDigit()
            .contentTransition(.numericText())
            .onChange(of: text) { newText in
                withSettingsAnimation {
                    displayedText = newText
                }
            }
    }
}

func withSettingsAnimation(_ action: () -> Void) {
    if #available(macOS 14.0, *) {
        withAnimation(.snappy(duration: 0.18)) {
            action()
        }
    } else {
        withAnimation(.easeOut(duration: 0.18)) {
            action()
        }
    }
}

class LoopVideoPlayerNSView: NSView {
    private var looper: AVPlayerLooper?
    private var player: AVQueuePlayer?
    private(set) var currentURL: URL?

    var playerLayer: AVPlayerLayer? {
        self.layer as? AVPlayerLayer
    }
    
    override func makeBackingLayer() -> CALayer {
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.clear.cgColor
        return layer
    }
    
    func setupPlayer(with url: URL) {
        cleanup()
        self.currentURL = url
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
        
        let player = AVQueuePlayer()
        let playerItem = AVPlayerItem(url: url)
        let playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
        
        self.playerLayer?.player = player
        player.isMuted = true
        player.play()
        
        self.looper = playerLooper
        self.player = player
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        
        if let oldWindow = self.window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: oldWindow)
        }
        
        if let newWindow = newWindow {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: newWindow
            )
        } else {
            cleanup()
        }
    }
    
    @objc private func windowWillClose(_ notification: Notification) {
        cleanup()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func cleanup() {
        player?.pause()
        playerLayer?.player = nil
        looper = nil
        player = nil
        currentURL = nil
    }
    
    override func scrollWheel(with event: NSEvent) {
        self.nextResponder?.scrollWheel(with: event)
    }
}

struct LoopVideoPlayerRepresentable: NSViewRepresentable {
    let videoURL: URL
    
    func makeNSView(context: Context) -> LoopVideoPlayerNSView {
        let view = LoopVideoPlayerNSView()
        view.setupPlayer(with: videoURL)
        return view
    }
    
    func updateNSView(_ nsView: LoopVideoPlayerNSView, context: Context) {
        if nsView.currentURL != videoURL {
            nsView.setupPlayer(with: videoURL)
        }
    }
    
    static func dismantleNSView(_ nsView: LoopVideoPlayerNSView, coordinator: Coordinator) {
        nsView.cleanup()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {}
}

struct IsSettingsPreRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSettingsPreRendering: Bool {
        get { self[IsSettingsPreRenderingKey.self] }
        set { self[IsSettingsPreRenderingKey.self] = newValue }
    }
}

struct LoopVideoPlayerView: View {
    let videoURL: URL
    @Environment(\.isSettingsPreRendering) private var isPreRendering
    
    var body: some View {
        if isPreRendering {
            Color.clear
        } else {
            LoopVideoPlayerRepresentable(videoURL: videoURL)
        }
    }
}

struct SettingsTabKey: EnvironmentKey {
    static let defaultValue: SettingsTab = .general
}

extension EnvironmentValues {
    var settingsTab: SettingsTab {
        get { self[SettingsTabKey.self] }
        set { self[SettingsTabKey.self] = newValue }
    }
}

struct SearchableSettingItem: Identifiable, Hashable {
    let title: String
    let localizedTitle: String
    let tab: SettingsTab
    let keywords: [String]

    var id: String { "\(tab.rawValue):\(title)" }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(tab)
    }
    
    static func == (lhs: SearchableSettingItem, rhs: SearchableSettingItem) -> Bool {
        lhs.title == rhs.title && lhs.tab == rhs.tab
    }
}

enum SettingsCatalog {
    static let items: [SearchableSettingItem] = [
        item("Show preview labels", tab: .general),
        item("Show active space labels", tab: .general),
        item("Hide menubar icon", tab: .general),
        item("Settings.General.General.LaunchAtLogin", tab: .general),
        item("Settings.General.Updates.AutoCheckUpdate", tab: .general),
        item("Automatically download updates", tab: .general),
        item("Settings.General.Updates.ManualCheck", tab: .general),
        item("Settings.General.Advanced.EnableAPI", tab: .general),
        item("Diagnostic Report", tab: .general),
        item("Review Splash", tab: .general),
        item("Factory Reset", tab: .general),
        item("Keep full-screen spaces next to source desktop", tab: .space),
        item("Settings.Spaces.Edit.Name", tab: .space, keywords: ["rename", "name", "title", "label", "custom", "edit"]),
        item("Settings.Spaces.Edit.Actions", tab: .space, keywords: ["reorder", "arrange", "display", "monitor", "position"]),
        item("Show preview labels", tab: .labels),
        item("Hide when switching spaces", tab: .labels),
        item("Disable Liquid Glass effects", tab: .labels),
        item("Font size", tab: .labels),
        item("Window size", tab: .labels),
        item("Show active space labels", tab: .labels),
        item("Keep visible on space", tab: .labels),
        item("Reload space labels", tab: .labels),
        item("Switch to previous space", tab: .sswitch),
        item("Switch to next space", tab: .sswitch),
        item("Switch to space number", tab: .sswitch),
        item("Move window to previous space", tab: .sswitch),
        item("Move window to next space", tab: .sswitch),
        item("Move window to space number", tab: .sswitch),
        item("Move window to previous display", tab: .sswitch),
        item("Move window to next display", tab: .sswitch),
        item("Toggle lock for current space", tab: .sswitch),
        item("Restore windows moved by lock", tab: .sswitch),
        item("Enable switch gesture override", tab: .sswitch),
        item("Gesture type", tab: .sswitch),
        item("Switch display with", tab: .sswitch),
        item("Move window when holding Option", tab: .sswitch),
        item("Switch duration", tab: .sswitch),
        item("Switch override threshold", tab: .sswitch),
        item("Grab offset X", tab: .sswitch),
        item("Grab offset Y", tab: .sswitch),
        item("Exceptions", tab: .sswitch),
        item("Drag window slightly before switching", tab: .sswitch),
        item("Open launcher", tab: .launcher),
        item("Automatically return to original space", tab: .launcher),
        item("Automatically rank commands", tab: .launcher),
        item("Settings.Launcher.Command.Actions", tab: .launcher, keywords: ["reorder", "arrange", "sequence", "position", "move", "up", "down", "rank"]),
        item("GitHub / Support", tab: .about, keywords: ["github", "website", "developer", "contact", "support"]),
        item("Accessibility", tab: .permissions)
    ]

    private static func item(_ title: String, tab: SettingsTab, keywords: [String] = []) -> SearchableSettingItem {
        let localizedTitle = NSLocalizedString(title, comment: "")
        let generatedKeywords = keywords
            + title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            + localizedTitle.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)

        SearchableSettingItem(
            title: title,
            localizedTitle: localizedTitle,
            tab: tab,
            keywords: Array(Set(generatedKeywords.filter { $0.count > 1 }))
        )
    }
}

class SettingsNavigationState: ObservableObject {
    @Published var scrollToItemID: String? = nil
    @Published var searchText: String = ""
    @Published var registeredItems: [SearchableSettingItem] = SettingsCatalog.items
    
    func register(title: String, tab: SettingsTab, keywords: [String] = []) {
        // Search items are indexed statically so settings pages do not need to be
        // instantiated off-screen just to register their labels.
    }

    func unregister(title: String, tab: SettingsTab) {
        // Kept as a no-op for existing SettingsRow lifecycle calls.
    }
}

func highlightedText(text: String, query: String, color: Color? = .blue) -> AttributedString {
    var attributed = AttributedString(text)
    guard !query.isEmpty else { return attributed }
    
    let lowerQuery = query.lowercased()
    var searchStart = attributed.startIndex
    
    while searchStart < attributed.endIndex {
        let remainingString = String(attributed[searchStart...].characters)
        guard let range = remainingString.lowercased().range(of: lowerQuery) else { break }
        
        let matchStartIndex = remainingString.distance(from: remainingString.startIndex, to: range.lowerBound)
        let matchLength = remainingString.distance(from: range.lowerBound, to: range.upperBound)
        
        let startIdx = attributed.index(searchStart, offsetByCharacters: matchStartIndex)
        let endIdx = attributed.index(startIdx, offsetByCharacters: matchLength)
        let targetRange = startIdx..<endIdx
        
        if let color = color {
            attributed[targetRange].foregroundColor = color
        }
        attributed[targetRange].inlinePresentationIntent = .stronglyEmphasized
        
        searchStart = endIdx
    }
    
    return attributed
}

struct SettingsContainer<Content: View>: View {
    let tab: SettingsTab
    let content: () -> Content
    @EnvironmentObject var navigationState: SettingsNavigationState
        
    init(_ tab: SettingsTab, @ViewBuilder content: @escaping () -> Content) {
        self.tab = tab
        self.content = content
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content()
                    .padding(16)
            }
            .environment(\.settingsTab, tab)
            .onChange(of: navigationState.scrollToItemID) { id in
                if let id = id {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .center)
                        }
                        DispatchQueue.main.async {
                            navigationState.scrollToItemID = nil
                        }
                    }
                }
            }
        }
    }
}

struct SettingsRow<Content: View>: View {
    let title: LocalizedStringResource
    let content: Content
    let helperText: LocalizedStringKey?
    let warningText: LocalizedStringKey?
    let demoVideoName: String?
    
    @AppStorage("ShowDemoVideos") private var showDemoVideos = true
    @Environment(\.settingsTab) var currentTab
    @Environment(\.isSettingsPreRendering) private var isPreRendering
    @EnvironmentObject var navigationState: SettingsNavigationState

    init(
        _ title: LocalizedStringResource,
        helperText: LocalizedStringKey? = nil,
        warningText: LocalizedStringKey? = nil,
        demoVideoName: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.helperText = helperText
        self.warningText = warningText
        self.demoVideoName = demoVideoName
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Text(highlightedText(text: String(localized: title), query: navigationState.searchText))
                        .frame(alignment: .leading)

                    if let helperText = helperText {
                        HelperInfoButton(text: helperText)
                    }

                    if let warningText = warningText {
                        WarningInfoButton(text: warningText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                content
                    .frame(alignment: .trailing)
            }

            if showDemoVideos,
               let videoName = demoVideoName,
               let videoURL = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
                LoopVideoPlayerView(videoURL: videoURL)
                    .frame(height: 180)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .id(title.key)
        .onAppear {
            navigationState.register(title: title.key, tab: currentTab)
        }
        .onDisappear {
            if !isPreRendering {
                navigationState.unregister(title: title.key, tab: currentTab)
            }
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey?
    let helperText: LocalizedStringKey?
    let content: Content

    init(
        _ title: LocalizedStringKey? = nil, helperText: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.helperText = helperText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.headline)

                    if let helperText = helperText {
                        HelperInfoButton(text: helperText)
                    }
                }
                .padding(.leading, 4)
            }

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.regularMaterial)
                    )
            )
        }
        .padding(.top, title == nil ? -10 : 0)
    }

    private var backgroundColor: Color {
        let nsColor = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 0.20, alpha: 1.0)
            } else {
                return NSColor(calibratedWhite: 1.00, alpha: 1.0)
            }
        }
        return Color(nsColor: nsColor)
    }
}

struct HelperInfoButton: View {
    let text: LocalizedStringKey
    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(15)
            .frame(minWidth: 200, maxWidth: 300)
        }
    }
}

struct WarningInfoButton: View {
    let text: LocalizedStringKey
    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.yellow)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(15)
            .frame(minWidth: 200, maxWidth: 300)
        }
    }
}
