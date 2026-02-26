import SwiftUI

struct PermissionsSettingsView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Permissions", helperText: "If the Settings show that the permission is granted but the app still does not have the permission, remove the app row in Settings and re-grant.") {
                    SettingsRow("Accessibility", helperText: "Required for injecting shortcuts to switch spaces, and reading active window information.") {
                        HStack {
                            if permissionManager.isAccessibilityGranted {
                                Text("Granted")
                                    .foregroundColor(.green)
                            } else {
                                Text("Not Granted")
                                    .foregroundColor(.red)
                            }
                            
                            Button(permissionManager.isAccessibilityGranted ? "Open Settings" : "Grant") {
                                permissionManager.requestAccessibilityPermission()
                            }
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow("Automation", helperText: "Required for using Mission Control via AppleScript (System Events) to switch spaces when the fast-switch method falls back.") {
                        HStack {
                            if permissionManager.isAutomationGranted {
                                Text("Granted")
                                    .foregroundColor(.green)
                            } else {
                                Text("Not Granted")
                                    .foregroundColor(.red)
                            }
                            
                            Button(permissionManager.isAutomationGranted ? "Open Settings" : "Grant") {
                                permissionManager.requestAutomationPermission()
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
