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

    @State private var showLogSheet: Bool = false

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
                        "Generate bug report",
                        helperText:
                            "This generates a log that is helpful for the developers to debug."
                    ) {
                        Button(action: {
                            if spaceManager.isBugReportActive {
                                spaceManager.stopBugReportLogging()
                            } else {
                                spaceManager.startBugReportLogging()
                                showLogSheet = true
                            }
                        }) {
                            Text(spaceManager.isBugReportActive ? "Stop" : "Start")
                        }
                        .keyboardShortcut("b")
                    }

                    Divider()

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
        .sheet(
            isPresented: $showLogSheet,
            onDismiss: { if spaceManager.isBugReportActive { spaceManager.stopBugReportLogging() } }
        ) { bugReportSheet }
        .animation(.easeInOut(duration: 0.2), value: autoCheckUpdate)
    }

    private var bugReportSheet: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Bug Report Log Collection")
                    .font(.title2).fontWeight(.bold)
                Spacer()
            }
            .padding(.bottom, 5)

            Text(
                "Please go through all spaces that may be helpful in analyzing the bug. The log is updating in real-time."
            )
            .font(.body)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.leading)

            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(spaceManager.bugReportLog.indices, id: \.self) { index in
                            let entry = spaceManager.bugReportLog[index]
                            let isLatest = index == spaceManager.bugReportLog.count - 1

                            Text(entry.description)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(
                                    isLatest ? .accentColor : Color(NSColor.controlTextColor)
                                )
                                .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onReceive(spaceManager.$bugReportLog) { log in
                        if let last = log.last {
                            DispatchQueue.main.async {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(height: 250)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )

            HStack {
                Button("Cancel") {
                    spaceManager.stopBugReportLogging()
                    showLogSheet = false
                }
                Spacer()
                Button("Save Log") {
                    saveLog()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
    }

    private func saveLog() {
        let logContent = spaceManager.bugReportLog.map { $0.description }.joined(separator: "\n")
        guard let data = logContent.data(using: .utf8) else { return }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")

        savePanel.nameFieldStringValue = "DesktopRenamer_BugReport_\(timestamp).log"
        savePanel.allowedContentTypes = [.log, .plainText]

        guard let window = NSApp.suitableSheetWindow else { return }

        savePanel.beginSheetModal(for: window) { result in
            if result == .OK, let url = savePanel.url {
                do {
                    try data.write(to: url)
                    self.spaceManager.stopBugReportLogging()
                    self.showLogSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.showThankYouAlert()
                    }
                } catch {
                    print("Error saving file: \(error)")
                }
            }
        }
    }

    private func showThankYouAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Thank You!", comment: "")
        alert.informativeText = NSLocalizedString(
            "The bug report log has been successfully saved. This will greatly help in fixing issues!",
            comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("Button.OK", comment: ""))

        guard let window = NSApp.keyWindow else {
            alert.runModal()
            return
        }

        alert.beginSheetModal(for: window) { _ in }
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
