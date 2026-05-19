import SwiftUI
import AVKit
import AVFoundation

class LoopVideoPlayerNSView: NSView {
    var playerLayer: AVPlayerLayer {
        self.layer as! AVPlayerLayer
    }
    
    override func makeBackingLayer() -> CALayer {
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.clear.cgColor
        return layer
    }
    
    func setupPlayer(with url: URL, coordinator: LoopVideoPlayerView.Coordinator) {
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
        
        let player = AVQueuePlayer()
        let playerItem = AVPlayerItem(url: url)
        let playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
        
        self.playerLayer.player = player
        player.isMuted = true
        player.play()
        
        coordinator.looper = playerLooper
        coordinator.player = player
    }
    
    override func scrollWheel(with event: NSEvent) {
        self.nextResponder?.scrollWheel(with: event)
    }
}

struct LoopVideoPlayerView: NSViewRepresentable {
    let videoURL: URL
    
    func makeNSView(context: Context) -> LoopVideoPlayerNSView {
        let view = LoopVideoPlayerNSView()
        view.setupPlayer(with: videoURL, coordinator: context.coordinator)
        return view
    }
    
    func updateNSView(_ nsView: LoopVideoPlayerNSView, context: Context) {}
    
    static func dismantleNSView(_ nsView: LoopVideoPlayerNSView, coordinator: Coordinator) {
        coordinator.player?.pause()
        coordinator.player?.removeAllItems()
        coordinator.looper = nil
        coordinator.player = nil
        nsView.playerLayer.player = nil
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var looper: AVPlayerLooper?
        var player: AVQueuePlayer?
    }
}

struct SettingsTabKey: EnvironmentKey {
    static let defaultValue: SettingsTab = .general
}

extension EnvironmentValues {
    var settingsTab: SettingsTab {
        get { self[SettingsTabKey.self] }
        set { self[SettingsTabKey.self] }
    }
}

struct SearchableSettingItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let localizedTitle: String
    let tab: SettingsTab
    let keywords: [String]
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(tab)
    }
    
    static func == (lhs: SearchableSettingItem, rhs: SearchableSettingItem) -> Bool {
        lhs.title == rhs.title && lhs.tab == rhs.tab
    }
}

class SettingsNavigationState: ObservableObject {
    @Published var scrollToItemID: String? = nil
    @Published var searchText: String = ""
    @Published var registeredItems: [SearchableSettingItem] = []
    
    func register(title: String, tab: SettingsTab, keywords: [String] = []) {
        let localizedTitle = NSLocalizedString(title, comment: "")
        
        // Avoid duplicate registrations
        guard !registeredItems.contains(where: { $0.title == title }) else { return }
        
        var generatedKeywords = keywords.map { $0.lowercased() }
        
        let titleWords = localizedTitle.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 1 }
        generatedKeywords.append(contentsOf: titleWords)
        
        let keyWords = title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 1 }
        generatedKeywords.append(contentsOf: keyWords)
        
        let uniqueKeywords = Array(Set(generatedKeywords))
        
        let item = SearchableSettingItem(
            title: title,
            localizedTitle: localizedTitle,
            tab: tab,
            keywords: uniqueKeywords
        )
        
        DispatchQueue.main.async {
            self.registeredItems.append(item)
        }
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
    let content: Content
    @EnvironmentObject var navigationState: SettingsNavigationState
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .padding(20)
            }
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
    let title: String
    let content: Content
    let helperText: LocalizedStringKey?
    let warningText: LocalizedStringKey?
    let demoVideoName: String?
    
    @Environment(\.settingsTab) var currentTab
    @EnvironmentObject var navigationState: SettingsNavigationState

    init(
        _ title: String,
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
                    Text(highlightedText(text: NSLocalizedString(title, comment: ""), query: navigationState.searchText))
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
            
            if let videoName = demoVideoName,
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
        .id(title)
        .onAppear {
            navigationState.register(title: title, tab: currentTab)
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

private struct WarningInfoButton: View {
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

struct SliderSettingsRow<V>: View where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
    let title: String
    @Binding var value: V
    let range: ClosedRange<V>
    let defaultValue: V
    let step: V?
    let helperText: LocalizedStringKey?
    let warningText: LocalizedStringKey?
    let demoVideoName: String?
    let valueString: (V) -> String
    
    @Environment(\.settingsTab) var currentTab
    @EnvironmentObject var navigationState: SettingsNavigationState

    init(
        _ title: String,
        helperText: LocalizedStringKey? = nil,
        warningText: LocalizedStringKey? = nil,
        demoVideoName: String? = nil,
        value: Binding<V>,
        range: ClosedRange<V>,
        defaultValue: V,
        step: V? = nil,
        valueString: @escaping (V) -> String = { String(format: "%.2f", Double($0)) }
    ) {
        self.title = title
        self.helperText = helperText
        self.warningText = warningText
        self.demoVideoName = demoVideoName
        self._value = value
        self.range = range
        self.defaultValue = defaultValue
        self.step = step
        self.valueString = valueString
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Text(highlightedText(text: NSLocalizedString(title, comment: ""), query: navigationState.searchText))
                    if let helperText = helperText {
                        HelperInfoButton(text: helperText)
                    }
                    if let warningText = warningText {
                        WarningInfoButton(text: warningText)
                    }
                }

                Spacer()

                Button("↺") {
                    withAnimation {
                        value = defaultValue
                    }
                }
                .help("Reset to default")
                .disabled(value == defaultValue)
            }

            HStack {
                if let step = step {
                    Slider(value: $value, in: range, step: V.Stride(step))
                } else {
                    Slider(value: $value, in: range)
                }

                Text(valueString(value))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .frame(minWidth: 50, alignment: .trailing)
            }
            
            if let videoName = demoVideoName,
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
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .id(title)
        .onAppear {
            navigationState.register(title: title, tab: currentTab)
        }
    }
}
