import SwiftUI
import ServiceManagement
import AppKit // Import AppKit for NSColor and NSApp/NSSavePanel

class APITester: ObservableObject {
    @Published var responseText: String = ""
    
    init() {
        // LISTEN to Local Notification Center
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCurrentSpaceResponse(_:)),
            name: SpaceAPI.returnActiveSpace,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAllSpacesResponse(_:)),
            name: SpaceAPI.returnSpaceList,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func sendCurrentSpaceRequest() {
        responseText = "Requesting current space..."
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.getActiveSpace,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
    
    func sendAllSpacesRequest() {
        responseText = "Requesting all spaces..."
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.getSpaceList,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
    
    @objc private func handleCurrentSpaceResponse(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let userInfo = notification.userInfo else {
                self.responseText = "Received empty response"
                return
            }
            
            let name = userInfo["spaceName"] as? String ?? "N/A"
            let num = (userInfo["spaceNumber"] as? NSNumber)?.intValue ?? (userInfo["spaceNumber"] as? Int) ?? -1
            let uuid = userInfo["spaceUUID"] as? String ?? "N/A"
            
            self.responseText = "Current Space:\nName: \(name)\n#: \(num)\nUUID: \(uuid)"
        }
    }
    
    @objc private func handleAllSpacesResponse(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let userInfo = notification.userInfo,
                  let spaces = userInfo["spaces"] as? [[String: Any]] else {
                self.responseText = "Received empty space list"
                return
            }
            
            var result = "All Spaces (\(spaces.count)):\n"
            
            for space in spaces {
                let name = space["spaceName"] as? String ?? "N/A"
                let num = (space["spaceNumber"] as? NSNumber)?.intValue ?? -1
                // Truncate UUID for display
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
    @State private var autoCheckUpdate: Bool = UpdateManager.isAutoCheckEnabled
    @State private var isResetting: Bool = false
    @State private var isAPIEnabled: Bool = SpaceManager.isAPIEnabled
    @State private var isStableEnabled: Bool = SpaceManager.isStableEnabled
    
    // New state for bug report feature
    @State private var showLogSheet: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("Settings.General.General") {
                    SettingsRow("Settings.General.General.ShowLabels", helperText: "Create windows that only appear in Mission Control to display space names.\n\nMay not work when multiple displays are connected.") {
                        Toggle("", isOn: $labelManager.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    
                    Divider()
                    
                    SettingsRow("Settings.General.General.LaunchAtLogin") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: launchAtLogin) { value in
                                toggleLaunchAtLogin(value)
                            }
                    }
                }
                
                SettingsSection("Settings.General.Updates") {
                    SettingsRow("Settings.General.Updates.AutoCheckUpdate") {
                        Toggle("", isOn: $autoCheckUpdate)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: autoCheckUpdate) { value in
                                UpdateManager.isAutoCheckEnabled = value
                            }
                    }
                    
                    Divider()
                    
                    SettingsRow("Settings.General.Updates.ManualCheck") {
                        Button(NSLocalizedString("Settings.General.Updates.Button", comment: "")) {
                            checkForUpdate()
                        }
                    }
                }
                
//                SettingsSection("Settings.General.Reset") {
//                    SettingsRow("Settings.General.Reset.Body") {
//                        Button(NSLocalizedString("Settings.General.Reset.Button", comment: "")) {
//                            resetNames()
//                        }
//                        .disabled(isResetting)
//                    }
//                }
                
                SettingsSection("Settings.General.Advanced") {
                    SettingsRow("Settings.General.Advanced.EnableAPI", helperText: "Allow other apps to get space names.") {
                        Toggle("", isOn: $isAPIEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: isAPIEnabled) { _ in
                                // Calling toggleAPIState handles SpaceManager.isAPIEnabled.toggle()
                                spaceManager.spaceAPI?.toggleAPIState()
                            }
                    }
                    
                    Divider()
                    
                    SettingsRow("Use stable space detection method", helperText: "This method is more stable than the normal one. It detects space every \(String(format: "%.2f", POLL_INTERVAL))s, slightly increasing the energy cost.\n\nNotice, the space name may update twice every time you switch the space, and you may also see the name of the main space appears shortly.") {
                        Toggle("", isOn: $isStableEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: isStableEnabled) { _ in
                                // togglePolling handles SpaceManager.isStableEnabled.toggle()
                                spaceManager.togglePolling()
                            }
                    }
                    
                    Divider()
                    
                    SettingsRow("Generate bug report", helperText: "This generates a log that is helpful for the developers to debug. The log includes the following information:\n\n1. SpaceUUIDs (not your customized name)\n2. A number representing the notification center amount (does not contain sensitive information, just a number)") {
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
                }
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            launchAtLogin = getLaunchAtLoginState()
        }
        // FIX 2: Add an onDismiss handler to sheet to stop logging if the user closes the sheet
        // using the Escape key or clicking outside (default sheet dismissal behavior).
        .sheet(isPresented: $showLogSheet, onDismiss: {
            if spaceManager.isBugReportActive {
                spaceManager.stopBugReportLogging()
            }
        }) {
            bugReportSheet
        }
    }
    
    private var bugReportSheet: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Bug Report Log Collection")
                    .font(.title2).fontWeight(.bold)
                Spacer()
            }
            .padding(.bottom, 5)
            
            Text("Please go through all spaces that may be helpful in analyzing the bug. The log is updating in real-time.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
            
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 4) {
                        // Display log entries in normal chronological order (newest at bottom)
                        ForEach(spaceManager.bugReportLog.indices, id: \.self) { index in
                            let entry = spaceManager.bugReportLog[index]
                            let isLatest = index == spaceManager.bugReportLog.count - 1
                            
                            Text(entry.description)
                                .font(.system(.footnote, design: .monospaced))
                                // Use accent color for the newest line, white for previous lines
                                .foregroundColor(isLatest ? .accentColor : Color(NSColor.controlTextColor))
                                .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // FIX 1: Scroll to bottom when log is updated
                    .onReceive(spaceManager.$bugReportLog) { log in
                        if let last = log.last {
                            // Scroll to the newest item (which is the last item)
                            // This must be done on the next run loop cycle to ensure the view size has updated.
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
            .border(Color.secondary.opacity(0.3), width: 1)
            
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
                .tint(.accentColor)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
    }
    
    private func saveLog() {
        // Convert log entries to a single string
        let logContent = spaceManager.bugReportLog.map { $0.description }.joined(separator: "\n")
        guard let data = logContent.data(using: .utf8) else { return }
        
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        
        // Use ISO8601 for a machine-readable timestamp in the filename
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        
        savePanel.nameFieldStringValue = "DesktopRenamer_BugReport_\(timestamp).log"
        // Ensure .log type is available
        savePanel.allowedContentTypes = [.log, .plainText]
        
        // Get the window for sheet presentation (using the extension in UpdateManager)
        // This is the window the bugReportSheet is attached to.
        guard let window = NSApp.suitableSheetWindow else { return }
        
        savePanel.beginSheetModal(for: window) { result in
            if result == .OK, let url = savePanel.url {
                do {
                    try data.write(to: url)
                    
                    // Corrected the sequence of closing the log sheet and showing the thank you alert.
                    // 1. Stop logging and close the initial sheet immediately.
                    self.spaceManager.stopBugReportLogging()
                    self.showLogSheet = false
                    
                    // 2. Schedule the thank you alert to be shown on the main thread AFTER a slight delay.
                    // This ensures the first sheet (bug report log) has fully dismissed before the second sheet (alert) begins.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                         self.showThankYouAlert()
                    }

                } catch {
                    print("Error saving file: \(error)")
                    // Optionally show an error alert
                }
            } else if result == .cancel {
                // User cancelled save, keep the sheet open and logging active
            }
        }
    }

    private func showThankYouAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Thank You!", comment: "")
        alert.informativeText = NSLocalizedString("The bug report log has been successfully saved. This will greatly help in fixing issues!", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("Button.OK", comment: ""))
        
        // Use keyWindow or suitableSheetWindow for modal presentation
        // Since the bug report sheet is now closed, keyWindow should be the Settings window again.
        guard let window = NSApp.keyWindow else {
            alert.runModal()
            return
        }
        
        // Present the alert as a sheet on the (now visible) settings window
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
        Task {
            await UpdateManager.shared.checkForUpdate(from: nil, suppressUpToDateAlert: false)
        }
    }
    
    private func resetNames() {
        isResetting = true
        
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Settings.General.Reset.Alert.Msg", comment: "")
        alert.informativeText = NSLocalizedString("Settings.General.Reset.Alert.Info", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Settings.General.Reset.Alert.Reset", comment: ""))
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
                    successAlert.messageText = NSLocalizedString("Settings.General.Reset.Success.Msg", comment: "")
                    successAlert.informativeText = NSLocalizedString("Settings.General.Reset.Success.Info", comment: "")
                    successAlert.alertStyle = .informational
                    successAlert.addButton(withTitle: NSLocalizedString("Button.OK", comment: ""))
                    successAlert.beginSheetModal(for: window) { _ in }
                }
            }
        }
    }
}
