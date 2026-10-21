import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SpaceAPIAccessSettingsView: View {
    @ObservedObject var accessController: SpaceAPIAccessController
    @Environment(\.dismiss) private var dismiss

    @State private var showPolicyRepairConfirmation = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("SpaceAPI Access")
                    .font(.title2.weight(.semibold))
                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SettingsSection("Access Policy") {
                        SettingsRow("Allow only approved apps") {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { accessController.isRestrictedForSettings },
                                    set: { accessController.setRestricted($0) }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }

                        if let errorMessage = accessController.errorMessage {
                            Divider()

                            SettingsRow("Policy status") {
                                HStack(spacing: 8) {
                                    Text(errorMessage)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                        .multilineTextAlignment(.trailing)
                                        .fixedSize(horizontal: false, vertical: true)

                                    if accessController.canRepairPolicy {
                                        Button("Reset") {
                                            showPolicyRepairConfirmation = true
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if accessController.isRestrictedForSettings {
                        SettingsSection(
                            "App Permissions",
                            helperText: "Set the access level for each approved app."
                        ) {
                            SettingsRow(
                                "Add an app",
                                helperText: "Development builds must be approved again after rebuilding."
                            ) {
                                Button("Choose…", action: chooseApplication)
                            }

                            if accessController.approvedClients.isEmpty {
                                Divider()

                                SettingsRow("No apps added") {
                                    Text("All apps are blocked while access restriction is enabled.")
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.trailing)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } else {
                                ForEach(accessController.approvedClients) { client in
                                    Divider()

                                    SettingsRow(
                                        LocalizedStringResource(stringLiteral: client.name),
                                        leadingIcon: NSWorkspace.shared.icon(forFile: client.applicationPath)
                                    ) {
                                        HStack(spacing: 8) {
                                            Picker(
                                                "Access for \(client.name)",
                                                selection: Binding(
                                                    get: { client.accessLevel },
                                                    set: { accessController.setAccessLevel(forClientID: client.id, to: $0) }
                                                )
                                            ) {
                                                Text("No Access").tag(SpaceAPIClientAccessLevel.noAccess)
                                                Text("Read Only").tag(SpaceAPIClientAccessLevel.readOnly)
                                                Text("Read & Write").tag(SpaceAPIClientAccessLevel.fullAccess)
                                            }
                                            .labelsHidden()
                                            .pickerStyle(.menu)
                                            .frame(width: 128)
                                            .disabled(!accessController.isRestrictedForSettings)

                                            Button {
                                                accessController.revokeClient(id: client.id)
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                            .buttonStyle(.borderless)
                                            .help("Remove app")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 560, height: 540)
        .environment(\.settingsTab, .general)
        .confirmationDialog(
            "Reset SpaceAPI access?",
            isPresented: $showPolicyRepairConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                accessController.repairUnreadablePolicy()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Resetting the unreadable policy clears the app permissions. SpaceAPI stays restricted until permissions are set again.")
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = NSLocalizedString("Approve an App for SpaceAPI", comment: "")
        panel.message = NSLocalizedString("Choose the app that may use SpaceAPI.", comment: "")
        panel.prompt = NSLocalizedString("Approve", comment: "")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                accessController.approveApplication(at: url)
            }
        }
    }
}
