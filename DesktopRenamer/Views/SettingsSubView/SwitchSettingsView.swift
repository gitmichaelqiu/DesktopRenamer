import SwiftUI

struct SwitchSettingsView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var gestureManager: GestureManager
    @StateObject private var permissionManager = PermissionManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: - Keyboard Shortcuts
                SettingsSection("Keyboard Shortcuts", helperText: "If you want to use Control + Arrow, disable the system's one in Settings → Keyboard → Keyboard Shortcuts... → Mission Control.") {
                    // Switch Left
                    VStack(spacing: 0) {
                        SettingsRow(
                            "Switch to left space",
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

                        // Switch Right
                        SettingsRow(
                            "Switch to right space",
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
                }

                // MARK: - Gesture Override
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

                        SettingsRow("Gesture type") {
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
                            value: $gestureManager.swipeThreshold,
                            range: 0.05...0.50,
                            defaultValue: 0.10,
                            step: 0.05,
                            helperText:
                                "Controls how much distance the fingers have to move before switching the desktop.",
                            valueString: { String(format: "%.0f%%", $0 * 100) }
                        )
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
