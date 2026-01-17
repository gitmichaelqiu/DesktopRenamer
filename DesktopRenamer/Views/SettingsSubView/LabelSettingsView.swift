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
                            "Show Preview Labels",
                            helperText: "The large label visible in Mission Control."
                        ) {
                            Toggle("", isOn: $labelManager.showPreviewLabels)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        if labelManager.showPreviewLabels {
                            Divider()
                            
                            SliderSectionRow(
                                title: "Font Size",
                                value: $labelManager.previewFontScale,
                                range: 0.5...2.0
                            )
                            
                            Divider()
                            
                            SliderSectionRow(
                                title: "Window Size",
                                value: $labelManager.previewPaddingScale,
                                range: 0.5...3.0
                            )
                        }
                    }
                    
                    SettingsSection("Active Space Labels") {
                        // Main Toggle
                        SettingsRow(
                            "Show Active Space Labels",
                            helperText: "The hidden label that slides into the corner of the active desktop."
                        ) {
                            Toggle("", isOn: $labelManager.showActiveLabels)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        if labelManager.showActiveLabels {
                            Divider()
                            
                            SettingsRow(
                                "Keep Visible on Desktop",
                                helperText: "If enabled, the label stays on the desktop instead of hiding.\n\nTip: You can drag the window to the screen edge to shrink it into a 'Picture-in-Picture' mode."
                            ) {
                                Toggle("", isOn: $labelManager.showOnDesktop)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }
                            
                            Divider()
                            
                            SliderSectionRow(
                                title: "Font Size",
                                value: $labelManager.activeFontScale,
                                range: 0.5...2.0
                            )
                            
                            Divider()
                            
                            SliderSectionRow(
                                title: "Window Size",
                                value: $labelManager.activePaddingScale,
                                range: 0.5...3.0
                            )
                        }
                    }
                    
                    // MARK: - SECTION 3: ACTIONS
                    SettingsSection("Actions") {
                        SettingsRow("Restore Defaults") {
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
    
    // MARK: - Custom Helper for Full-Width Sliders
    struct SliderSectionRow: View {
        let title: LocalizedStringKey
        @Binding var value: Double
        let range: ClosedRange<Double>
        
        var body: some View {
            VStack(spacing: 6) {
                // Top Row: Title and Value
                HStack {
                    Text(title)
                    Spacer()
                    Text("\(value, specifier: "%.2f")x")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
                
                // Bottom Row: Full Width Slider
                Slider(value: $value, in: range, step: 0.10)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
    }
}
