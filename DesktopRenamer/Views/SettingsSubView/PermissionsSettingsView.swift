import SwiftUI

struct PermissionsSettingsView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    
    var body: some View {
        SettingsContainer(.permissions) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Permissions", helperText: "Status is read from macOS for this copy of DesktopRenamer and refreshes automatically while System Settings is open. If a permission remains off, remove the old DesktopRenamer entry and add the copy currently running.") {
                    SettingsRow("Accessibility", helperText: "Required for injecting shortcuts, reading active window information, and moving windows with Option + swipe.") {
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

                    Divider()

                    SettingsRow("Event Posting", helperText: "Required for DesktopRenamer to synthesize the keyboard, mouse, and trackpad events used by switching and window movement.") {
                        HStack {
                            if permissionManager.isEventSynthesisGranted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }

                            Button(permissionManager.isEventSynthesisGranted ? "Settings" : "Grant") {
                                permissionManager.requestEventSynthesisPermission()
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
            .onAppear {
                permissionManager.refresh()
            }
        }
    }
}
