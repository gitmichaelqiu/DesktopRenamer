import SwiftUI
import ServiceManagement
import Combine

// MARK: - About View
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // App icon
                if let icon = NSApplication.shared.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .cornerRadius(10)
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
                
                // App name
                Text(NSLocalizedString("About.AppName", comment: ""))
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)
                
                // Version
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text("v\(version)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                // Description
                Text(NSLocalizedString("About.Description", comment: ""))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                // GitHub link
                Button(action: openGitHub) {
                    Text(NSLocalizedString("About.GithubLink", comment: ""))
                        .font(.system(size: 13))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                // Copyright
                let year = Calendar.current.component(.year, from: Date())
                let copyrightString = String(format: NSLocalizedString("About.Copyright", comment: ""), year)
                Text(copyrightString)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func openGitHub() {
        if let url = URL(string: "https://github.com/gitmichaelqiu/DesktopRenamer") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - General Settings View
struct GeneralSettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    @State private var launchAtLogin: Bool = false
    @State private var showLabels: Bool = false
    @State private var autoCheckUpdate: Bool = UpdateManager.isAutoCheckEnabled
    @State private var isResetting: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Launch at login toggle
                Toggle(NSLocalizedString("Settings.LaunchAtLogin", comment: ""), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { value in
                        toggleLaunchAtLogin(value)
                    }
                
                // Auto Check for Update toggle
                Toggle(NSLocalizedString("Settings.AutoCheckUpdate", comment: ""), isOn: $autoCheckUpdate)
                    .onChange(of: autoCheckUpdate) { value in
                        UpdateManager.isAutoCheckEnabled = value
                    }
                
                Spacer().frame(height: 20)
                
                // Reset names button
                Button(NSLocalizedString("Settings.ResetButton", comment: "")) {
                    resetNames()
                }
                .disabled(isResetting)
                
                // Check for Update button
                Button(NSLocalizedString("Settings.CheckUpdateButton", comment: "")) {
                    checkForUpdate()
                }
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            launchAtLogin = getLaunchAtLoginState()
            showLabels = labelManager.isEnabled
        }
    }
    
    private func getLaunchAtLoginState() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            let bundleId = Bundle.main.bundleIdentifier ?? ""
            return SMLoginItemSetEnabled(bundleId as CFString, true)
        }
    }
    
    private func toggleLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                let service = SMAppService.mainApp
                if service.status == .enabled {
                    try service.unregister()
                } else {
                    try service.register()
                }
            } catch {
                print("Failed to toggle launch at login: \(error)")
                launchAtLogin = getLaunchAtLoginState()
            }
        } else {
            if let bundleId = Bundle.main.bundleIdentifier {
                let success = SMLoginItemSetEnabled(bundleId as CFString, enabled)
                if !success {
                    launchAtLogin = getLaunchAtLoginState()
                }
            }
        }
    }
    
    private func checkForUpdate() {
        UpdateManager.shared.checkForUpdate(from: nil, suppressUpToDateAlert: false)
    }
    
    private func resetNames() {
        isResetting = true
        
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Settings.ResetAlertMsg", comment: "")
        alert.informativeText = NSLocalizedString("Settings.ResetAlertInfo", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Settings.ResetAlertButtonReset", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Settings.ResetAlertButtonCancel", comment: ""))
        
        let response = alert.runModal()
        
        DispatchQueue.main.async {
            self.isResetting = false
            
            if response == .alertFirstButtonReturn {
                self.spaceManager.resetAllNames()
            }
        }
    }
}

// MARK: - Space Edit View
struct SpaceEditView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    @State private var desktopSpaces: [DesktopSpace] = []
    
    var body: some View {
        VStack {
            if desktopSpaces.isEmpty {
                Text("No spaces available")
                    .foregroundColor(.secondary)
            } else {
                Table(desktopSpaces) {
                    TableColumn("#") { space in
                        Text(spaceManager.currentSpaceUUID == space.id ? "[\(space.num)]" : "\(space.num)")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .width(30)
                    
                    TableColumn(NSLocalizedString("Settings.Space.CustomName", comment: "")) { space in
                        TextField(
                            String(format: NSLocalizedString("Space.DefaultName", comment: ""), space.num),
                            text: Binding(
                                get: { space.customName },
                                set: { newValue in
                                    updateSpaceName(space, newValue)
                                }
                            )
                        )
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    .width(240)
                    
                    TableColumn(NSLocalizedString("Settings.Space.Actions", comment: "")) { space in
                        HStack(spacing: 4) {
                            Button("↑") {
                                moveRowUp(space)
                            }
                            .disabled(isFirstRow(space) || space.id == spaceManager.currentSpaceUUID)
                            
                            Button("↓") {
                                moveRowDown(space)
                            }
                            .disabled(isLastRow(space) || space.id == spaceManager.currentSpaceUUID)
                            
                            Button("⌫") {
                                deleteRow(space)
                            }
                            .disabled(space.id == spaceManager.currentSpaceUUID)
                            .help(space.id == spaceManager.currentSpaceUUID ?
                                  NSLocalizedString("settings.space.cannot_delete_current", comment: "Cannot delete current space") : "")
                        }
                        .buttonStyle(.bordered)
                    }
                    .width(85)
                }
                .tableStyle(.bordered)
            }
        }
        .padding()
        .onAppear {
            refreshData()
        }
        .onReceive(spaceManager.$spaceNameDict) { _ in
            refreshData()
        }
        .onReceive(spaceManager.$currentSpaceUUID) { _ in
            refreshData()
        }
    }
    
    private func refreshData() {
        desktopSpaces = spaceManager.spaceNameDict.sorted { $0.num < $1.num }
    }
    
    private func isFirstRow(_ space: DesktopSpace) -> Bool {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }) else { return true }
        return index == 0
    }
    
    private func isLastRow(_ space: DesktopSpace) -> Bool {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }) else { return true }
        return index == desktopSpaces.count - 1
    }
    
    private func moveRowUp(_ space: DesktopSpace) {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }),
              index > 0 else { return }
        
        desktopSpaces.swapAt(index, index - 1)
        updateNumbersAndSave()
    }
    
    private func moveRowDown(_ space: DesktopSpace) {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }),
              index < desktopSpaces.count - 1 else { return }
        
        desktopSpaces.swapAt(index, index + 1)
        updateNumbersAndSave()
    }
    
    private func deleteRow(_ space: DesktopSpace) {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }),
              space.id != spaceManager.currentSpaceUUID else { return }
        
        desktopSpaces.remove(at: index)
        updateNumbersAndSave()
    }
    
    private func updateSpaceName(_ space: DesktopSpace, _ newName: String) {
        guard let index = desktopSpaces.firstIndex(where: { $0.id == space.id }) else { return }
        
        var updatedSpace = desktopSpaces[index]
        updatedSpace.customName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        desktopSpaces[index] = updatedSpace
        
        spaceManager.spaceNameDict = desktopSpaces
        spaceManager.saveSpaces()
    }
    
    private func updateNumbersAndSave() {
        // Reindex
        for (index, _) in desktopSpaces.enumerated() {
            desktopSpaces[index].num = index + 1
        }
        
        // Sync back to spaceManager
        spaceManager.spaceNameDict = desktopSpaces
        spaceManager.currentTotalSpace = desktopSpaces.count
        spaceManager.saveSpaces()
    }
}

// MARK: - Main Settings View
struct SettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    @State private var selectedTab = 0
    
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
        .frame(width: 600, height: 400)
        .padding()
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
        self.preferredContentSize = NSSize(width: 600, height: 400)
    }
}
