import SwiftUI

struct LabelSettingsView: View {
    @ObservedObject var labelManager: SpaceLabelManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // SECTION 1: ACTIVE LABEL (Corner)
                SettingsSection("Settings.Labels.Active") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(NSLocalizedString("Settings.Labels.Active.Desc", comment: "The hidden label that slides into the corner."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Font Scale
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(NSLocalizedString("Settings.Labels.FontSize", comment: ""))
                                Spacer()
                                Text("\(labelManager.activeFontScale, specifier: "%.2f")x")
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $labelManager.activeFontScale, in: 0.5...2.0, step: 0.05)
                        }
                        
                        // Padding Scale
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(NSLocalizedString("Settings.Labels.WindowSize", comment: ""))
                                Spacer()
                                Text("\(labelManager.activePaddingScale, specifier: "%.2f")x")
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $labelManager.activePaddingScale, in: 0.5...3.0, step: 0.05)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                }
                
                // SECTION 2: PREVIEW LABEL (Mission Control)
                SettingsSection("Settings.Labels.Preview") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(NSLocalizedString("Settings.Labels.Preview.Desc", comment: "The large label visible in Mission Control."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Font Scale
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(NSLocalizedString("Settings.Labels.FontSize", comment: ""))
                                Spacer()
                                Text("\(labelManager.previewFontScale, specifier: "%.2f")x")
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $labelManager.previewFontScale, in: 0.5...2.0, step: 0.05)
                        }
                        
                        // Padding Scale
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(NSLocalizedString("Settings.Labels.WindowSize", comment: ""))
                                Spacer()
                                Text("\(labelManager.previewPaddingScale, specifier: "%.2f")x")
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $labelManager.previewPaddingScale, in: 0.5...3.0, step: 0.05)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                }
                
                // Reset Button
                HStack {
                    Spacer()
                    Button(NSLocalizedString("Settings.Labels.Reset", comment: "Reset Defaults")) {
                        withAnimation {
                            labelManager.activeFontScale = 1.0
                            labelManager.activePaddingScale = 1.0
                            labelManager.previewFontScale = 1.0
                            labelManager.previewPaddingScale = 1.0
                        }
                    }
                }
                .padding(.top, 10)
            }
            .padding()
        }
    }
}
