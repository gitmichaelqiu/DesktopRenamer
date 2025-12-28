import SwiftUI

struct LabelSettingsView: View {
    @ObservedObject var labelManager: SpaceLabelManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // MARK: - SECTION 1: PREVIEW LABEL
                SettingsSection("Preview Labels") {
                    // Toggle
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
                        
                        // Font Scale
                        SettingsRow("Font Size") {
                            sliderControl(value: $labelManager.previewFontScale, range: 0.5...2.0)
                        }
                        
                        // Padding Scale
                        SettingsRow("Window Size") {
                            sliderControl(value: $labelManager.previewPaddingScale, range: 0.5...3.0)
                        }
                    }
                }
                
                // MARK: - SECTION 2: ACTIVE LABEL
                SettingsSection("Active Space Labels") {
                    // Toggle
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
                        
                        // Desktop Visibility
                        SettingsRow(
                            "Keep Visible on Desktop",
                            helperText: "If enabled, the label stays on the desktop instead of hiding.\n\nTip: You can drag the window to the screen edge to shrink it into a 'Picture-in-Picture' mode."
                        ) {
                            Toggle("", isOn: $labelManager.showOnDesktop)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        Divider()
                        
                        // Font Scale
                        SettingsRow("Font Size") {
                            sliderControl(value: $labelManager.activeFontScale, range: 0.5...2.0)
                        }
                        
                        // Padding Scale
                        SettingsRow("Window Size") {
                            sliderControl(value: $labelManager.activePaddingScale, range: 0.5...3.0)
                        }
                    }
                }
                
                // MARK: - SECTION 3: ACTIONS
                SettingsSection("Actions") {
                    SettingsRow("Restore Defaults") {
                        Button("Reset") {
                            withAnimation {
                                labelManager.showPreviewLabels = true
                                labelManager.showActiveLabels = true
                                labelManager.activeFontScale = 1.0
                                labelManager.activePaddingScale = 1.0
                                labelManager.previewFontScale = 1.0
                                labelManager.previewPaddingScale = 1.0
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    // Helper to keep slider styling consistent across rows
    @ViewBuilder
    private func sliderControl(value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 12) {
            Slider(value: value, in: range, step: 0.10)
                .frame(width: 120) // Fixed width for alignment
            
            Text("\(value.wrappedValue, specifier: "%.2f")x")
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 45, alignment: .trailing)
        }
    }
}
