import AppKit
import ServiceManagement
import SwiftUI

// Helper class for testing SpaceAPI functionality.
class APITester: ObservableObject {
    @Published var responseText: String = ""

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleCurrentSpaceResponse(_:)),
            name: SpaceAPI.returnActiveSpace, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAllSpacesResponse(_:)), name: SpaceAPI.returnSpaceList,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func sendCurrentSpaceRequest() {
        responseText = "Requesting current space..."
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.getActiveSpace, object: nil, userInfo: nil, deliverImmediately: true)
    }

    func sendAllSpacesRequest() {
        responseText = "Requesting all spaces..."
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.getSpaceList, object: nil, userInfo: nil, deliverImmediately: true)
    }

    @objc private func handleCurrentSpaceResponse(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let userInfo = notification.userInfo else {
                self.responseText = "Received empty response"
                return
            }
            let name = userInfo["spaceName"] as? String ?? "N/A"
            let num =
                (userInfo["spaceNumber"] as? NSNumber)?.intValue
                ?? (userInfo["spaceNumber"] as? Int) ?? -1
            let uuid = userInfo["spaceUUID"] as? String ?? "N/A"
            self.responseText = "Current Space:\nName: \(name)\n#: \(num)\nUUID: \(uuid)"
        }
    }

    @objc private func handleAllSpacesResponse(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let userInfo = notification.userInfo,
                let spaces = userInfo["spaces"] as? [[String: Any]]
            else {
                self.responseText = "Received empty space list"
                return
            }
            var result = "All Spaces (\(spaces.count)):\n"
            for space in spaces {
                let name = space["spaceName"] as? String ?? "N/A"
                let num = (space["spaceNumber"] as? NSNumber)?.intValue ?? -1
                let uuid = (space["spaceUUID"] as? String)?.prefix(8) ?? "N/A"
                result += "#\(num): \(name) [\(uuid).. ]\n"
            }
            self.responseText = result
        }
    }
}

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


    var body: some View {
        SettingsContainer(.general) {
            VStack(alignment: .leading, spacing: 20) {
                // General configuration options.
                SettingsSection("Settings.General.General") {
                    SettingsRow(
                        "Show preview labels",
                        helperText: "The large label visible in Mission Control."
                    ) {
                        Toggle("", isOn: $labelManager.showPreviewLabels)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    Divider()
                
                    SettingsRow(
                        "Show active space labels",
                        helperText:
                            "The hidden label that slides into the corner of the active desktop.",
                    ) {
                        Toggle("", isOn: $labelManager.showActiveLabels)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
                
                SettingsSection(nil) {
                    SettingsRow(
                        "Hide menubar icon",
                        helperText:
                            "By doing so, you can turn DesktopRenamer into a completely silent API app."
                    ) {
                        Toggle("", isOn: $isStatusBarHidden)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: isStatusBarHidden) { _ in
                                StatusBarController.toggleStatusBar()
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

                    SettingsRow("Settings.General.Updates.ManualCheck") {
                        Button(NSLocalizedString("Settings.General.Updates.Button", comment: "")) {
                            checkForUpdate()
                        }
                    }
                }

                SettingsSection("Settings.General.Advanced") {
                    SettingsRow(
                        "Settings.General.Advanced.EnableAPI",
                        helperText: "Allow other apps to get space names."
                    ) {
                        Toggle("", isOn: $isAPIEnabled).labelsHidden().toggleStyle(.switch)
                            .onChange(of: isAPIEnabled) { _ in
                                spaceManager.spaceAPI?.toggleAPIState()
                            }
                    }

                    Divider()

                    SettingsRow(
                        "Diagnostic Report",
                        helperText: "Start collection, reproduce the bug, then stop and save the full diagnostic report."
                    ) {
                        Button("Open") {
                            showDiagnosticSheet = true
                        }
                    }

                    Divider()

                    SettingsRow("Review Splash", helperText: "View the welcome screen again.") {
                        Button("Review") {
                            AppDelegate.shared.showSplashScreen(on: NSApp.suitableSheetWindow)
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
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .environment(\.settingsTab, .general)
        }
        .onAppear { launchAtLogin = getLaunchAtLoginState() }
        .sheet(isPresented: $showDiagnosticSheet) {
            DiagnosticSheetView()
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
        UpdateManager.shared.updaterController.checkForUpdates(nil)
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
        @State private var phase: Phase = .idle
        @State private var refreshCounter = 0
        @State private var timer: Timer? = nil
        @State private var savedURL: URL? = nil

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
                    try? data.write(to: url)
                    self.savedURL = url
                    self.phase = .saved
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
