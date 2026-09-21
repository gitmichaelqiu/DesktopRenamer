import SwiftUI

struct LabelSettingsView: View {
    @ObservedObject var labelManager: SpaceLabelManager
    @EnvironmentObject var hotkeyManager: HotkeyManager

    private var isLiquidGlassAvailable: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    var body: some View {
        SettingsContainer(.labels) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Preview Labels") {
                    SettingsRow(
                        "Show preview labels",
                        demoVideoName: "MissionControl"
                    ) {
                        Toggle("", isOn: $labelManager.showPreviewLabels)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    if labelManager.showPreviewLabels {
                        Divider()

                        SettingsRow(
                            "Hide when switching spaces",
                            helperText:
                                "Hide the target space label before switching instead of after."
                        ) {
                            Toggle("", isOn: $labelManager.hideWhenSwitching)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        Divider()

                        if isLiquidGlassAvailable {
                            SettingsRow(
                                "Disable Liquid Glass effects",
                                helperText: "Use a blurred background instead of Liquid Glass."
                            ) {
                                Toggle("", isOn: $labelManager.disablePreviewLiquidGlass)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }

                            Divider()
                        }

                        SliderSettingsRow(
                            "Font size",
                            value: $labelManager.previewFontScale,
                            range: 0.5...2.0,
                            defaultValue: 1.0,
                            step: 0.10,
                            valueString: { String(format: "%.2fx", $0) }
                        )

                        Divider()

                        SliderSettingsRow(
                            "Window size",
                            value: $labelManager.previewPaddingScale,
                            range: 0.5...3.0,
                            defaultValue: 1.0,
                            step: 0.10,
                            valueString: { String(format: "%.2fx", $0) }
                        )
                    }
                }

                SettingsSection("Active Space Labels") {
                    // Visibility toggle for active space labels.
                    SettingsRow(
                        "Show active space labels",
                        demoVideoName: "ActiveLabel"
                    ) {
                        Toggle("", isOn: $labelManager.showActiveLabels)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    if labelManager.showActiveLabels {
                        Divider()

                        SettingsRow(
                            "Keep visible on space",
                            helperText:
                                "Keep the label visible on the desktop outside Mission Control."
                        ) {
                            Toggle("", isOn: $labelManager.showOnDesktop)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        Divider();

                        if isLiquidGlassAvailable {
                            SettingsRow(
                                "Disable Liquid Glass effects",
                                helperText: "Use a blurred background instead of Liquid Glass."
                            ) {
                                Toggle("", isOn: $labelManager.disableActiveLiquidGlass)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }

                            Divider()
                        }

                        SliderSettingsRow(
                            "Font size",
                            value: $labelManager.activeFontScale,
                            range: 0.5...2.0,
                            defaultValue: 1.0,
                            step: 0.10,
                            valueString: { String(format: "%.2fx", $0) }
                        )

                        Divider()

                        SliderSettingsRow(
                            "Window size",
                            value: $labelManager.activePaddingScale,
                            range: 0.5...3.0,
                            defaultValue: 1.0,
                            step: 0.10,
                            valueString: { String(format: "%.2fx", $0) }
                        )
                    }
                }

                if labelManager.showPreviewLabels || labelManager.showActiveLabels {
                    SettingsSection("Shortcuts") {
                        SettingsRow("Reload space labels") {
                            HStack {
                                Text(hotkeyManager.description(for: .reloadLabels))
                                    .foregroundColor(.secondary)
                                    .padding(.trailing, 8)
                                
                                Button("◉") {
                                    hotkeyManager.startListening(for: .reloadLabels)
                                }
                                .disabled(hotkeyManager.isListening)
                                
                                Button("↺") {
                                    hotkeyManager.resetToDefault(for: .reloadLabels)
                                }
                                .disabled(hotkeyManager.isDefault(for: .reloadLabels))
                            }
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: labelManager.showActiveLabels)
            .animation(.easeInOut(duration: 0.2), value: labelManager.showPreviewLabels)
            .animation(.easeInOut(duration: 0.2), value: labelManager.disableActiveLiquidGlass)
            .animation(.easeInOut(duration: 0.2), value: labelManager.disablePreviewLiquidGlass)
            .environment(\.settingsTab, .labels)
        }
    }
}
