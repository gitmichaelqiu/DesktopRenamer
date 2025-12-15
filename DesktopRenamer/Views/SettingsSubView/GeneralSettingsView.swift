import SwiftUI
import ServiceManagement
import AppKit

// [APITester Class remains unchanged...]
class APITester: ObservableObject {
    @Published var responseText: String = ""
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleCurrentSpaceResponse(_:)), name: SpaceAPI.returnActiveSpace, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAllSpacesResponse(_:)), name: SpaceAPI.returnSpaceList, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func sendCurrentSpaceRequest() {
        responseText = "Requesting current space..."
        DistributedNotificationCenter.default().postNotificationName(SpaceAPI.getActiveSpace, object: nil, userInfo: nil, deliverImmediately: true)
    }
    
    func sendAllSpacesRequest() {
        responseText = "Requesting all spaces..."
        DistributedNotificationCenter.default().postNotificationName(SpaceAPI.getSpaceList, object: nil, userInfo: nil, deliverImmediately: true)
    }
    
    @objc private func handleCurrentSpaceResponse(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let userInfo = notification.userInfo else { self.responseText = "Received empty response"; return }
            let name = userInfo["spaceName"] as? String ?? "N/A"
            let num = (userInfo["spaceNumber"] as? NSNumber)?.intValue ?? (userInfo["spaceNumber"] as? Int) ?? -1
            let uuid = userInfo["spaceUUID"] as? String ?? "N/A"
            self.responseText = "Current Space:\nName: \(name)\n#: \(num)\nUUID: \(uuid)"
        }
    }
    
    @objc private func handleAllSpacesResponse(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let userInfo = notification.userInfo, let spaces = userInfo["spaces"] as? [[String: Any]] else { self.responseText = "Received empty space list"; return }
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

struct ThresholdAdjustmentView: View {
    @ObservedObject var spaceManager: SpaceManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var thresholdValue: Int = SpaceHelper.fullscreenThreshold
    
    @State private var recordedDesktops: [String: Int] = [:]
    @State private var recordedFullscreens: [String: Int] = [:]
    
    @State private var isRecordingDesktops = false
    @State private var isRecordingFullscreen = false
    
    @State private var suggestionText: String = ""
    @State private var suggestionIsError: Bool = false
    @State private var showingHelperPopover = false
    
    
    
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 4) {
                Text("Adjust Fullscreen Threshold")
                    .font(.headline)
                
                Button {
                    showingHelperPopover.toggle()
                } label: {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingHelperPopover, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This is the key parameter in the detection of fullscreen.\n\nAt the right hand side, you can acquire a suggested value. You need to go requested desktops or fullscreen (not necessarily all of them). During this process, do not stop at the spaces that do not match the request.\n\nThe threshold should be between the two extreme values shown.\n\nIf all desktops are marked as fullscreen, you may decrease the threshold.")
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(15)
                    .frame(minWidth: 200, maxWidth: 300)
                }
            }
            
            HStack(alignment: .top, spacing: 30) {
                // LEFT: Manual Edit
                VStack(alignment: .leading, spacing: 10) {
                    Text("Threshold Value")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("Value", value: $thresholdValue, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    
                    Text("Current Metric: \(spaceManager.currentNcCount)")
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
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Recorded: \(recordedDesktops.count)")
                                    if let min = recordedDesktops.values.min() {
                                        Text("Min Metric: \(min)")
                                            .foregroundColor(.blue)
                                    }
                                }
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
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Recorded: \(recordedFullscreens.count)")
                                    if let max = recordedFullscreens.values.max() {
                                        Text("Max Metric: \(max)")
                                            .foregroundColor(.orange)
                                    }
                                }
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
                    // REFRESH: Immediately re-evaluate the current space with the new threshold
                    spaceManager.refreshSpaceState()
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 450)
        // CHANGE: Listen to currentRawSpaceUUID to ensure we capture actual data even if logic thinks it's fullscreen
        .onReceive(spaceManager.$currentRawSpaceUUID) { uuid in
            recordData(uuid: uuid, ncCnt: spaceManager.currentNcCount)
        }
    }
    
    private func toggleDesktopRecording() {
        if isRecordingDesktops {
            isRecordingDesktops = false
        } else {
            recordedDesktops.removeAll()
            suggestionText = ""
            isRecordingDesktops = true
            recordData(uuid: spaceManager.currentRawSpaceUUID, ncCnt: spaceManager.currentNcCount)
        }
    }
    
    private func toggleFullscreenRecording() {
        if isRecordingFullscreen {
            isRecordingFullscreen = false
            calculateSuggestion()
        } else {
            recordedFullscreens.removeAll()
            isRecordingFullscreen = true
            recordData(uuid: spaceManager.currentRawSpaceUUID, ncCnt: spaceManager.currentNcCount)
        }
    }
    
    private func recordData(uuid: String, ncCnt: Int) {
        if isRecordingDesktops {
            recordedDesktops[uuid] = ncCnt
        } else if isRecordingFullscreen {
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

struct AddSpacesView: View {
    @ObservedObject var spaceManager: SpaceManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var detectedSpaces: Set<String> = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add New Spaces")
                .font(.headline)
            
            Text("Switch to the desktops you want to add. They will appear in the list below.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            List {
                if detectedSpaces.isEmpty {
                    Text("No new spaces detected yet...")
                        .foregroundColor(.secondary)
                        .italic()
                        .padding()
                } else {
                    ForEach(Array(detectedSpaces).sorted(), id: \.self) { uuid in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("New Space")
                                    .fontWeight(.medium)
                                Text(uuid)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Add") {
                                addSpace(uuid)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(height: 200)
            .border(Color.gray.opacity(0.2))
            
            HStack {
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .padding()
        .frame(width: 400)
        // CHANGE: Listen to raw UUID to capture spaces even if currently treated as fullscreen
        .onReceive(spaceManager.$currentRawSpaceUUID) { uuid in
            checkForNewSpace(uuid)
        }
    }
    
    private func checkForNewSpace(_ uuid: String) {
        // We only add spaces that are NOT "FULLSCREEN" string (safeguard)
        // and are NOT already in the dict.
        if uuid != "FULLSCREEN" && !spaceManager.spaceNameDict.contains(where: { $0.id == uuid }) {
            detectedSpaces.insert(uuid)
        }
    }
    
    private func addSpace(_ uuid: String) {
        spaceManager.addManualSpace(uuid)
        detectedSpaces.remove(uuid)
    }
}

// [GeneralSettingsView remains largely the same, just included to show context]
struct GeneralSettingsView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var labelManager: SpaceLabelManager
    
    @StateObject private var apiTester = APITester()
    
    @State private var launchAtLogin: Bool = false
    @State private var autoCheckUpdate: Bool = UpdateManager.isAutoCheckEnabled
    @State private var isResetting: Bool = false
    @State private var isAPIEnabled: Bool = SpaceManager.isAPIEnabled
    @State private var isManualSpacesEnabled: Bool = SpaceManager.isManualSpacesEnabled
    @State private var isStatusBarHidden: Bool = StatusBarController.isStatusBarHidden
    
    @State private var showLogSheet: Bool = false
    @State private var showThresholdSheet: Bool = false
    @State private var showAddSpacesSheet: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // [General Section omitted for brevity]
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
                            .onChange(of: isStatusBarHidden) { _ in StatusBarController.toggleStatusBar() }
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
                            .onChange(of: autoCheckUpdate) { value in UpdateManager.isAutoCheckEnabled = value }
                    }
                    Divider()
                    SettingsRow("Settings.General.Updates.ManualCheck") {
                        Button(NSLocalizedString("Settings.General.Updates.Button", comment: "")) { checkForUpdate() }
                    }
                }
                
                SettingsSection("Settings.General.Advanced") {
                    SettingsRow("Settings.General.Advanced.EnableAPI", helperText: "Allow other apps to get space names.") {
                        Toggle("", isOn: $isAPIEnabled).labelsHidden().toggleStyle(.switch)
                            .onChange(of: isAPIEnabled) { _ in spaceManager.spaceAPI?.toggleAPIState() }
                    }
                    
                    Divider()
                    
                    SettingsRow("Manually add spaces", helperText: "If enabled, new spaces won't be added automatically. You must add them in the Spaces tab.") {
                        Toggle("", isOn: $isManualSpacesEnabled).labelsHidden().toggleStyle(.switch)
                            .onChange(of: isManualSpacesEnabled) { newValue in
                                SpaceManager.isManualSpacesEnabled = newValue
                                // REFRESH: Re-evaluate current space when mode changes
                                spaceManager.refreshSpaceState()
                            }
                    }
                    
                    if isManualSpacesEnabled {
                        Divider()
                        SettingsRow("Add spaces") {
                            Button("Add") {
                                showAddSpacesSheet = true
                            }
                        }
                    } else {
                        Divider()
                        SettingsRow("Fix automatic detection") {
                            Button("Fix") {
                                showThresholdSheet = true
                            }
                        }
                    }
                    
                    Divider()
                    
                    SettingsRow("Generate bug report", helperText: "This generates a log that is helpful for the developers to debug.") {
                        Button(action: {
                            if spaceManager.isBugReportActive { spaceManager.stopBugReportLogging() }
                            else { spaceManager.startBugReportLogging(); showLogSheet = true }
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
        .onAppear { launchAtLogin = getLaunchAtLoginState() }
        .sheet(isPresented: $showLogSheet, onDismiss: { if spaceManager.isBugReportActive { spaceManager.stopBugReportLogging() } }) { bugReportSheet }
        .sheet(isPresented: $showThresholdSheet) { ThresholdAdjustmentView(spaceManager: spaceManager) }
        .sheet(isPresented: $showAddSpacesSheet) { AddSpacesView(spaceManager: spaceManager) }
        .animation(.easeInOut(duration: 0.2), value: SpaceManager.isManualSpacesEnabled)
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
                        ForEach(spaceManager.bugReportLog.indices, id: \.self) { index in
                            let entry = spaceManager.bugReportLog[index]
                            let isLatest = index == spaceManager.bugReportLog.count - 1
                            
                            Text(entry.description)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(isLatest ? .accentColor : Color(NSColor.controlTextColor))
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
        alert.informativeText = NSLocalizedString("The bug report log has been successfully saved. This will greatly help in fixing issues!", comment: "")
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
