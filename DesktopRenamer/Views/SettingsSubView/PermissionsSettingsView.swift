import SwiftUI

struct PermissionsSettingsView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    
    var body: some View {
        SettingsContainer(.permissions) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Permissions", helperText: "Status is read from macOS for this copy of DesktopRenamer and refreshes automatically while System Settings is open. Accessibility covers both window control and the event input needed for switching. If a permission remains off, remove the old DesktopRenamer entry and add the copy currently running.") {
                    SettingsRow("Accessibility", helperText: "Required for injecting shortcuts, reading active window information, and moving windows with Option + swipe. This also includes the event control needed to switch Spaces and move windows.") {
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

                    if !permissionManager.hasAllRequiredPermissions {
                        Divider()

                        SettingsRow(
                            "Restart DesktopRenamer",
                            helperText: "Restart after changing permissions so macOS applies the updated access to a fresh DesktopRenamer process."
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
