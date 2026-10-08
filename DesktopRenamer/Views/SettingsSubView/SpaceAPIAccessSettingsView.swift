import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SpaceAPIAccessSettingsView: View {
    @ObservedObject var accessController: SpaceAPIAccessController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SpaceAPI Access")
                .font(.title2.weight(.semibold))

            Toggle(
                "Allow only approved apps",
                isOn: Binding(
                    get: { accessController.isRestrictedForSettings },
                    set: { accessController.setRestricted($0) }
                )
            )
            Text("When enabled, unapproved apps cannot read or change spaces through SpaceAPI.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let errorMessage = accessController.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Approved Apps")
                    .font(.headline)
                Spacer()
                Button("Add App…", action: chooseApplication)
            }

            if accessController.approvedClients.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text("No Approved Apps")
                        .font(.headline)
                    Text("An empty list blocks every app while access restriction is enabled.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(accessController.approvedClients) { client in
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: client.applicationPath))
                            .resizable()
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(client.name)
                                .lineLimit(1)
                            Text(client.identityDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            accessController.revokeClient(id: client.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Revoke access")
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset)
            }

            Text("Ad-hoc development builds must be approved again after the app is rebuilt.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 520)
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
