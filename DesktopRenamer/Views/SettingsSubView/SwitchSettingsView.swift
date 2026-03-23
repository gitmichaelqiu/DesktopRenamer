import SwiftUI

struct SwitchSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var gestureManager: GestureManager
    @EnvironmentObject var spaceManager: SpaceManager
    @StateObject private var permissionManager = PermissionManager.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Keyboard Shortcuts", helperText: "If you want to use Control + Arrow, disable the system's one in Settings → Keyboard → Keyboard Shortcuts... → Mission Control.") {
                    
                    SettingsRow(
                        "Switch to previous space",
                        warningText: permissionManager.isAccessibilityGranted
                        ? nil : "Requires Accessibility permission."
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
                        }
                    }
                }
                
                SettingsSection(nil) {
                    SettingsRow("Move window to previous desktop") {
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
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow("Move window to next desktop") {
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
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow("Move window to desktop number", helperText: "Press modifiers and a number to set the shortcut.") {
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
                        }
                    }
                }
                
                // Trackpad Gesture Settings
                SettingsSection("Trackpad Switch Gesture Override") {
                    SettingsRow(
                        "Enable switch gesture override",
                        helperText:
                            "Replaces system switch gestures with instant space switching.\n\nRequired: You must disable 'Swipe between full screen apps' in System Settings → Trackpad → More Gestures or change to different number of fingers to prevent conflicts.\n\nNotice, you must click at the fullscreen app to make it active to avoid issues when leaving the app.",
                        warningText: (permissionManager.isAccessibilityGranted
                                      && permissionManager.isAutomationGranted)
                        ? nil : "Requires Accessibility and Automation permissions."
                    ) {
                        Toggle("", isOn: $gestureManager.isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    
                    if gestureManager.isEnabled {
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
                
                // Advanced Settings
                SettingsSection("Advanced") {
                    SettingsRow(
                        "Force Mission Control for fullscreen apps",
                        helperText:
                            "When enabled, the app will always use Mission Control Automation for transitions to or from fullscreen apps. This is slower but more reliable on some systems.",
                        warningText: (permissionManager.isAccessibilityGranted
                                      && permissionManager.isAutomationGranted)
                        ? nil : "Requires Accessibility and Automation permissions."
                    ) {
                        Toggle("", isOn: $spaceManager.forceMissionControlForFullscreen)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
                SettingsSection(nil) {
                    SliderSettingsRow(
                        "Grab Offset X",
                        helperText: "Adjust the position where the mouse grabs the window to move across spaces.",
                        value: $spaceManager.grabOffsetX,
                        range: 0...100,
                        defaultValue: 6.0,
                        step: 1.0,
                        valueString: { String(format: "%.0f px", $0) }
                    )
                    
                    Divider()
                    
                    SliderSettingsRow(
                        "Grab Offset Y",
                        value: $spaceManager.grabOffsetY,
                        range: 0...100,
                        defaultValue: 27.0,
                        step: 1.0,
                        valueString: { String(format: "%.0f px", $0) }
                    )
                }
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.2), value: gestureManager.isEnabled)
        }
    }
}
