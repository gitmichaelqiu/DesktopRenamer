import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SpaceAPIAccessSettingsView: View {
    @ObservedObject var accessController: SpaceAPIAccessController
    @ObservedObject var usageStatistics: SpaceAPIUsageStatistics
    @Environment(\.dismiss) private var dismiss

    @State private var showPolicyRepairConfirmation = false
    @State private var selectedUsage: SpaceAPIUsageStatistics.AppUsage?
    @AppStorage("spaceAPIUsageRange") private var usageRange = SpaceAPIUsageRange.last7Days
    @State private var showClearUsageConfirmation = false

    var body: some View {
        VStack(spacing: 12) {
            if let selectedUsage {
                SpaceAPIUsageReportView(
                    usage: selectedUsage,
                    selectedRange: $usageRange,
                    usageStatistics: usageStatistics,
                    onBack: { self.selectedUsage = nil },
                    onDone: { dismiss() }
                )
            } else {
                accessSettingsContent
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
        .alert("Clear SpaceAPI usage history?", isPresented: $showClearUsageConfirmation) {
            Button("Clear", role: .destructive) {
                usageStatistics.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all recorded SpaceAPI usage counts and history.")
        }
    }

    private var accessSettingsContent: some View {
        VStack(spacing: 12) {
            HStack {
                Text("SpaceAPI Access")
                    .font(.title2.weight(.semibold))
                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let request = accessController.pendingApprovalRequest {
                        SettingsSection(
                            "Access Request",
                            helperText: "Choose what this app can do with SpaceAPI."
                        ) {
                            SettingsRow(
                                LocalizedStringResource(stringLiteral: request.name),
                                leadingIcon: NSWorkspace.shared.icon(forFile: request.applicationPath)
                            ) {
                                HStack(spacing: 6) {
                                    Button("Don't Allow") {
                                        accessController.resolvePendingApproval(with: .noAccess)
                                    }
                                    Button("Read Only") {
                                        accessController.resolvePendingApproval(with: .readOnly)
                                    }
                                    Button("Read & Write") {
                                        accessController.resolvePendingApproval(with: .fullAccess)
                                    }
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(.easeInOut(duration: 0.2), value: request.id)
                    }

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
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            } else {
                                ForEach(accessController.approvedClients) { client in
                                    VStack(spacing: 0) {
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
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        accessController.revokeClient(id: client.id)
                                                    }
                                                } label: {
                                                    Image(systemName: "trash")
                                                }
                                                .buttonStyle(.borderless)
                                                .help("Remove app")
                                            }
                                        }
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                    }

                    SettingsSection(
                        "Usage Statistics",
                        helperText: "Keeps hourly request history for 7 days and a lifetime total. Request contents aren’t saved; legacy notification calls can’t be attributed."
                    ) {
                        SettingsRow("Record SpaceAPI usage") {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { usageStatistics.isEnabled },
                                    set: { usageStatistics.isEnabled = $0 }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }

                        if usageStatistics.appUsages.isEmpty {
                            Divider()
                            SettingsRow("No app usage recorded") {
                                Text("—")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Divider()
                            SettingsRow("Activity period") {
                                SpaceAPIUsageRangePicker(selection: $usageRange)
                            }

                            ForEach(usageStatistics.appUsages) { usage in
                                Divider()
                                SettingsRow(
                                    LocalizedStringResource(stringLiteral: usage.name),
                                    leadingIcon: NSWorkspace.shared.icon(forFile: usage.applicationPath)
                                ) {
                                    Button {
                                        selectedUsage = usage
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(displayedRequestCount(for: usage), format: .number)
                                                .monospacedDigit()
                                            if usage.hasDetailedHistory {
                                                Text("requests /")
                                                Text(usageRange.compactTitle)
                                            } else {
                                                Text("total requests")
                                            }
                                            Image(systemName: "chevron.right")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(minHeight: 24)
                                    }
                                    .buttonStyle(.plain)
                                    .help("View usage activity")
                                }
                            }

                            Divider()
                            SettingsRow("Usage history") {
                                Button("Clear", role: .destructive) {
                                    showClearUsageConfirmation = true
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
    }

    private func displayedRequestCount(for usage: SpaceAPIUsageStatistics.AppUsage) -> Int {
        guard usage.hasDetailedHistory else { return usage.requestCount }
        let buckets = usageRange == .last24Hours
            ? usageStatistics.hourlyActivity(for: usage.id)
            : usageStatistics.dailyActivity(for: usage.id)
        return buckets.reduce(0) { $0 + $1.requestCount }
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
        guard let window = NSApp.suitableSheetWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.2)) {
                    accessController.approveApplication(at: url)
                }
            }
        }
    }
}
