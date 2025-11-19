import SwiftUI
import ServiceManagement
import Combine

enum SettingsTab: String {
    case general, space, about
}

let defaultSettingsWindowWidth = 417
let defaultSettingsWindowHeight = 480

struct SettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    @AppStorage("selectedSettingsTab") private var selectedTab: SettingsTab = .general
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(spaceManager: spaceManager, labelManager: labelManager)
                .tabItem {
                    Image(systemName: "gearshape")
                    Text(NSLocalizedString("Settings.General", comment: ""))
                }
                .tag(SettingsTab.general)
            
            SpaceEditView(spaceManager: spaceManager, labelManager: labelManager)
                .tabItem {
                    Image(systemName: "macwindow.stack")
                    Text(NSLocalizedString("Settings.Spaces", comment: ""))
                }
                .tag(SettingsTab.space)
            
            AboutView()
                .tabItem {
                    Image(systemName: "info.circle")
                    Text(NSLocalizedString("Settings.About", comment: ""))
                }
                .tag(SettingsTab.about)
        }
        .frame(width: CGFloat(defaultSettingsWindowWidth), height: CGFloat(defaultSettingsWindowHeight))
        .padding()
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
