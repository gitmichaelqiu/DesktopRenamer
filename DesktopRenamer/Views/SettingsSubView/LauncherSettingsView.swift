import SwiftUI

@MainActor
struct LauncherSettingsView: View {
    @EnvironmentObject var spaceManager: SpaceManager
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @ObservedObject var viewModel = LauncherWindowController.shared.viewModel
    @StateObject private var permissionManager = PermissionManager.shared
    @EnvironmentObject var navigationState: SettingsNavigationState
    @Environment(\.isSettingsPreRendering) private var isPreRendering
    
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
                        "Automatically return to original space"
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
                }

                if !viewModel.automaticallyRankCommands {
                    SettingsSection(nil) {
                        VStack(spacing: 0) {
                            HStack(spacing: 10) {
                                Color.clear.frame(width: 16)
                                Text("#").frame(width: 30, alignment: .leading)
                                Text(NSLocalizedString("Settings.Launcher.Command.Name", comment: ""))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id("Settings.Launcher.Command.Name")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            
                            Divider()
                            
                            if orderedCommands.isEmpty {
                                Text("No commands found")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(10)
                            } else {
                                commandRows(orderedCommands)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.2), value: viewModel.automaticallyRankCommands)
            .animation(.easeInOut(duration: 0.2), value: viewModel.launcherManualCommandOrder)
            .onAppear {
                navigationState.register(title: "Settings.Launcher.Command.Name", tab: .launcher, keywords: ["reorder", "arrange", "sequence", "position", "move", "rank"])
            }
            .onDisappear {
                if !isPreRendering {
                    navigationState.unregister(title: "Settings.Launcher.Command.Name", tab: .launcher)
                }
            }
            .environment(\.settingsTab, .launcher)
        }
    }
    
    private var orderedCommands: [LauncherCommand] {
        viewModel.manualCommandOrder.compactMap { id in
            viewModel.allCommands.first(where: { $0.id == id })
        }
    }

    @ViewBuilder
    private func commandRows(_ commands: [LauncherCommand]) -> some View {
        ReorderableSettingsList(
            items: commands,
            rowContent: { command, items in
                commandRow(for: command, in: items)
            },
            dragPreview: { command in
                dragPreview(for: command)
            },
            moveBefore: { sourceID, targetID in
                rearrange(sourceID, before: targetID)
            },
            moveToEnd: { sourceID in
                viewModel.moveCommandToEnd(id: sourceID)
            }
        )
    }

    private func commandRow(for command: LauncherCommand, in commands: [LauncherCommand]) -> some View {
        let commandIndex = commands.firstIndex(where: { $0.id == command.id }) ?? 0

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                    .accessibilityLabel("Drag to rearrange")
                Text("\(commandIndex + 1)")
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if command.id != commands.last?.id {
                Divider().padding(.leading, 12)
            }
        }
    }

    private func dragPreview(for command: LauncherCommand) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 16)

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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minWidth: 320, alignment: .leading)
        .contentShape(.dragPreview, Rectangle())
        .background(SettingsSectionStyle.rowBackgroundColor)
    }

    private func rearrange(_ sourceID: String, before targetID: String) -> Bool {
        guard sourceID != targetID else { return false }
        viewModel.moveCommand(id: sourceID, before: targetID)
        return true
    }
}
