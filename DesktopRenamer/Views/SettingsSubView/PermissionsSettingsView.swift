import SwiftUI

struct PermissionsSettingsView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    
    var body: some View {
        SettingsContainer(.permissions) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Permissions", helperText: "If the Settings show that the permission is granted but the app still does not have the permission, remove the app row in Settings and re-grant.") {
                    SettingsRow("Accessibility", helperText: "Required for injecting shortcuts, reading active window information, and moving windows with Option + swipe.") {
                        HStack {
                            if permissionManager.hasAccessibilityPermission {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                            
                            Button(permissionManager.hasAccessibilityPermission ? "Settings" : "Grant") {
                                permissionManager.requestAccessibilityPermission()
                            }
                        }
                    }

                    Divider()

                    SettingsRow("Screen Recording", helperText: "Required for reading the active window before moving it with Option + swipe.") {
                        HStack {
                            if permissionManager.isScreenCaptureGranted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }

                            Button(permissionManager.isScreenCaptureGranted ? "Settings" : "Grant") {
                                permissionManager.requestScreenCapturePermission()
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
