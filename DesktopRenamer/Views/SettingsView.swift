import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, space, labels, sswitch, permissions, about

    var id: String { self.rawValue }

    var localizedNameKey: String {
        switch self {
        case .general: return "Settings.General"
        case .space: return "Settings.Spaces"
        case .labels: return "Settings.Labels"
        case .sswitch: return "Settings.Switch"
        case .permissions: return "Permissions"
        case .about: return "Settings.About"
        }
    }

    var localizedName: LocalizedStringKey {
        LocalizedStringKey(localizedNameKey)
    }
    

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .space: return "macwindow"
        case .labels: return "tag"
        case .sswitch: return "arrow.left.and.right.square"
        case .permissions: return "lock.shield"
        case .about: return "info.circle"
        }
    }
}

// UI layout constants for consistent sizing.
let sidebarWidth: CGFloat = 180
let defaultSettingsWindowWidth = 750
let defaultSettingsWindowHeight = 550
let sidebarRowHeight: CGFloat = 32
let sidebarFontSize: CGFloat = 16

// Tighter Header Height
let titleHeaderHeight: CGFloat = 48

struct SettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var gestureManager: GestureManager

    @StateObject private var navigationState = SettingsNavigationState()
    @State private var selectedTab: SettingsTab?
    @State private var searchText = ""
    
    init(spaceManager: SpaceManager, labelManager: SpaceLabelManager, initialTab: SettingsTab? = .general) {
        self.spaceManager = spaceManager
        self.labelManager = labelManager
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                sidebar
            } detail: {
                detailView
            }
            
            // Pre-render settings views off-screen in the active root hierarchy to index them
            ZStack {
                GeneralSettingsView(spaceManager: spaceManager, labelManager: labelManager)
                    .environment(\.settingsTab, .general)
                SpaceEditView(spaceManager: spaceManager)
                    .environment(\.settingsTab, .space)
                LabelSettingsView(labelManager: labelManager)
                    .environment(\.settingsTab, .labels)
                SwitchSettingsView()
                    .environment(\.settingsTab, .sswitch)
                PermissionsSettingsView()
                    .environment(\.settingsTab, .permissions)
                AboutView()
                    .environment(\.settingsTab, .about)
            }
            .environmentObject(navigationState)
            .environment(\.isSettingsPreRendering, true)
            .frame(width: CGFloat(defaultSettingsWindowWidth), height: CGFloat(defaultSettingsWindowHeight))
            .opacity(0.001)
            .allowsHitTesting(false)
        }
        .environmentObject(navigationState)
        .navigationTitle("")
        .modifier(ToolbarHider())
        .edgesIgnoringSafeArea(.top)
        .frame(
            width: CGFloat(defaultSettingsWindowWidth), height: CGFloat(defaultSettingsWindowHeight)
        )
        .onChange(of: searchText) { newValue in
            navigationState.searchText = newValue
            if !newValue.isEmpty {
                let tabs = filteredTabs
                if let selected = selectedTab, !tabs.contains(selected) {
                    selectedTab = tabs.first
                } else if selectedTab == nil {
                    selectedTab = tabs.first
                }
            }
        }
    }

    private struct ToolbarHider: ViewModifier {
        func body(content: Content) -> some View {
            if #available(macOS 14.0, *) {
                content.toolbar(.hidden, for: .windowToolbar)
            } else {
                content
            }
        }
    }

    var filteredTabs: [SettingsTab] {
        if searchText.isEmpty {
            return SettingsTab.allCases
        }
        let query = searchText.lowercased()
        return SettingsTab.allCases.filter { tab in
            let matchesTabName = tab.rawValue.lowercased().contains(query) ||
                                 NSLocalizedString(tab.localizedNameKey, comment: "").lowercased().contains(query)
            
            let matchesSetting = navigationState.registeredItems.contains { item in
                item.tab == tab && (
                    item.title.lowercased().contains(query) ||
                    item.localizedTitle.lowercased().contains(query) ||
                    item.keywords.contains { $0.lowercased().contains(query) }
                )
            }
            
            return matchesTabName || matchesSetting
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 13))
            
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.leading, -4)
        .padding(.trailing, 10)
    }

    @ViewBuilder
    private func sidebarContent(titleSize: CGFloat, spacing: CGFloat) -> some View {
        Section {
            if filteredTabs.isEmpty {
                Text("No results")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
                    .padding(.top, 4)
            } else {
                ForEach(filteredTabs) { tab in
                    VStack(alignment: .leading, spacing: 2) {
                        sidebarItem(for: tab)
                        
                        if !searchText.isEmpty {
                            let matchingItems = navigationState.registeredItems.filter { item in
                                item.tab == tab && (
                                    item.title.lowercased().contains(searchText.lowercased()) ||
                                    item.localizedTitle.lowercased().contains(searchText.lowercased()) ||
                                    item.keywords.contains { $0.lowercased().contains(searchText.lowercased()) }
                                )
                            }
                            
                            ForEach(matchingItems) { item in
                                Button {
                                    selectedTab = tab
                                    navigationState.scrollToItemID = item.title
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.turn.down.right")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .padding(.leading, 12)
                                        
                                        Text(highlightedText(text: item.localizedTitle, query: searchText, color: nil))
                                            .font(.system(size: 11, weight: .regular))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .frame(height: 18)
                            }
                        }
                    }
                    .tag(tab)
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: spacing) {
                Color.clear.frame(height: 45)
                Text("Desktop").font(.custom("Syncopate-Bold", size: titleSize)).foregroundStyle(
                    .primary)
                Text("Renamer").font(.custom("Syncopate-Bold", size: titleSize)).foregroundStyle(
                    .primary
                ).padding(.bottom, 10)
                
                searchField
                    .padding(.bottom, 12)
            }
        }
        .collapsible(false)
    }

    @ViewBuilder
    private var sidebar: some View {
        if #available(macOS 14.0, *) {
            List(selection: $selectedTab) {
                sidebarContent(titleSize: 21, spacing: 2)
            }
            .scrollDisabled(true)
            .removeSidebarToggle()
            .navigationSplitViewColumnWidth(
                min: sidebarWidth, ideal: sidebarWidth, max: sidebarWidth
            )
            .edgesIgnoringSafeArea(.top)
        } else {
            List(selection: $selectedTab) {
                sidebarContent(titleSize: 18, spacing: 0)
            }
            .scrollDisabled(true)
            .navigationSplitViewColumnWidth(
                min: sidebarWidth, ideal: sidebarWidth, max: sidebarWidth
            )
            .edgesIgnoringSafeArea(.top)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        let activeTab = selectedTab ?? filteredTabs.first ?? .general
        
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                switch activeTab {
                case .general:
                    GeneralSettingsView(spaceManager: spaceManager, labelManager: labelManager)
                case .space:
                    SpaceEditView(spaceManager: spaceManager)
                case .labels:
                    LabelSettingsView(labelManager: labelManager)
                case .sswitch:
                    SwitchSettingsView()
                case .permissions:
                    PermissionsSettingsView()
                case .about:
                    AboutView()
                }
            }
            .environmentObject(navigationState)
            .environment(\.settingsTab, activeTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, titleHeaderHeight)

            VStack(spacing: 0) {
                HStack {
                    Text(activeTab.localizedName).font(.system(size: 20, weight: .semibold)).padding(
                        .leading, 20)
                    Spacer()
                }
                .frame(height: titleHeaderHeight)
                .background(.bar)
                Divider()
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .edgesIgnoringSafeArea(.top)
    }

    @ViewBuilder
    private func sidebarItem(for tab: SettingsTab) -> some View {
        NavigationLink(value: tab) {
            Label {
                Text(tab.localizedName)
                    .font(.system(size: sidebarFontSize, weight: .medium))
                    .padding(.leading, 2)
            } icon: {
                Image(systemName: tab.iconName).resizable().scaledToFit().frame(
                    height: sidebarRowHeight - 15)
            }
        }
        .frame(height: sidebarRowHeight)
    }
}

class SettingsHostingController: NSHostingController<AnyView> {
    private let spaceManager: SpaceManager
    private let labelManager: SpaceLabelManager
    private let hotkeyManager: HotkeyManager
    private let gestureManager: GestureManager

    // Integrates SwiftUI settings with the application logic.
    init(
        spaceManager: SpaceManager, labelManager: SpaceLabelManager, hotkeyManager: HotkeyManager,
        gestureManager: GestureManager, initialTab: SettingsTab? = .general
    ) {
        self.spaceManager = spaceManager
        self.labelManager = labelManager
        self.hotkeyManager = hotkeyManager
        self.gestureManager = gestureManager
 
        let rootView = SettingsView(spaceManager: spaceManager, labelManager: labelManager, initialTab: initialTab)
            .environmentObject(hotkeyManager)
            .environmentObject(gestureManager)
            .environmentObject(spaceManager)
            .environmentObject(labelManager)
 
        super.init(rootView: AnyView(rootView))
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.preferredContentSize = NSSize(
            width: defaultSettingsWindowWidth, height: defaultSettingsWindowHeight)
    }
}
