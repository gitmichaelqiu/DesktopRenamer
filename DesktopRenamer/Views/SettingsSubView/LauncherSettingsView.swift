import SwiftUI

@MainActor
struct LauncherSettingsView: View {
    @EnvironmentObject var spaceManager: SpaceManager
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @ObservedObject var viewModel = LauncherWindowController.shared.viewModel
    @StateObject private var permissionManager = PermissionManager.shared
    @EnvironmentObject var navigationState: SettingsNavigationState
    @Environment(\.isSettingsPreRendering) private var isPreRendering
    @State private var targetedCommandID: String?
    
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
        if #available(macOS 27.0, *) {
            VStack(spacing: 0) {
                ForEach(commands) { command in
                    commandRow(for: command, in: commands)
                }
                .reorderable()
            }
            .reorderContainer(for: LauncherCommand.self) { difference in
                applyNativeReorder(difference)
            }
        } else {
            ForEach(commands) { command in
                commandRow(for: command, in: commands)
                    .draggable(command.id) {
                        dragPreview(for: command)
                    }
                    .dropDestination(for: String.self) { sourceIDs, _ in
                        guard let sourceID = sourceIDs.first else { return false }
                        return rearrange(sourceID, before: command)
                    } isTargeted: { isTargeted in
                        if isTargeted {
                            targetedCommandID = command.id
                        } else if targetedCommandID == command.id {
                            targetedCommandID = nil
                        }
                    }
            }
        }
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
        .contentShape(Rectangle())
        .background(
            targetedCommandID == command.id
                ? Color.accentColor.opacity(0.12)
                : Color.clear
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func dragPreview(for command: LauncherCommand) -> some View {
        Text(command.title)
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func rearrange(_ sourceID: String, before target: LauncherCommand) -> Bool {
        guard sourceID != target.id else { return false }
        viewModel.moveCommand(id: sourceID, before: target.id)
        return true
    }

    @available(macOS 27.0, *)
    private func applyNativeReorder(
        _ difference: ReorderDifference<String, ReorderableSingleCollectionIdentifier>
    ) {
        guard let sourceID = difference.sources.first else { return }

        switch difference.destination.position {
        case .before(let targetID):
            viewModel.moveCommand(id: sourceID, before: targetID)
        case .end:
            viewModel.moveCommandToEnd(id: sourceID)
        }
    }
}
