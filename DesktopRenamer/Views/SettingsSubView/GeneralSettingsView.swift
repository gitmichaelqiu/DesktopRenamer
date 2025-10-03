import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    @State private var launchAtLogin: Bool = false
    @State private var autoCheckUpdate: Bool = UpdateManager.isAutoCheckEnabled
    @State private var isResetting: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Settings.General.General") {
                    SettingsRow("Settings.General.General.ShowLabels") {
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
                    SettingsRow("Settings.General.Reset.Button") {
                        Button(NSLocalizedString("Settings.General.Reset.Button", comment: "")) {
                            resetNames()
                        }
                        .disabled(isResetting)
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
                
                // Show error alert
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Settings.LaunchAtLogin.Error", comment: "Failed to toggle launch at login")
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: NSLocalizedString("Button.OK", comment: "OK"))
                alert.runModal()
            }
        } else {
            if let bundleId = Bundle.main.bundleIdentifier {
                let success = SMLoginItemSetEnabled(bundleId as CFString, enabled)
                if !success {
                    launchAtLogin = getLaunchAtLoginState()
                    
                    // Show error alert
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Settings.General.General.LaunchAtLogin.Error", comment: "Failed to toggle launch at login")
                    alert.informativeText = NSLocalizedString("Settings.General.General.LaunchAtLogin.Error.info", comment: "Could not update login items")
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: NSLocalizedString("Common.OK", comment: "OK"))
                    alert.runModal()
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
                    
                    // Show success feedback
                    let successAlert = NSAlert()
                    successAlert.messageText = NSLocalizedString("Settings.General.Reset.Success.Msg", comment: "Reset successful")
                    successAlert.informativeText = NSLocalizedString("Settings.General.Reset.Success.Info", comment: "All space names have been reset to their default values")
                    successAlert.alertStyle = .informational
                    successAlert.addButton(withTitle: NSLocalizedString("Button.OK", comment: "OK"))
                    successAlert.beginSheetModal(for: window) { _ in
                    }
                }
            }
        }
    }
}
