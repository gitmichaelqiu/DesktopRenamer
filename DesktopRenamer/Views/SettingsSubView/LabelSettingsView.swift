import SwiftUI

struct LabelSettingsView: View {
    @ObservedObject var labelManager: SpaceLabelManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // SECTION 1: PREVIEW LABEL (Mission Control)
                SettingsSection("Preview Labels") {
                    VStack(alignment: .leading, spacing: 16) {
                        // NEW: Toggle
                        Toggle("Show Preview Labels", isOn: $labelManager.showPreviewLabels)
                            .toggleStyle(.switch)
                            
                        Divider()
                            .padding(.vertical, 4)
                        
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
                        .disabled(!labelManager.showPreviewLabels)
                        .opacity(labelManager.showPreviewLabels ? 1.0 : 0.5)
                        
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
                        .disabled(!labelManager.showPreviewLabels)
                        .opacity(labelManager.showPreviewLabels ? 1.0 : 0.5)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                }
                
                // SECTION 2: ACTIVE LABEL (Corner)
                SettingsSection("Active Space Labels") {
                    VStack(alignment: .leading, spacing: 16) {
                        // NEW: Toggle
                        Toggle("Show Active Space Labels", isOn: $labelManager.showActiveLabels)
                            .toggleStyle(.switch)
                        
                        HStack(alignment: .top) {
                            Toggle("Keep Visible on Desktop", isOn: $labelManager.showOnDesktop)
                                .toggleStyle(.switch)
                                .disabled(!labelManager.showActiveLabels)
                            
                            Spacer()
                            
                            if labelManager.showOnDesktop {
                                Text("Drag to edge to shrink (PiP)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                            }
                        }

                        Divider()
                            .padding(.vertical, 4)
                        
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
                        .disabled(!labelManager.showActiveLabels)
                        .opacity(labelManager.showActiveLabels ? 1.0 : 0.5)
                        
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
                        .disabled(!labelManager.showActiveLabels)
                        .opacity(labelManager.showActiveLabels ? 1.0 : 0.5)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                }
                
                // Reset Button
                HStack {
                    Spacer()
                    Button(NSLocalizedString("Reset Defaults", comment: "Reset Defaults")) {
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
                .padding(.top, 10)
            }
            .padding()
        }
    }
}
