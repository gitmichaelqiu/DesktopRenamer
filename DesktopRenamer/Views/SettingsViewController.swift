import SwiftUI
import ServiceManagement
import Combine

let defaultSettingsWindowWidth = 450
let defaultSettingsWindowHeight = 450

// MARK: - Main Settings View
struct SettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    @AppStorage("selectedSettingsTab") private var selectedTab: Int = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(spaceManager: spaceManager, labelManager: labelManager)
                .tabItem {
                    Image(systemName: "gearshape")
                    Text(NSLocalizedString("Settings.Tab.General", comment: ""))
                }
                .tag(0)
            
            SpaceEditView(spaceManager: spaceManager, labelManager: labelManager)
                .tabItem {
                    Image(systemName: "macwindow.stack")
                    Text(NSLocalizedString("Settings.Tab.Space", comment: ""))
                }
                .tag(1)
            
            AboutView()
                .tabItem {
                    Image(systemName: "info.circle")
                    Text(NSLocalizedString("Settings.Tab.About", comment: ""))
                }
                .tag(2)
        }
        .frame(width: 450, height: 450)
        .padding()
        .onAppear {
            if let savedTab = UserDefaults.standard.object(forKey: "selectedSettingsTab") as? Int {
                selectedTab = savedTab
            }
        }
    }
}

// MARK: - SwiftUI Hosting Controller
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
        self.preferredContentSize = NSSize(width: 450, height: 450)
    }
}
