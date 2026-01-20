import SwiftUI

struct SwitchSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager

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

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
