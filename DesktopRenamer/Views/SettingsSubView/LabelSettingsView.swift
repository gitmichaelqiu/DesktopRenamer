import SwiftUI

struct LabelSettingsView: View {
    @ObservedObject var labelManager: SpaceLabelManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Enable Labels") {
                    SettingsRow("Settings.General.General.ShowLabels") {
                        Toggle("", isOn: $labelManager.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
                
                if labelManager.isEnabled {
                    SettingsSection("Preview Labels") {
                        SettingsRow(
                            "Show preview labels",
                            helperText: "The large label visible in Mission Control."
                        ) {
                            Toggle("", isOn: $labelManager.showPreviewLabels)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        if labelManager.showPreviewLabels {
                            Divider()
                            
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
                        // Main Toggle
                        SettingsRow(
                            "Show active space labels",
                            helperText: "The hidden label that slides into the corner of the active desktop."
                        ) {
                            Toggle("", isOn: $labelManager.showActiveLabels)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        if labelManager.showActiveLabels {
                            Divider()
                            
                            SettingsRow(
                                "Keep visible on desktop",
                                helperText: "If enabled, the label stays on the desktop instead of hiding.\n\nTip: You can drag the window to the screen edge to shrink it into a 'Picture-in-Picture' mode."
                            ) {
                                Toggle("", isOn: $labelManager.showOnDesktop)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }
                            
                            Divider()
                            
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
                    
                    // MARK: - SECTION 3: ACTIONS
                    SettingsSection("Actions") {
                        SettingsRow("Restore defaults") {
                            Button("Reset") {
                                withAnimation {
                                    labelManager.showPreviewLabels = true
                                    labelManager.showActiveLabels = false
                                    labelManager.activeFontScale = 1.0
                                    labelManager.activePaddingScale = 1.0
                                    labelManager.previewFontScale = 1.0
                                    labelManager.previewPaddingScale = 1.0
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: labelManager.showActiveLabels)
            .animation(.easeInOut(duration: 0.2), value: labelManager.showPreviewLabels)
            .animation(.easeInOut(duration: 0.2), value: labelManager.isEnabled)
        }
    }
}
