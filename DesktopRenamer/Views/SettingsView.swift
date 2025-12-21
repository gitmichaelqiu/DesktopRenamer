import SwiftUI

// Enum remains the same
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

// Updated constants
let sidebarWidth: CGFloat = 220
let defaultSettingsWindowWidth = 750
let defaultSettingsWindowHeight = 550

struct SettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    
    @State private var selectedTab: SettingsTab? = .general
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                // HEADER SECTION (Traffic Lights + Title)
                Section {
                    EmptyView()
                } header: {
                    VStack(alignment: .leading, spacing: 0) {
                        // 1. Spacer to push content below traffic lights (approx 40pt)
                        Color.clear
                            .frame(height: 38)
                        
                        Text("Desktop")
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("Renamer")
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(.primary)
//                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                    }
                    // Remove default header padding to align with edge
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                .collapsible(false)
                
                // TAB ITEMS
                Section {
                    ForEach(SettingsTab.allCases) { tab in
                        sidebarItem(for: tab)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollDisabled(true)
            .navigationSplitViewColumnWidth(sidebarWidth)
            
            // 2. CRITICAL: Force Sidebar to top edge of window
            .edgesIgnoringSafeArea(.top)
            
        } detail: {
            ZStack {
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
            // 3. CRITICAL: Push Detail view down so it doesn't sit under the toolbar area
            //    (Since we removed the toolbar, the content might ride up too high otherwise)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("")
        // 4. HIDE TOOLBARS explicitly to prevent SwiftUI from reserving space
        .toolbar(.hidden, for: .windowToolbar)
        .frame(width: CGFloat(defaultSettingsWindowWidth), height: CGFloat(defaultSettingsWindowHeight))
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
        // Use default height, no fixed frame needed
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
