import SwiftUI

struct PermissionsSettingsView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    
    var body: some View {
        SettingsContainer(.permissions) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Permissions", helperText: "If the Settings show that the permission is granted but the app still does not have the permission, remove the app row in Settings and re-grant.") {
                    SettingsRow("Accessibility", helperText: "Required for injecting shortcuts to switch spaces, and reading active window information.") {
                        HStack {
                            if permissionManager.isAccessibilityGranted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                            
                            Button(permissionManager.isAccessibilityGranted ? "Settings" : "Grant") {
                                permissionManager.requestAccessibilityPermission()
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .environment(\.settingsTab, .permissions)
        }
    }
}
