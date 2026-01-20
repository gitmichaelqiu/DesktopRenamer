import SwiftUI

struct SwitchSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var gestureManager: GestureManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // MARK: - Switch Left
                SettingsSection("Switch to the left space") {
                    SettingsRow("Settings.Shortcuts.Hotkey", helperText: "You can remove the system shortkey of control + arrow key by editing Settings/Keyboard/Keyboard Shortcuts/Mission Control.") {
                        Text(hotkeyManager.description(for: .switchLeft))
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    .frame(minHeight: 36)

                    Divider()

                    SettingsRow("") {
                        HStack(spacing: 8) {
                            Button(NSLocalizedString("Settings.Shortcuts.Hotkey.Change", comment: "Change")) {
                                hotkeyManager.startListening(for: .switchLeft)
                            }
                            Button(NSLocalizedString("Settings.Shortcuts.Hotkey.Reset", comment: "Reset")) {
                                hotkeyManager.resetToDefault(for: .switchLeft)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(minHeight: 36)
                }
                
                // MARK: - Switch Right
                SettingsSection("Switch to the right space") {
                    SettingsRow("Settings.Shortcuts.Hotkey", helperText: "You can remove the system shortkey of control + arrow key by editing Settings/Keyboard/Keyboard Shortcuts/Mission Control.") {
                        Text(hotkeyManager.description(for: .switchRight))
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    .frame(minHeight: 36)
                    
                    Divider()
                    
                    SettingsRow("") {
                        HStack(spacing: 8) {
                            Button(NSLocalizedString("Settings.Shortcuts.Hotkey.Change", comment: "Change")) {
                                hotkeyManager.startListening(for: .switchRight)
                            }
                            Button(NSLocalizedString("Settings.Shortcuts.Hotkey.Reset", comment: "Reset")) {
                                hotkeyManager.resetToDefault(for: .switchRight)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(minHeight: 36)
                }
                
                // MARK: - Gesture Override
                SettingsSection("Trackpad Gesture Override") {
                    SettingsRow("Enable Gesture Override", helperText: "Allows DesktopRenamer to handle space switching gestures.\n\nImportant: You must disable 'Swipe between full screen apps' in System Settings > Trackpad > More Gestures to prevent conflicts.") {
                        Toggle("", isOn: $gestureManager.isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    
                    if gestureManager.isEnabled {
                        Divider().padding(.leading, 16)
                        
                        SettingsRow("Gesture Type") {
                            Picker("", selection: $gestureManager.fingerCount) {
                                Text("3 Fingers").tag(3)
                                Text("4 Fingers").tag(4)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                            .labelsHidden()
                        }
                        
                        SettingsRow("", helperText: "This feature uses scroll momentum to detect swipes. It provides a faster, instant switch compared to the native animation.") {
                            EmptyView()
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
