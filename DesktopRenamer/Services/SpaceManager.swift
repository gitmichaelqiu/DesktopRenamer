import Foundation
import AppKit
import SwiftUI

let POLL_INTERVAL = 0.8

// New struct for log entries
struct LogEntry: Identifiable, CustomStringConvertible {
    let id = UUID()
    let timestamp: Date
    let spaceUUID: String
    let ncCount: Int
    let action: String
    
    var description: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timeString = formatter.string(from: timestamp)
        return "[\(timeString)] ACTION: \(action) | UUID: \(spaceUUID) | NCCount: \(ncCount)"
    }
}


class SpaceManager: ObservableObject {
    static private let spacesKey = "com.michaelqiu.desktoprenamer.spaces"
    static private let isStableEnabledKey = "com.michaelqiu.desktoprenamer.isstableenabled"
    static private let isAPIEnabledKey = "com.michaelqiu.desktoprenamer.isapienabled"
    
    @Published private(set) var currentSpaceUUID: String = ""
    @Published var spaceNameDict: [DesktopSpace] = []
    
    // New Log properties
    @Published var isBugReportActive: Bool = false
    @Published private(set) var bugReportLog: [LogEntry] = []
    
    static var isAPIEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: isAPIEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: isAPIEnabledKey) }
    }
    static var isStableEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: isStableEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: isStableEnabledKey) }
    }
    
    private var pollingTimer: Timer?
    
    public var currentTotalSpace = 0
    
    // Keep reference to API
    public var spaceAPI: SpaceAPI?
    
    init() {
        loadSavedSpaces()
        
        // Initialize API
        self.spaceAPI = SpaceAPI(spaceManager: self)
        
        // Set initial state based on saved setting
        if SpaceManager.isAPIEnabled {
            self.spaceAPI?.setupListener()
            
            DistributedNotificationCenter.default().postNotificationName(
                SpaceAPI.apiToggleNotification,
                object: nil,
                userInfo: ["isEnabled": true],
                deliverImmediately: true
            )
            print("SpaceAPI: Sent Toggle Notification -> true")
        } else {
            self.spaceAPI?.removeListener()
        }
        
        // FIX: Update SpaceHelper monitoring to use the new signature (UUID and ncCount)
        SpaceHelper.startMonitoring { [weak self] newSpaceUUID, ncCnt in
            self?.handleSpaceChange(newSpaceUUID, ncCount: ncCnt, source: "Monitor")
        }
        
        if SpaceManager.isStableEnabled {
            startPolling()
        }
    }
    
    func togglePolling() {
        SpaceManager.isStableEnabled.toggle()
        
        if SpaceManager.isStableEnabled {
            startPolling()
        } else {
            stopPolling()
        }
    }
    
    // MARK: - Bug Report Logging
    
    func startBugReportLogging() {
        // Initial log entry
        bugReportLog = [LogEntry(timestamp: Date(), spaceUUID: currentSpaceUUID, ncCount: -1, action: "--- START LOGGING ---")]
        isBugReportActive = true
    }

    func stopBugReportLogging() {
        // Final log entry
        bugReportLog.append(LogEntry(timestamp: Date(), spaceUUID: currentSpaceUUID, ncCount: -1, action: "--- STOP LOGGING ---"))
        isBugReportActive = false
    }
    
    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(POLL_INTERVAL), repeats: true) { [weak self] _ in
            self?.pollCurrentSpace()
        }
        // Add the timer to the common run loop mode to ensure it fires reliably
        if let timer = pollingTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }
    
    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    private func pollCurrentSpace() {
        // FIX: Update SpaceHelper call to use the new signature
        SpaceHelper.getSpaceUUID { [weak self] newSpaceUUID, ncCnt in
            self?.handleSpaceChange(newSpaceUUID, ncCount: ncCnt, source: "Polling")
        }
    }
    
    func prepareForTermination() {
        print("SpaceManager: Shutting down...")
        stopPolling() // Stop the timer
        // Explicitly send "False" notification
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.apiToggleNotification,
            object: nil,
            userInfo: ["isEnabled": false],
            deliverImmediately: true
        )
        print("SpaceAPI: Sent Toggle Notification -> false")
    }
    
    deinit {
        SpaceHelper.stopMonitoring()
        stopPolling()
    }
    
    // FIX: Update handleSpaceChange signature to include ncCount and source
    private func handleSpaceChange(_ newSpaceUUID: String, ncCount: Int, source: String) {
        if !Thread.isMainThread {
            // FIX: Update recursive call
            DispatchQueue.main.async { [weak self] in self?.handleSpaceChange(newSpaceUUID, ncCount: ncCount, source: source) }
            return
        }
        
        // Logging logic: Log the event immediately if logging is active
        if isBugReportActive {
            let action = (currentSpaceUUID != newSpaceUUID) ? "Space Switched (\(source))" : "State Check (\(source))"
            let entry = LogEntry(timestamp: Date(), spaceUUID: newSpaceUUID, ncCount: ncCount, action: action)
            bugReportLog.append(entry)
        }
        
        guard currentSpaceUUID != newSpaceUUID else {
            return
        }

        currentSpaceUUID = newSpaceUUID // Publishes change and triggers API update
        
        if !spaceNameDict.contains(where: { $0.id == currentSpaceUUID }) && currentSpaceUUID != "FULLSCREEN" {
            currentTotalSpace += 1
            spaceNameDict.append(DesktopSpace(id: currentSpaceUUID, customName: "", num: currentTotalSpace))
            saveSpaces()
        }
    }
    
    private func loadSavedSpaces() {
        if let data = UserDefaults.standard.data(forKey: SpaceManager.spacesKey),
           let spaces = try? JSONDecoder().decode([DesktopSpace].self, from: data) {
            spaceNameDict = spaces
            currentTotalSpace = spaceNameDict.count
        }
    }
    
    public func saveSpaces() {
        if let data = try? JSONEncoder().encode(spaceNameDict) {
            UserDefaults.standard.set(data, forKey: SpaceManager.spacesKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    func getSpaceNum(_ spaceUUID: String) -> Int {
        if spaceUUID == "FULLSCREEN" { return 0 }
        return spaceNameDict.first(where: { $0.id == spaceUUID })?.num ?? -1
    }
    
    func getSpaceName(_ spaceUUID: String) -> String {
        if spaceUUID == "FULLSCREEN" { return "Fullscreen" }
        var ret = spaceNameDict.first(where: {$0.id == spaceUUID})?.customName
        if ret == nil || ret == "" {
            ret = String(format: NSLocalizedString("Space.DefaultName", comment: ""), getSpaceNum(spaceUUID))
        }
        return ret ?? ""
    }
    
    func resetAllNames() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            UserDefaults.standard.removeObject(forKey: SpaceManager.spacesKey)
            self.currentTotalSpace = 0
            self.spaceNameDict.removeAll()
            self.saveSpaces()
            
            // Re-identify the current space after reset
            SpaceHelper.getSpaceUUID { spaceUUID, _ in // Ignore ncCnt here
                self.currentSpaceUUID = spaceUUID
                // Call handleSpaceChange which will ensure the current space is re-added
                // and the API is notified of the fresh state.
                self.handleSpaceChange(spaceUUID, ncCount: -1, source: "Reset")
            }
        }
    }
    
    func renameSpace(_ spaceUUID: String, to newName: String) {
        if let index = spaceNameDict.firstIndex(where: { $0.id == spaceUUID }) {
            spaceNameDict[index].customName = newName
            saveSpaces()
        }
    }
}
