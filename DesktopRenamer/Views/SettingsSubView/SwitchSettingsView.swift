import SwiftUI

struct SwitchSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var gestureManager: GestureManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // MARK: - Keyboard Shortcuts
                SettingsSection("Keyboard Shortcuts") {
                    // Switch Left
                    VStack(spacing: 0) {
                        SettingsRow("Switch to left space") {
                            HStack {
                                Text(hotkeyManager.description(for: .switchLeft))
                                    .foregroundColor(.secondary)
                                    .padding(.trailing, 8)
                                
                                Button("Record") {
                                    hotkeyManager.startListening(for: .switchLeft)
                                }
                                .disabled(hotkeyManager.isListening)
                            }
                        }
                        
                        Divider().padding(.leading, 16)
                        
                        // Switch Right
                        SettingsRow("Switch to right space") {
                            HStack {
                                Text(hotkeyManager.description(for: .switchRight))
                                    .foregroundColor(.secondary)
                                    .padding(.trailing, 8)
                                
                                Button("Record") {
                                    hotkeyManager.startListening(for: .switchRight)
                                }
                                .disabled(hotkeyManager.isListening)
                            }
                        }
                    }
                }
                
                // MARK: - Gesture Override
                SettingsSection("Trackpad Gesture Override") {
                    SettingsRow("Enable Gesture Override", helperText: "Replaces system gestures with instant space switching.\n\nRequired: You must disable 'Swipe between full screen apps' in System Settings > Trackpad > More Gestures to prevent conflicts.") {
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
                        
                        SettingsRow("", helperText: "Uses MultitouchSupport to detect physical swipes.") {
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
