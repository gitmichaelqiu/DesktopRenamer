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
                        
                        // Switch Right
                        SettingsRow("Switch to right space") {
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
                }
                
                // MARK: - Gesture Override
                SettingsSection("Trackpad Switch Gesture Override") {
                    SettingsRow("Enable switch gesture override", helperText: "Replaces system switch gestures with instant space switching.\n\nRequired: You must disable 'Swipe between full screen apps' in System Settings > Trackpad > More Gestures to prevent conflicts.") {
                        Toggle("", isOn: $gestureManager.isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    
                    if gestureManager.isEnabled {
                        Divider()
                        
                        SettingsRow("Gesture type") {
                            Picker("", selection: $gestureManager.fingerCount) {
                                Text("3 Fingers").tag(3)
                                Text("4 Fingers").tag(4)
                            }
                            .labelsHidden()
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.2), value: gestureManager.isEnabled)
        }
    }
}
