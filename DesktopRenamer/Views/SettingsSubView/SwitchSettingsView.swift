import SwiftUI

struct SwitchSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var gestureManager: GestureManager
    @EnvironmentObject var spaceManager: SpaceManager
    @EnvironmentObject var labelManager: SpaceLabelManager
    @StateObject private var permissionManager = PermissionManager.shared
    
    var body: some View {
        SettingsContainer(.sswitch) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Keyboard Shortcuts", helperText: "If you want to use Control + Arrow, disable the system's one in Settings → Keyboard → Keyboard Shortcuts... → Mission Control.") {
                    
                    SettingsRow(
                        "Switch to previous space",
                        warningText: permissionManager.isAccessibilityGranted
                        ? nil : "Requires Accessibility permission.",
                    ) {
                        HStack {
                            Text(hotkeyManager.description(for: .switchLeft))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .switchLeft)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .switchLeft)
                            }
                            .disabled(hotkeyManager.isDefault(for: .switchLeft))
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow(
                        "Switch to next space",
                        warningText: permissionManager.isAccessibilityGranted
                        ? nil : "Requires Accessibility permission."
                    ) {
                        HStack {
                            Text(hotkeyManager.description(for: .switchRight))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .switchRight)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .switchRight)
                            }
                            .disabled(hotkeyManager.isDefault(for: .switchRight))
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow(
                        "Switch to space number",
                        helperText: "Press modifiers and a number to set the shortcut."
                    ) {
                        HStack {
                            Text(hotkeyManager.description(for: .switchSpaceNumber))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .switchSpaceNumber)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .switchSpaceNumber)
                            }
                            .disabled(hotkeyManager.isDefault(for: .switchSpaceNumber))
                        }
                    }
                }
                
                SettingsSection(nil) {
                    SettingsRow("Move window to previous space") {
                        HStack {
                            Text(hotkeyManager.description(for: .moveWindowPrevious))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .moveWindowPrevious)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .moveWindowPrevious)
                            }
                            .disabled(hotkeyManager.isDefault(for: .moveWindowPrevious))
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow("Move window to next space") {
                        HStack {
                            Text(hotkeyManager.description(for: .moveWindowNext))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .moveWindowNext)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .moveWindowNext)
                            }
                            .disabled(hotkeyManager.isDefault(for: .moveWindowNext))
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow("Move window to space number", helperText: "Press modifiers and a number to set the shortcut.") {
                        HStack {
                            Text(hotkeyManager.description(for: .moveWindowNumber))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .moveWindowNumber)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .moveWindowNumber)
                            }
                            .disabled(hotkeyManager.isDefault(for: .moveWindowNumber))
                        }
                    }   
                }

                SettingsSection(nil) {
                    SettingsRow("Move window to previous display") {
                        HStack {
                            Text(hotkeyManager.description(for: .moveWindowPreviousDisplay))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .moveWindowPreviousDisplay)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .moveWindowPreviousDisplay)
                            }
                            .disabled(hotkeyManager.isDefault(for: .moveWindowPreviousDisplay))
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow("Move window to next display") {
                        HStack {
                            Text(hotkeyManager.description(for: .moveWindowNextDisplay))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .moveWindowNextDisplay)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .moveWindowNextDisplay)
                            }
                            .disabled(hotkeyManager.isDefault(for: .moveWindowNextDisplay))
                        }
                    }
                }

                SettingsSection(nil) {
                    SettingsRow("Toggle lock for current space",
                        helperText: "When a space switch is triggered by opening the window of an app, move that window back to the original space. This way, you are always focused in the locked space.",
                        demoVideoName: "LockSpace"
                    ) {
                        HStack {
                            Text(hotkeyManager.description(for: .toggleLock))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .toggleLock)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .toggleLock)
                            }
                            .disabled(hotkeyManager.isDefault(for: .toggleLock))
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow("Restore windows moved by lock",
                        helperText: "Restore windows moved by lock to the last space that windows are manually assigned to."
                    ) {
                        HStack {
                            Text(hotkeyManager.description(for: .restoreWindows))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .restoreWindows)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .restoreWindows)
                            }
                            .disabled(hotkeyManager.isDefault(for: .restoreWindows))
                        }
                    }
                }
                
                // Gesture-based switching configuration.
                SettingsSection("Trackpad Switch Gesture Override") {
                    SettingsRow(
                        "Enable switch gesture override",
                        helperText:
                            "Replaces system switch gestures with instant space switching.\n\nRequired: You must disable 'Swipe between full screen apps' in System Settings → Trackpad → More Gestures or change to different number of fingers to prevent conflicts.\n\nNotice, you must click at the fullscreen app to make it active to avoid issues when leaving the app.",
                        warningText: permissionManager.isAccessibilityGranted
                        ? nil : "Requires Accessibility permission.",
                        demoVideoName: "SwitchOverride"
                    ) {
                        Toggle("", isOn: $gestureManager.isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    
                    if gestureManager.isEnabled {
                        Divider()     

                        SettingsRow(
                            "Instant switch without animations",
                            helperText:
                                "Bypasses the macOS sliding animation using synthetic high-velocity gestures.\n\nRequires 'Swipe between full-screen applications' enabled in System Settings → Trackpad.\n\nRecommended: Disable 'Automatically rearrange spaces based on most recent use' in Desktop & Dock settings to prevent miscalculations.",
                            warningText: permissionManager.isAccessibilityGranted
                            ? nil : "Requires Accessibility permission."
                        ) {
                            Toggle("", isOn: $spaceManager.instantSpaceSwitch)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        Divider()

                        SettingsRow("Gesture type", helperText: "When set to 3 fingers, you can still use 4 fingers to trigger native swipe.") {
                            Picker("", selection: $gestureManager.fingerCount) {
                                Text("3 Fingers").tag(3)
                                Text("4 Fingers").tag(4)
                            }
                            .labelsHidden()
                        }

                        Divider()
                        
                        SettingsRow("Switch display with") {
                            Picker("", selection: $gestureManager.switchOverride) {
                                Text("Cursor").tag(GestureManager.SwitchOverrideMode.cursor)
                                Text("Active Window").tag(
                                    GestureManager.SwitchOverrideMode.activeWindow)
                            }
                            .labelsHidden()
                        }
                        
                        Divider()
                        
                        SliderSettingsRow(
                            "Switch override threshold",
                            helperText: "Controls how much distance the fingers have to move before switching the desktop.",
                            value: $gestureManager.swipeThreshold,
                            range: 0.05...0.50,
                            defaultValue: 0.10,
                            step: 0.05,
                            valueString: { String(format: "%.0f%%", $0 * 100) }
                        )
                    }
                }
                

                SettingsSection("Advanced") {
                    SliderSettingsRow(
                        "Grab offset X",
                        helperText: "Adjust the position where the mouse grabs the window to move across spaces.",
                        value: $spaceManager.grabOffsetX,
                        range: 0...100,
                        defaultValue: 6.0,
                        step: 1.0,
                        valueString: { String(format: "%.0f px", $0) }
                    )
                    
                    Divider()
                    
                    SliderSettingsRow(
                        "Grab offset Y",
                        value: $spaceManager.grabOffsetY,
                        range: 0...100,
                        defaultValue: 27.0,
                        step: 1.0,
                        valueString: { String(format: "%.0f px", $0) }
                    )
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.2), value: gestureManager.isEnabled)
            .environment(\.settingsTab, .sswitch)
        }
    }
}
