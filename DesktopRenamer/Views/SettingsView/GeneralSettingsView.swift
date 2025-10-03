import SwiftUI
import ServiceManagement

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
