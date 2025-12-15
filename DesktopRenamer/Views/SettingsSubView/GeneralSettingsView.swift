import SwiftUI
import ServiceManagement
import AppKit

// [APITester Class remains unchanged...]
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

struct ThresholdAdjustmentView: View {
    @ObservedObject var spaceManager: SpaceManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var thresholdValue: Int = SpaceHelper.fullscreenThreshold
    
    // Calibration State
    @State private var recordedDesktops: [String: Int] = [:]
    @State private var recordedFullscreens: [String: Int] = [:]
    
    @State private var isRecordingDesktops = false
    @State private var isRecordingFullscreen = false
    
    @State private var suggestionText: String = ""
    @State private var suggestionIsError: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Adjust Fullscreen Threshold")
                .font(.headline)
            
            HStack(alignment: .top, spacing: 30) {
                // LEFT: Manual Edit
                VStack(alignment: .leading, spacing: 10) {
                    Text("Threshold Value")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("Value", value: $thresholdValue, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    
                    Text("Current ncCnt: \(spaceManager.currentNcCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .frame(width: 150)
                
                Divider()
                
                // RIGHT: Debug/Calibration
                VStack(alignment: .leading, spacing: 15) {
                    // Step 1: Desktops
                    VStack(alignment: .leading, spacing: 5) {
                        Text("1. Go through desktops")
                            .font(.subheadline)
                        
                        HStack {
                            Button(isRecordingDesktops ? "Stop" : "Start") {
                                toggleDesktopRecording()
                            }
                            .disabled(isRecordingFullscreen)
                            
                            if !recordedDesktops.isEmpty {
                                Text("Recorded: \(recordedDesktops.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Step 2: Fullscreens
                    VStack(alignment: .leading, spacing: 5) {
                        Text("2. Go through fullscreen")
                            .font(.subheadline)
                        
                        HStack {
                            Button(isRecordingFullscreen ? "Stop" : "Start") {
                                toggleFullscreenRecording()
                            }
                            .disabled(recordedDesktops.isEmpty || isRecordingDesktops)
                            
                            if !recordedFullscreens.isEmpty {
                                Text("Recorded: \(recordedFullscreens.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Suggestion Result
                    if !suggestionText.isEmpty {
                        Text(suggestionText)
                            .font(.caption)
                            .foregroundColor(suggestionIsError ? .red : .blue)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 200)
            }
            .padding()
            
            HStack {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                Spacer()
                Button("Save") {
                    SpaceHelper.fullscreenThreshold = thresholdValue
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 450)
        // Monitor changes to capture data
        .onReceive(spaceManager.$currentSpaceUUID) { uuid in
            recordData(uuid: uuid, ncCnt: spaceManager.currentNcCount)
        }
    }
    
    private func toggleDesktopRecording() {
        if isRecordingDesktops {
            // Stop
            isRecordingDesktops = false
        } else {
            // Start
            recordedDesktops.removeAll()
            recordedFullscreens.removeAll()
            suggestionText = ""
            isRecordingDesktops = true
            // Record current immediately
            recordData(uuid: spaceManager.currentSpaceUUID, ncCnt: spaceManager.currentNcCount)
        }
    }
    
    private func toggleFullscreenRecording() {
        if isRecordingFullscreen {
            // Stop & Calculate
            isRecordingFullscreen = false
            calculateSuggestion()
        } else {
            // Start
            isRecordingFullscreen = true
            // Record current immediately
            recordData(uuid: spaceManager.currentSpaceUUID, ncCnt: spaceManager.currentNcCount)
        }
    }
    
    private func recordData(uuid: String, ncCnt: Int) {
        if isRecordingDesktops {
            recordedDesktops[uuid] = ncCnt
        } else if isRecordingFullscreen {
            // Remove ncCnt with UUID already existed in desktops part
            // (Don't record if this UUID was seen as a desktop)
            if recordedDesktops[uuid] == nil {
                recordedFullscreens[uuid] = ncCnt
            }
        }
    }
    
    private func calculateSuggestion() {
        guard !recordedDesktops.isEmpty, !recordedFullscreens.isEmpty else {
            suggestionText = "Not enough data collected."
            suggestionIsError = true
            return
        }
        
        let minDesktop = recordedDesktops.values.min() ?? 0
        let maxFullscreen = recordedFullscreens.values.max() ?? 0
        
        if minDesktop > maxFullscreen {
            suggestionText = "Suggested Threshold: \(maxFullscreen)"
            suggestionIsError = false
            thresholdValue = maxFullscreen
        } else {
            suggestionText = "The automatic method does not work on your device, please switch to manual method."
            suggestionIsError = true
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
    // Replaced isStableEnabled with isManualSpacesEnabled
    @State private var isManualSpacesEnabled: Bool = SpaceManager.isManualSpacesEnabled
    @State private var isStatusBarHidden: Bool = StatusBarController.isStatusBarHidden
    
    // New state for bug report feature
    @State private var showLogSheet: Bool = false
    // New state for threshold adjustment
    @State private var showThresholdSheet: Bool = false
    
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
                    
                    SettingsRow("Hide menubar icon", helperText: "By doing so, you can turn DesktopRenamer into a completely silent API app.") {
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
                
                SettingsSection("Settings.General.Advanced") {
                    SettingsRow("Settings.General.Advanced.EnableAPI", helperText: "Allow other apps to get space names.") {
                        Toggle("", isOn: $isAPIEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: isAPIEnabled) { _ in
                                spaceManager.spaceAPI?.toggleAPIState()
                            }
                    }
                    
                    Divider()
                    
                    // Replaced "Stable Method" with "Manual Method"
                    SettingsRow("Manually add spaces", helperText: "If enabled, new spaces won't be added automatically. You must add them in the Spaces tab.") {
                        Toggle("", isOn: $isManualSpacesEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: isManualSpacesEnabled) { newValue in
                                SpaceManager.isManualSpacesEnabled = newValue
                            }
                    }
                    
                    // Show Adjust Threshold only if Manual is OFF
                    if !isManualSpacesEnabled {
                        Divider()
                        SettingsRow("Adjust fullscreen threshold") {
                            Button("Adjust") {
                                showThresholdSheet = true
                            }
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
        .sheet(isPresented: $showLogSheet, onDismiss: {
            if spaceManager.isBugReportActive {
                spaceManager.stopBugReportLogging()
            }
        }) {
            bugReportSheet
        }
        .sheet(isPresented: $showThresholdSheet) {
            ThresholdAdjustmentView(spaceManager: spaceManager)
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
        // [Existing resetNames implementation remains unchanged]
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
