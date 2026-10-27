import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager

    @StateObject private var apiTester = APITester()

    @State private var launchAtLogin: Bool = false
    @State private var autoCheckUpdate: Bool = UpdateManager.shared.updaterController.updater.automaticallyChecksForUpdates
    @State private var autoDownloadUpdate: Bool = UpdateManager.shared.updaterController.updater.automaticallyDownloadsUpdates
    @State private var isResetting: Bool = false
    @State private var isAPIEnabled: Bool = SpaceManager.isAPIEnabled
    @State private var isStatusBarHidden: Bool = StatusBarController.isStatusBarHidden
    @State private var showDiagnosticSheet: Bool = false
    @State private var showSpaceAPIAccessSettings: Bool = false
    @State private var showSettingsFileError: Bool = false
    @State private var settingsFileErrorTitle: String = ""
    @State private var settingsFileError: String = ""


    var body: some View {
        SettingsContainer(.general) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Settings.General") {
                    SettingsRow(
                        "Hide menubar icon",
                        helperText:
                            "Hide the menu bar icon while DesktopRenamer continues running."
                    ) {
                        Toggle("", isOn: $isStatusBarHidden)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: isStatusBarHidden) { isHidden in
                                if StatusBarController.isStatusBarHidden != isHidden {
                                    StatusBarController.toggleStatusBar()
                                }
                            }
                    }

                    Divider()

                    SettingsRow("Settings.General.General.LaunchAtLogin") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: launchAtLogin) { value in toggleLaunchAtLogin(value) }
                    }
                }

                SettingsSection("Settings.General.Updates") {
                    if !DesktopRenamerIdentity.isLegacyBridge {
                        SettingsRow("Settings.General.Updates.AutoCheckUpdate") {
                            Toggle("", isOn: $autoCheckUpdate).labelsHidden().toggleStyle(.switch)
                                .onChange(of: autoCheckUpdate) { value in
                                    UpdateManager.shared.updaterController.updater.automaticallyChecksForUpdates = value
                                }
                        }
                        Divider()

                        if autoCheckUpdate {
                            SettingsRow("Automatically download updates") {
                                Toggle("", isOn: $autoDownloadUpdate).labelsHidden().toggleStyle(.switch)
                                    .onChange(of: autoDownloadUpdate) { value in
                                        UpdateManager.shared.updaterController.updater.automaticallyDownloadsUpdates = value
                                    }
                            }
                            Divider()
                        }
                    }

                    SettingsRow("Settings.General.Updates.ManualCheck") {
                        Button(
                            DesktopRenamerIdentity.isLegacyBridge
                                ? NSLocalizedString("Migrate", comment: "")
                                : NSLocalizedString("Settings.General.Updates.Button", comment: "")
                        ) {
                            checkForUpdate()
                        }
                    }
                }

                SettingsSection("Settings.General.Advanced") {
                    SettingsRow(
                        "Settings.General.Advanced.EnableAPI",
                        helperText: "Let other apps access your space names.",
                        requirements: [
                            .spaceAPI(isAvailable: spaceManager.spaceAPI != nil)
                        ]
                    ) {
                        Toggle("", isOn: $isAPIEnabled).labelsHidden().toggleStyle(.switch)
                            .onChange(of: isAPIEnabled) { _ in
                                spaceManager.spaceAPI?.toggleAPIState()
                            }
                    }

                    if spaceManager.spaceAPI?.accessController != nil {
                        Divider()

                        SettingsRow("Settings.General.Advanced.ManageSpaceAPIAccess") {
                            Button("Manage…") { showSpaceAPIAccessSettings = true }
                        }
                    }

                }

                SettingsSection(nil) {
                    SettingsRow("Diagnostic report") {
                        Button("Open") {
                            showDiagnosticSheet = true
                        }
                    }

                    Divider()

                    SettingsRow("Review onboarding") {
                        Button("Review") {
                            AppDelegate.shared.showOnboarding(on: NSApp.suitableSheetWindow)
                        }
                    }

                    Divider()

                    SettingsRow("Factory Reset") {
                        Button("Reset") {
                            performFactoryReset()
                        }
                        .foregroundStyle(.red)
                    }
                }

                SettingsSection(nil) {
                    SettingsRow(
                        "Settings.General.Export.Settings",
                        helperText: "Settings.General.Export.Helper"
                    ) {
                        Button("Settings.General.Export.Button") {
                            exportSettings()
                        }
                    }

                    Divider()

                    SettingsRow("Settings.General.Import.Settings") {
                        Button("Settings.General.Import.Button") {
                            importSettings()
                        }
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .environment(\.settingsTab, .general)
        }
        .onAppear { launchAtLogin = getLaunchAtLoginState() }
        .sheet(isPresented: $showDiagnosticSheet) {
            DiagnosticSheetView(spaceManager: spaceManager)
        }
        .sheet(isPresented: $showSpaceAPIAccessSettings) {
            if let spaceAPI = spaceManager.spaceAPI {
                SpaceAPIAccessSettingsView(
                    accessController: spaceAPI.accessController,
                    usageStatistics: spaceAPI.usageStatistics
                )
            }
        }
        .alert(Text(settingsFileErrorTitle), isPresented: $showSettingsFileError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(settingsFileError)
        }
    }

    private func getLaunchAtLoginState() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            let service = SMAppService.mainApp
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            print("Failed to toggle launch at login: \(error)")
            launchAtLogin = getLaunchAtLoginState()
        }
    }

    private func checkForUpdate() {
        if DesktopRenamerIdentity.isLegacyBridge {
            DesktopRenamerBridgeMigrationManager.shared.startMigrationFromUserAction()
            return
        }

        UpdateManager.shared.updaterController.checkForUpdates(nil)
    }

    private func exportSettings() {
        guard let appDelegate = AppDelegate.shared,
              let gestureManager = appDelegate.gestureManager,
              let hotkeyManager = appDelegate.hotkeyManager else {
            presentExportError(NSLocalizedString("Settings.General.Export.Error.Unavailable", comment: ""))
            return
        }

        do {
            let data = try SettingsExportService.makeExport(
                spaceManager: spaceManager,
                labelManager: labelManager,
                gestureManager: gestureManager,
                hotkeyManager: hotkeyManager,
                launcherViewModel: LauncherWindowController.shared.viewModel
            )

            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.showsTagField = false
            panel.allowedContentTypes = [.json]
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            panel.nameFieldStringValue = "DesktopRenamer_Settings_\(formatter.string(from: Date())).json"

            guard let window = NSApp.suitableSheetWindow else {
                presentExportError(NSLocalizedString("Settings.General.Export.Error.Unavailable", comment: ""))
                return
            }

            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    presentExportError(error.localizedDescription)
                }
            }
        } catch {
            presentExportError(error.localizedDescription)
        }
    }

    private func importSettings() {
        guard AppDelegate.shared?.gestureManager != nil,
              AppDelegate.shared?.hotkeyManager != nil else {
            presentSettingsFileError(
                title: "Settings.General.Import.Error.Title",
                message: NSLocalizedString("Settings.General.Import.Error.Unavailable", comment: "")
            )
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.json]

        guard let window = NSApp.suitableSheetWindow else {
            presentSettingsFileError(
                title: "Settings.General.Import.Error.Title",
                message: NSLocalizedString("Settings.General.Import.Error.Unavailable", comment: "")
            )
            return
        }

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try SettingsImportService.readDocument(at: url)
                let plan = try SettingsImportService.makePlan(from: data, spaceManager: spaceManager)
                confirmSettingsImport(plan)
            } catch let error as SettingsImportService.ImportError {
                presentSettingsFileError(
                    title: "Settings.General.Import.Error.Title",
                    message: error.localizedDescription
                )
            } catch {
                presentSettingsFileError(
                    title: "Settings.General.Import.Error.Title",
                    message: NSLocalizedString("Settings.General.Import.Error.Read", comment: "")
                )
            }
        }
    }

    private func confirmSettingsImport(_ plan: SettingsImportService.Plan) {
        guard let appDelegate = AppDelegate.shared,
              let gestureManager = appDelegate.gestureManager,
              let hotkeyManager = appDelegate.hotkeyManager,
              let window = NSApp.suitableSheetWindow else {
            presentSettingsFileError(
                title: "Settings.General.Import.Error.Title",
                message: NSLocalizedString("Settings.General.Import.Error.Unavailable", comment: "")
            )
            return
        }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Settings.General.Import.Confirm.Title", comment: "")
        alert.informativeText = String(
            format: NSLocalizedString("Settings.General.Import.Confirm.Message", comment: ""),
            Int64(plan.spaceNameAssignments.count),
            Int64(plan.unmatchedSpaceNameCount)
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Settings.General.Import.Confirm.Button", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Button.Cancel", comment: ""))

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            SettingsImportService.apply(
                plan,
                spaceManager: spaceManager,
                labelManager: labelManager,
                gestureManager: gestureManager,
                hotkeyManager: hotkeyManager,
                launcherViewModel: LauncherWindowController.shared.viewModel
            )
            isStatusBarHidden = plan.settings.general.isStatusBarHidden
        }
    }

    private func presentExportError(_ message: String) {
        presentSettingsFileError(title: "Settings.General.Export.Error.Title", message: message)
    }

    private func presentSettingsFileError(title: String, message: String) {
        settingsFileErrorTitle = NSLocalizedString(title, comment: "")
        settingsFileError = message
        showSettingsFileError = true
    }

    private func resetNames() {
        isResetting = true

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Settings.General.Reset.Alert.Msg", comment: "")
        alert.informativeText = NSLocalizedString("Settings.General.Reset.Alert.Info", comment: "")
        alert.alertStyle = .warning
        alert.addButton(
            withTitle: NSLocalizedString("Settings.General.Reset.Alert.Reset", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Button.Cancel", comment: ""))

        guard let window = NSApp.keyWindow else {
            isResetting = false
            return
        }

        alert.beginSheetModal(for: window) { response in
            DispatchQueue.main.async {
                self.isResetting = false

                if response == .alertFirstButtonReturn {
                    self.spaceManager.resetAllNames()

                    let successAlert = NSAlert()
                    successAlert.messageText = NSLocalizedString(
                        "Settings.General.Reset.Success.Msg", comment: "")
                    successAlert.informativeText = NSLocalizedString(
                        "Settings.General.Reset.Success.Info", comment: "")
                    successAlert.alertStyle = .informational
                    successAlert.addButton(withTitle: NSLocalizedString("Button.OK", comment: ""))
                    successAlert.beginSheetModal(for: window) { _ in }
                }
            }
        }
    }


    /// Diagnostic collection sheet — start/stop recording and save the report.
    struct DiagnosticSheetView: View {
        @Environment(\.dismiss) var dismiss
        @ObservedObject var spaceManager: SpaceManager
        @State private var phase: Phase = .idle
        @State private var refreshCounter = 0
        @State private var timer: Timer? = nil
        @State private var savedURL: URL? = nil
        @State private var showPolicyRepairConfirmation = false

        enum Phase {
            case idle       // Show "Start" button
            case recording  // Show "Stop" button + hint
            case done       // Show event count + "Save Report"
            case saved      // Show thank-you + link to GitHub Issues
        }

        var body: some View {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Diagnostic Report")
                        .font(.title2).fontWeight(.bold)
                    Spacer()
                }

                if let accessController = spaceManager.spaceAPI?.accessController,
                   accessController.canRepairPolicy {
                    HStack(spacing: 12) {
                        Label(
                            "SpaceAPI access policy could not be verified. Access remains restricted.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)

                        Button("Reset…") {
                            showPolicyRepairConfirmation = true
                        }
                    }
                    .confirmationDialog(
                        "Reset SpaceAPI access?",
                        isPresented: $showPolicyRepairConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Reset", role: .destructive) {
                            accessController.repairUnreadablePolicy()
                            refreshCounter += 1
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Resetting the unreadable policy clears the approved app list. SpaceAPI stays restricted until you approve apps again.")
                    }
                }

                // Phase-specific content
                switch phase {
                case .idle:
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("Click Start to begin recording system events.")
                            .font(.body)
                            .foregroundColor(.secondary)
                        Text("Then reproduce the bug you encountered.")
                            .font(.body)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 20)

                case .recording:
                    VStack(spacing: 8) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 32))
                            .foregroundColor(.red)
                        Text("Recording system events...")
                            .font(.headline)
                            .foregroundColor(.red)
                        Text("Reproduce the bug, then click Stop.")
                            .font(.body)
                            .foregroundColor(.secondary)
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 10)

                case .done:
                    VStack(spacing: 8) {
                        let count = DiagnosticEventLog.shared.sessionEvents.count
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 32))
                            .foregroundColor(.green)
                        Text("Recording complete!")
                            .font(.headline)
                        Text("\(count) events captured.")
                            .font(.body)
                            .foregroundColor(.secondary)
                        Text("Click Save Report to generate the full diagnostic log.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 10)

                case .saved:
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("Thank you!")
                            .font(.title).fontWeight(.bold)

                        Text("Your diagnostic report has been saved.")
                            .font(.body)
                            .foregroundColor(.secondary)

                        if let url = savedURL {
                            Text(url.path)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }

                        Text("Open a GitHub issue and attach the saved file to report the problem.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                }

                // Live log preview
                if phase != .idle && phase != .saved {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Event Log (\(DiagnosticEventLog.shared.sessionEvents.count) recorded, ring buffer: \(DiagnosticEventLog.shared.formattedRing().components(separatedBy: "\n").count) lines)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    let ringLogLines = DiagnosticEventLog.shared.formattedRing().components(separatedBy: "\n")
                    ScrollView {
                        ScrollViewReader { proxy in
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(ringLogLines.enumerated()), id: \.offset) { i, line in
                                    Text(line)
                                        .font(.system(.footnote, design: .monospaced))
                                        .foregroundColor(Color(NSColor.textColor))
                                        .id(i)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onChange(of: refreshCounter) { _ in
                                if !ringLogLines.isEmpty {
                                    proxy.scrollTo(ringLogLines.count - 1, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .frame(height: 200)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
                }
                if phase == .recording || phase == .done {
                    Spacer()
                }

                HStack {
                    if phase == .saved {
                        Button("Close") { cleanup(); dismiss() }
                    } else {
                        Button("Cancel") { cleanup(); dismiss() }
                    }

                    Spacer()

                    switch phase {
                    case .idle:
                        Button("Start Recording") {
                            DiagnosticEventLog.shared.startCollection()
                            phase = .recording
                            startLiveRefresh()
                        }
                        .buttonStyle(.borderedProminent)

                    case .recording:
                        Button("Stop Recording") {
                            DiagnosticEventLog.shared.stopCollection()
                            stopLiveRefresh()
                            refreshCounter += 1
                            phase = .done
                        }
                        .foregroundStyle(Color.red)
                        .buttonStyle(.borderedProminent)
                        .tint(Color.red)

                    case .done:
                        Button("Save Report") {
                            saveReport()
                        }
                        .buttonStyle(.borderedProminent)

                    case .saved:
                        Button("Report on GitHub") {
                            NSWorkspace.shared.open(URL(string: "https://github.com/gitmichaelqiu/DesktopRenamer/issues")!)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
            .frame(minWidth: 620, minHeight: 480)
            .onDisappear { cleanup() }
        }

        private func startLiveRefresh() {
            stopLiveRefresh()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                refreshCounter += 1
            }
        }

        private func stopLiveRefresh() {
            timer?.invalidate()
            timer = nil
        }

        private func cleanup() {
            stopLiveRefresh()
            if DiagnosticEventLog.shared.isCollecting {
                DiagnosticEventLog.shared.stopCollection()
            }
        }

        private func saveReport() {
            let report = DiagnosticReportBuilder.generate()
            guard let data = report.data(using: .utf8) else { return }
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.showsTagField = false
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMdd_HHmmss"
            panel.nameFieldStringValue = "DesktopRenamer_Diagnostic_\(fmt.string(from: Date())).log"
            panel.allowedContentTypes = [.log, .plainText]
            guard let window = NSApp.suitableSheetWindow else { return }
            panel.beginSheetModal(for: window) { result in
                if result == .OK, let url = panel.url {
                    do {
                        try data.write(to: url)
                        self.savedURL = url
                        self.phase = .saved
                    } catch {
                        let alert = NSAlert()
                        alert.messageText = String(localized: "Failed to Save Report")
                        alert.informativeText = error.localizedDescription
                        alert.runModal()
                    }
                } else {
                    self.cleanup()
                    self.dismiss()
                }
            }
        }
    }

    private func performFactoryReset() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Factory Reset", comment: "")
        alert.informativeText = NSLocalizedString(
            "Are you sure? This will delete all your space names and settings. The app will quit immediately.",
            comment: "")
        alert.alertStyle = .critical
        alert.addButton(withTitle: NSLocalizedString("Reset & Quit", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        guard let window = NSApp.suitableSheetWindow else { return }
        alert.beginSheetModal(for: window) { result in
            if result == .alertFirstButtonReturn {
                if let bundleID = Bundle.main.bundleIdentifier {
                    UserDefaults.standard.removePersistentDomain(forName: bundleID)
                }

                NSApp.terminate(nil)
            }
        }
    }
}
