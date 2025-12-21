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

let sidebarWidth: CGFloat = 220
let defaultSettingsWindowWidth = 800
let defaultSettingsWindowHeight = 550

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
                Color.clear.frame(height: 40)
                // Ice Style Header: No spacers needed, Section Header handles layout
                Text("DesktopRenamer")
                    .font(.system(size: 18, weight: .semibold)) // Slightly smaller/bolder to match macOS standard
                    .foregroundStyle(.primary)
                    .padding(.vertical, 8) // Small vertical breathing room
            }
            .collapsible(false)
        }
        .scrollDisabled(true)
        .navigationSplitViewColumnWidth(sidebarWidth)
        .listStyle(.sidebar)
        // Ensure sidebar extends to top edge behind traffic lights
        .edgesIgnoringSafeArea(.top)
    }
    
    @ViewBuilder
    private var detailView: some View {
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // FIX: This pulls the content up, ignoring the "Ghost" Title Bar space
        .edgesIgnoringSafeArea(.top)
    }
    
    @ViewBuilder
    private func sidebarItem(for tab: SettingsTab) -> some View {
        NavigationLink(value: tab) {
            Label {
                Text(tab.localizedName)
                    .padding(.leading, 2)
            } icon: {
                Image(systemName: tab.iconName)
            }
        }
        .frame(height: 30)
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
