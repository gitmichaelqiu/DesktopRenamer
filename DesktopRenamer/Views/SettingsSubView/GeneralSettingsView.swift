import SwiftUI
import ServiceManagement

class APITester: ObservableObject {
    @Published var responseText: String = ""
    
    init() {
        // LISTEN to Local Notification Center
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCurrentSpaceResponse(_:)),
            name: SpaceAPI.returnActiveSpace,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAllSpacesResponse(_:)),
            name: SpaceAPI.returnSpaceList,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func sendCurrentSpaceRequest() {
        responseText = "Requesting current space..."
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.getActiveSpace,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
    
    func sendAllSpacesRequest() {
        responseText = "Requesting all spaces..."
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.getSpaceList,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
    
    @objc private func handleCurrentSpaceResponse(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let userInfo = notification.userInfo else {
                self.responseText = "Received empty response"
                return
            }
            
            let name = userInfo["spaceName"] as? String ?? "N/A"
            let num = (userInfo["spaceNumber"] as? NSNumber)?.intValue ?? (userInfo["spaceNumber"] as? Int) ?? -1
            let uuid = userInfo["spaceUUID"] as? String ?? "N/A"
            
            self.responseText = "Current Space:\nName: \(name)\n#: \(num)\nUUID: \(uuid)"
        }
    }
    
    @objc private func handleAllSpacesResponse(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let userInfo = notification.userInfo,
                  let spaces = userInfo["spaces"] as? [[String: Any]] else {
                self.responseText = "Received empty space list"
                return
            }
            
            var result = "All Spaces (\(spaces.count)):\n"
            
            for space in spaces {
                let name = space["spaceName"] as? String ?? "N/A"
                let num = (space["spaceNumber"] as? NSNumber)?.intValue ?? -1
                // Truncate UUID for display
                let uuid = (space["spaceUUID"] as? String)?.prefix(8) ?? "N/A"
                
                result += "#\(num): \(name) [\(uuid).. ]\n"
            }
            
            self.responseText = result
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    
    @StateObject private var apiTester = APITester()
    
    @State private var launchAtLogin: Bool = false
    @State private var autoCheckUpdate: Bool = UpdateManager.isAutoCheckEnabled
    @State private var isResetting: Bool = false
    @State private var isAPIEnabled: Bool = SpaceManager.isAPIEnabled
    @State private var isStableEnabled: Bool = SpaceManager.isStableEnabled
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Settings.General.General") {
                    SettingsRow("Settings.General.General.ShowLabels", helperText: "Create windows that only appear in Mission Control to display space names.\n\nMay not work when multiple displays are connected.") {
                        Toggle("", isOn: $labelManager.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    
                    Divider()
                    
                    SettingsRow("Settings.General.General.LaunchAtLogin") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: launchAtLogin) { value in
                                toggleLaunchAtLogin(value)
                            }
                    }
                }
                
                SettingsSection("Settings.General.Updates") {
                    SettingsRow("Settings.General.Updates.AutoCheckUpdate") {
                        Toggle("", isOn: $autoCheckUpdate)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: autoCheckUpdate) { value in
                                UpdateManager.isAutoCheckEnabled = value
                            }
                    }
                    
                    Divider()
                    
                    SettingsRow("Settings.General.Updates.ManualCheck") {
                        Button(NSLocalizedString("Settings.General.Updates.Button", comment: "")) {
                            checkForUpdate()
                        }
                    }
                }
                
                SettingsSection("Settings.General.Reset") {
                    SettingsRow("Settings.General.Reset.Body") {
                        Button(NSLocalizedString("Settings.General.Reset.Button", comment: "")) {
                            resetNames()
                        }
                        .disabled(isResetting)
                    }
                }
                
                SettingsSection("Settings.General.Advanced") {
                    SettingsRow("Settings.General.Advanced.EnableAPI", helperText: "Allow other apps to get space names.") {
                        Toggle("", isOn: $isAPIEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: isAPIEnabled) { value in
                                SpaceAPI(spaceManager: spaceManager).toggleAPIState()
                            }
                    }
                    
                    Divider()
                    
                    SettingsRow("Use stable space detection method", helperText: "This method is more stable than the normal one. It detects space every \(String(format: "%.2f", POLL_INTERVAL))s, slightly increasing the energy cost.\n\nNotice, the space name may update twice every time you switch the space, and you may also see the name of the main space appears shortly.") {
                        Toggle("", isOn: $isStableEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: isStableEnabled) { value in
                                spaceManager.togglePolling()
                            }
                    }
                }
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            launchAtLogin = getLaunchAtLoginState()
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
        }
    }
    
    private func checkForUpdate() {
        Task {
            await UpdateManager.shared.checkForUpdate(from: nil, suppressUpToDateAlert: false)
        }
    }
    
    private func resetNames() {
        isResetting = true
        
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Settings.General.Reset.Alert.Msg", comment: "")
        alert.informativeText = NSLocalizedString("Settings.General.Reset.Alert.Info", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Settings.General.Reset.Alert.Reset", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Button.Cancel", comment: ""))
        
        guard let window = NSApp.keyWindow else {
            isResetting = false
            return
        }
        
        alert.beginSheetModal(for: window) { response in
            DispatchQueue.main.async {
                self.isResetting = false
                
                if response == .alertFirstButtonReturn {
                    self.spaceManager.resetAllNames()
                    
                    let successAlert = NSAlert()
                    successAlert.messageText = NSLocalizedString("Settings.General.Reset.Success.Msg", comment: "")
                    successAlert.informativeText = NSLocalizedString("Settings.General.Reset.Success.Info", comment: "")
                    successAlert.alertStyle = .informational
                    successAlert.addButton(withTitle: NSLocalizedString("Button.OK", comment: ""))
                    successAlert.beginSheetModal(for: window) { _ in }
                }
            }
        }
    }
}
