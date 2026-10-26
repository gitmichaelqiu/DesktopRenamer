import SwiftUI

struct ShortcutsSettingsView: View {
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @EnvironmentObject private var labelManager: SpaceLabelManager
    @StateObject private var permissionManager = PermissionManager.shared

    var body: some View {
        SettingsContainer(.shortcuts) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Settings.Launcher") {
                    shortcutRow("Open launcher", type: .launcher)
                }

                SettingsSection(
                    "Space Navigation",
                    helperText: "If you use Control + Arrow shortcuts, disable the matching Mission Control shortcuts in System Settings."
                ) {
                    shortcutRow(
                        "Switch to previous space",
                        type: .switchLeft,
                        requirements: eventInjectionRequirement
                    )

                    Divider()

                    shortcutRow(
                        "Switch to next space",
                        type: .switchRight,
                        requirements: eventInjectionRequirement
                    )

                    Divider()

                    shortcutRow(
                        "Switch to space number",
                        type: .switchSpaceNumber,
                        requirements: eventInjectionRequirement
                    )
                }

                SettingsSection("Window Movement") {
                    shortcutRow(
                        "Move window to previous space",
                        type: .moveWindowPrevious,
                        requirements: eventInjectionRequirement
                    )

                    Divider()

                    shortcutRow(
                        "Move window to next space",
                        type: .moveWindowNext,
                        requirements: eventInjectionRequirement
                    )

                    Divider()

                    shortcutRow(
                        "Move window to space number",
                        type: .moveWindowNumber,
                        requirements: eventInjectionRequirement
                    )

                    Divider()

                    shortcutRow(
                        "Move window to previous display",
                        type: .moveWindowPreviousDisplay,
                        requirements: eventInjectionRequirement
                    )

                    Divider()

                    shortcutRow(
                        "Move window to next display",
                        type: .moveWindowNextDisplay,
                        requirements: eventInjectionRequirement
                    )
                }

                SettingsSection("Space Lock") {
                    shortcutRow(
                        "Toggle lock for current space",
                        type: .toggleLock,
                        helperText: "When opening an app switches spaces, return its window to the original space.",
                        demoVideoName: "LockSpace",
                        requirements: eventInjectionRequirement
                    )

                    Divider()

                    shortcutRow(
                        "Restore windows moved by lock",
                        type: .restoreWindows,
                        requirements: eventInjectionRequirement
                    )
                }

                if labelManager.showPreviewLabels || labelManager.showActiveLabels {
                    SettingsSection("Settings.Labels") {
                        shortcutRow("Reload space labels", type: .reloadLabels)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .environment(\.settingsTab, .shortcuts)
        }
    }

    private var eventInjectionRequirement: [SettingsRequirement] {
        [.accessibility(isGranted: permissionManager.hasEventInjectionPermission)]
    }

    private func shortcutRow(
        _ title: LocalizedStringResource,
        type: HotkeyType,
        helperText: LocalizedStringKey? = nil,
        demoVideoName: String? = nil,
        requirements: [SettingsRequirement] = []
    ) -> some View {
        SettingsRow(
            title,
            helperText: helperText,
            requirements: requirements,
            demoVideoName: demoVideoName
        ) {
            HStack {
                Text(hotkeyManager.description(for: type))
                    .foregroundColor(.secondary)
                    .padding(.trailing, 8)

                Button("◉") {
                    hotkeyManager.startListening(for: type)
                }
                .disabled(hotkeyManager.isListening)

                Button("↺") {
                    hotkeyManager.resetToDefault(for: type)
                }
                .disabled(hotkeyManager.isDefault(for: type))
            }
        }
    }
}
