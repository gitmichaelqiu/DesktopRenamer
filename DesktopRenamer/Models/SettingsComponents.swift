import SwiftUI
import AVKit
import AVFoundation
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
    
    private var registeredTitlesCounts = [String: Int]()
    
    private func extractKeywords(from string: String) -> [String] {
        string.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 1 }
    }
    
    func register(title: String, tab: SettingsTab, keywords: [String] = []) {
        let registrationKey = "\(title)-\(tab.rawValue)"
        let count = registeredTitlesCounts[registrationKey] ?? 0
        registeredTitlesCounts[registrationKey] = count + 1
        
        guard count == 0 else { return }
        
        let localizedTitle = NSLocalizedString(title, comment: "")
        var generatedKeywords = keywords.map { $0.lowercased() }
        
        generatedKeywords.append(contentsOf: extractKeywords(from: localizedTitle))
        generatedKeywords.append(contentsOf: extractKeywords(from: title))
        
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
    
    func unregister(title: String, tab: SettingsTab) {
        let registrationKey = "\(title)-\(tab.rawValue)"
        let count = registeredTitlesCounts[registrationKey] ?? 0
        
        if count <= 1 {
            registeredTitlesCounts[registrationKey] = nil
            DispatchQueue.main.async {
                self.registeredItems.removeAll { $0.title == title && $0.tab == tab }
            }
        } else {
            registeredTitlesCounts[registrationKey] = count - 1
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
    let requirements: [SettingsRequirement]
    let demoVideoName: String?
    
    @AppStorage("ShowDemoVideos") private var showDemoVideos = true
    @Environment(\.settingsTab) var currentTab
    @Environment(\.isSettingsPreRendering) private var isPreRendering
    @EnvironmentObject var navigationState: SettingsNavigationState

    init(
        _ title: LocalizedStringResource,
        helperText: LocalizedStringKey? = nil,
        warningText: LocalizedStringKey? = nil,
        requirements: [SettingsRequirement] = [],
        demoVideoName: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.helperText = helperText
        self.warningText = warningText
        self.requirements = requirements
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

                    SettingsRequirementWarning(requirements: requirements)
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

struct SettingsRequirement: Identifiable {
    let name: String
    let isSatisfied: Bool

    var id: String { name }

    static func accessibility(isGranted: Bool) -> Self {
        Self(name: "Accessibility permission", isSatisfied: isGranted)
    }

    static func accessibilityEventPosting(isGranted: Bool) -> Self {
        Self(name: "Accessibility permission", isSatisfied: isGranted)
    }

    static func screenRecording(isGranted: Bool) -> Self {
        Self(name: "Screen Recording permission", isSatisfied: isGranted)
    }

    static func spaceAPI(isAvailable: Bool) -> Self {
        Self(name: "SpaceAPI", isSatisfied: isAvailable)
    }
}

struct SettingsRequirementWarning: View {
    let requirements: [SettingsRequirement]

    private var missingRequirements: [SettingsRequirement] {
        var seenNames = Set<String>()
        return requirements.filter { requirement in
            !requirement.isSatisfied && seenNames.insert(requirement.name).inserted
        }
    }

    private var warningText: LocalizedStringKey {
        LocalizedStringKey("Requires \(missingRequirements.map(\.name).joined(separator: ", ")).")
    }

    var body: some View {
        if !missingRequirements.isEmpty {
            WarningInfoButton(text: warningText)
        }
    }
}

enum SettingsSectionStyle {
    static var dragPreviewBackgroundColor: Color {
        Color(nsColor: .underPageBackgroundColor)
    }

    static var backgroundColor: Color {
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
                    .fill(SettingsSectionStyle.backgroundColor.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.regularMaterial)
                    )
            )
        }
        .padding(.top, title == nil ? -10 : 0)
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
