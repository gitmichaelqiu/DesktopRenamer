import SwiftUI

struct PermissionsSettingsView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    
    var body: some View {
        SettingsContainer(.permissions) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Permissions") {
                    SettingsRow("Accessibility", helperText: "Required for keyboard shortcuts and moving windows between spaces.") {
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

                    SettingsRow("Screen Recording", helperText: "Required to identify the active window when moving it between spaces.") {
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

                    if !permissionManager.hasAllRequiredPermissions {
                        Divider()

                        SettingsRow(
                            "Restart DesktopRenamer",
                            helperText: "Restart DesktopRenamer after changing permissions."
                        ) {
                            Button {
                                permissionManager.restartApplication()
                            } label: {
                                Text(permissionManager.isRestarting ? "Restarting…" : "Restart")
                            }
                            .disabled(permissionManager.isRestarting)
                        }
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .environment(\.settingsTab, .permissions)
            .onAppear {
                permissionManager.refresh()
            }
        }
    }
}
