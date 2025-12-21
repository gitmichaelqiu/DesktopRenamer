import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, labels, space, about
    
    var id: String { self.rawValue }
    
    var localizedName: LocalizedStringKey {
        switch self {
        case .general: return "Settings.General"
        case .labels: return "Settings.Labels"
        case .space: return "Settings.Spaces"
        case .about: return "Settings.About"
        }
    }
    
    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .labels: return "tag"
        case .space: return "macwindow"
        case .about: return "info.circle"
        }
    }
}

// Layout Constants
let sidebarWidth: CGFloat = 180
let defaultSettingsWindowWidth = 750
let defaultSettingsWindowHeight = 550
let sidebarRowHeight: CGFloat = 32
let sidebarFontSize: CGFloat = 15

// Tighter Header Height
let titleHeaderHeight: CGFloat = 48

struct SettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    
    @State private var selectedTab: SettingsTab? = .general
    
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .windowToolbar)
        .edgesIgnoringSafeArea(.top)
        .frame(width: CGFloat(defaultSettingsWindowWidth), height: CGFloat(defaultSettingsWindowHeight))
    }
    
    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selectedTab) {
            Section {
                ForEach(SettingsTab.allCases) { tab in
                    sidebarItem(for: tab)
                }
            } header: {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 35)
                    
                    Text("Desktop")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("Renamer")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.bottom, 10)
                        // .padding(.leading, 8)
                }
            }
            .collapsible(false)
        }
        .scrollDisabled(true)
        .navigationSplitViewColumnWidth(sidebarWidth)
        .listStyle(.sidebar)
        .edgesIgnoringSafeArea(.top)
    }
    
    @ViewBuilder
    private var detailView: some View {
        ZStack(alignment: .top) {
            
            // 1. CONTENT LAYER
            ZStack(alignment: .top) {
                if let tab = selectedTab {
                    switch tab {
                    case .general:
                        GeneralSettingsView(spaceManager: spaceManager, labelManager: labelManager)
                    case .labels:
                        LabelSettingsView(labelManager: labelManager)
                    case .space:
                        SpaceEditView(spaceManager: spaceManager, labelManager: labelManager)
                    case .about:
                        AboutView()
                    }
                } else {
                    Text("Select a category")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Match the header height exactly
            .padding(.top, titleHeaderHeight)
            // OPTIONAL: Pull content up slightly if the gap is still too large due to internal Form padding
            // .padding(.top, -10)
            
            // 2. HEADER LAYER (Blurry Title Bar)
            if let tab = selectedTab {
                VStack(spacing: 0) {
                    HStack {
                        Text(tab.localizedName)
                            .font(.system(size: 20, weight: .semibold))
                            .padding(.leading, 20)
                        Spacer()
                    }
                    .frame(height: titleHeaderHeight) // 48pt
                    .background(.bar)
                    
                    Divider()
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .edgesIgnoringSafeArea(.top)
    }
    
    @ViewBuilder
    private func sidebarItem(for tab: SettingsTab) -> some View {
        NavigationLink(value: tab) {
            Label {
                Text(tab.localizedName)
                    .font(.system(size: sidebarFontSize))
                    .padding(.leading, 2)
            } icon: {
                Image(systemName: tab.iconName)
            }
        }
        .frame(height: sidebarRowHeight)
    }
}

class SettingsHostingController: NSHostingController<SettingsView> {
    private let spaceManager: SpaceManager
    private let labelManager: SpaceLabelManager
    
    init(spaceManager: SpaceManager, labelManager: SpaceLabelManager) {
        self.spaceManager = spaceManager
        self.labelManager = labelManager
        super.init(rootView: SettingsView(spaceManager: spaceManager, labelManager: labelManager))
    }
    
    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.preferredContentSize = NSSize(width: defaultSettingsWindowWidth, height: defaultSettingsWindowHeight)
    }
}
