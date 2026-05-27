import SwiftUI

struct LauncherSettingsView: View {
    @EnvironmentObject var spaceManager: SpaceManager
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @ObservedObject var viewModel = LauncherWindowController.shared.viewModel
    @StateObject private var permissionManager = PermissionManager.shared
    @EnvironmentObject var navigationState: SettingsNavigationState
    
    var body: some View {
        SettingsContainer(.launcher) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Launcher Settings") {
                    SettingsRow("Open launcher") {
                        HStack {
                            Text(hotkeyManager.description(for: .launcher))
                                .foregroundColor(.secondary)
                                .padding(.trailing, 8)
                            
                            Button("◉") {
                                hotkeyManager.startListening(for: .launcher)
                            }
                            .disabled(hotkeyManager.isListening)
                            
                            Button("↺") {
                                hotkeyManager.resetToDefault(for: .launcher)
                            }
                            .disabled(hotkeyManager.isDefault(for: .launcher))
                        }
                    }

                    Divider()

                    SettingsRow(
                        "Automatically return to original space",
                        helperText: "Automatically return to your original desktop after moving windows to a different desktop."
                    ) {
                        Toggle("", isOn: $spaceManager.returnToOriginalAfterBatchMove)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
                
                SettingsSection("Launcher Commands Ranking") {
                    SettingsRow(
                        "Automatically rank commands",
                        helperText: "Automatically rank commands based on their execution frequency. Turn off to manually reorder commands."
                    ) {
                        Toggle("", isOn: $viewModel.automaticallyRankCommands)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    
                    if !viewModel.automaticallyRankCommands {
                        Divider()
                        
                        VStack(spacing: 0) {
                            HStack(spacing: 10) {
                                Text("#").frame(width: 30, alignment: .leading)
                                Text(NSLocalizedString("Settings.Launcher.Command.Name", comment: ""))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id("Settings.Launcher.Command.Name")
                                Text(NSLocalizedString("Settings.Launcher.Command.Actions", comment: ""))
                                    .frame(width: 60, alignment: .trailing)
                                    .id("Settings.Launcher.Command.Actions")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            
                            Divider()
                            
                            let orderedCommands = viewModel.manualCommandOrder.compactMap { id in
                                viewModel.allCommands.first(where: { $0.id == id })
                            }
                            
                            if orderedCommands.isEmpty {
                                Text("No commands found")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(10)
                            } else {
                                ForEach(Array(orderedCommands.enumerated()), id: \.element.id) { index, command in
                                    VStack(spacing: 0) {
                                        HStack(spacing: 10) {
                                            Text("\(index + 1)")
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .frame(width: 30, alignment: .leading)
                                            
                                            HStack(spacing: 8) {
                                                Image(systemName: command.iconName)
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.secondary)
                                                    .frame(width: 20)
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(command.title)
                                                        .font(.body)
                                                        .fontWeight(.medium)
                                                    Text(command.subtitle)
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            
                                            HStack(spacing: 4) {
                                                Button(action: {
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        viewModel.moveCommand(at: index, direction: -1)
                                                    }
                                                }) {
                                                    Image(systemName: "chevron.up").frame(width: 16, height: 16)
                                                }
                                                .disabled(index == 0)
                                                .opacity(index == 0 ? 0.3 : 1.0)
                                                
                                                Button(action: {
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        viewModel.moveCommand(at: index, direction: 1)
                                                    }
                                                }) {
                                                    Image(systemName: "chevron.down").frame(width: 16, height: 16)
                                                }
                                                .disabled(index == orderedCommands.count - 1)
                                                .opacity(index == orderedCommands.count - 1 ? 0.3 : 1.0)
                                            }
                                            .buttonStyle(.borderless)
                                            .frame(width: 60, alignment: .trailing)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        
                                        if command.id != orderedCommands.last?.id {
                                            Divider().padding(.leading, 12)
                                        }
                                    }
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(sectionBackgroundColor.opacity(0.6))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.2), value: viewModel.automaticallyRankCommands)
            .animation(.easeInOut(duration: 0.2), value: viewModel.launcherManualCommandOrder)
            .onAppear {
                navigationState.register(title: "Settings.Launcher.Command.Actions", tab: .launcher, keywords: ["reorder", "arrange", "sequence", "position", "move", "up", "down", "rank"])
            }
            .onDisappear {
                navigationState.unregister(title: "Settings.Launcher.Command.Actions", tab: .launcher)
            }
            .environment(\.settingsTab, .launcher)
        }
    }
    
    private var sectionBackgroundColor: Color {
        let nsColor = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 0.20, alpha: 1.0)
            } else {
                return NSColor(calibratedWhite: 1.00, alpha: 1.0)
            }
        }
        return Color(nsColor: nsColor)
    }
}
