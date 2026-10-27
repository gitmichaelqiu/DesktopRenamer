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
            Text("Resetting the unreadable policy clears app permissions. SpaceAPI and AppleScript stay restricted until access is configured again.")
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
                    SettingsSection("Access Policy") {
                        SettingsRow(
                            "Allow only approved apps",
                            helperText: "Some older clients only work when access is unrestricted."
                        ) {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { accessController.isRestrictedForSettings },
                                    set: { value in
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            accessController.setRestricted(value)
                                        }
                                    }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }

                        if let errorMessage = accessController.errorMessage {
                            Divider()

                            SettingsRow(
                                "Policy status",
                                warningText: LocalizedStringKey(errorMessage)
                            ) {
                                if accessController.canRepairPolicy {
                                    Button("Reset") {
                                        showPolicyRepairConfirmation = true
                                    }
                                }
                            }
                        }
                    }

                    if accessController.isRestrictedForSettings {
                        SettingsSection(
                            "App Permissions",
                            helperText: "App access levels apply to both restricted APIs."
                        ) {
                            SettingsRow(
                                "Add an app",
                                helperText: "Development builds must be approved again after rebuilding."
                            ) {
                                Button("Choose…", action: chooseApplication)
                            }

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
                                                    set: { value in
                                                        withAnimation(.easeInOut(duration: 0.2)) {
                                                            accessController.setAccessLevel(forClientID: client.id, to: value)
                                                        }
                                                    }
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
                        .animation(
                            .easeInOut(duration: 0.2),
                            value: accessController.approvedClients.map(\.id)
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(
                            .easeInOut(duration: 0.2),
                            value: accessController.isRestrictedForSettings
                        )
                    }

                    SettingsSection(
                        "Usage Statistics",
                        helperText: "Settings.SpaceAPI.UsageStatistics.Helper"
                    ) {
                        SettingsRow("Record SpaceAPI usage") {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { usageStatistics.isEnabled },
                                    set: { value in
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            usageStatistics.isEnabled = value
                                        }
                                    }
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
                                    .frame(minHeight: 24)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
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
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            Divider()
                            SettingsRow("Usage history") {
                                Button("Clear", role: .destructive) {
                                    showClearUsageConfirmation = true
                                }
                            }
                        }
                    }
                    .animation(
                        .easeInOut(duration: 0.2),
                        value: usageStatistics.appUsages.map(\.id)
                    )
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
