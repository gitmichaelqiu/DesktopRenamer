import SwiftUI

struct LabelSettingsView: View {
    @ObservedObject var labelManager: SpaceLabelManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // SECTION 1: ACTIVE LABEL (Corner)
                SettingsSection("Active Space Labels") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(NSLocalizedString("The hidden label that slides into the corner.", comment: "The hidden label that slides into the corner."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Font Scale
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(NSLocalizedString("Font Size", comment: ""))
                                Spacer()
                                Text("\(labelManager.activeFontScale, specifier: "%.2f")x")
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $labelManager.activeFontScale, in: 0.5...2.0, step: 0.10)
                        }
                        
                        // Padding Scale
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(NSLocalizedString("Window Size", comment: ""))
                                Spacer()
                                Text("\(labelManager.activePaddingScale, specifier: "%.2f")x")
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $labelManager.activePaddingScale, in: 0.5...3.0, step: 0.10)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                }
                
                // SECTION 2: PREVIEW LABEL (Mission Control)
                SettingsSection("Preview Labels") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(NSLocalizedString("The large label visible in Mission Control.", comment: "The large label visible in Mission Control."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Font Scale
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(NSLocalizedString("Font Size", comment: ""))
                                Spacer()
                                Text("\(labelManager.previewFontScale, specifier: "%.2f")x")
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $labelManager.previewFontScale, in: 0.5...2.0, step: 0.10)
                        }
                        
                        // Padding Scale
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(NSLocalizedString("Window Size", comment: ""))
                                Spacer()
                                Text("\(labelManager.previewPaddingScale, specifier: "%.2f")x")
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $labelManager.previewPaddingScale, in: 0.5...3.0, step: 0.10)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                }
                
                // Reset Button
                HStack {
                    Spacer()
                    Button(NSLocalizedString("Reset Defaults", comment: "Reset Defaults")) {
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
