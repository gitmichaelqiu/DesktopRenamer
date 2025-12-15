import Foundation
import AppKit
import SwiftUI

// [LogEntry struct remains unchanged]
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
    static private let isAPIEnabledKey = "com.michaelqiu.desktoprenamer.isapienabled"
    static private let isManualSpacesEnabledKey = "com.michaelqiu.desktoprenamer.ismanualspacesenabled"
    
    // "Logical" UUID (may be "FULLSCREEN" based on logic)
    @Published private(set) var currentSpaceUUID: String = ""
    
    // NEW: "Raw" UUID (Always the actual ID from SpaceHelper, never masked as FULLSCREEN by threshold)
    @Published private(set) var currentRawSpaceUUID: String = ""
    
    @Published var spaceNameDict: [DesktopSpace] = []
    @Published var currentNcCount: Int = 0
    
    @Published var isBugReportActive: Bool = false
    @Published private(set) var bugReportLog: [LogEntry] = []
    
    static var isAPIEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: isAPIEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: isAPIEnabledKey) }
    }
    
    static var isManualSpacesEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: isManualSpacesEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: isManualSpacesEnabledKey) }
    }
    
    public var currentTotalSpace = 0
    public var spaceAPI: SpaceAPI?
    
    init() {
        loadSavedSpaces()
        
        self.spaceAPI = SpaceAPI(spaceManager: self)
        
        if SpaceManager.isAPIEnabled {
            self.spaceAPI?.setupListener()
            DistributedNotificationCenter.default().postNotificationName(
                SpaceAPI.apiToggleNotification,
                object: nil,
                userInfo: ["isEnabled": true],
                deliverImmediately: true
            )
        } else {
            self.spaceAPI?.removeListener()
        }
        
        // This callback receives RAW data now
        SpaceHelper.startMonitoring { [weak self] rawUUID, ncCnt in
            self?.handleSpaceChange(rawUUID, ncCount: ncCnt, source: "Monitor")
        }
    }
    
    // NEW: Function to force a refresh of the current state
    func refreshSpaceState() {
        SpaceHelper.getRawSpaceUUID { [weak self] rawUUID, ncCnt in
            self?.handleSpaceChange(rawUUID, ncCount: ncCnt, source: "Refresh")
        }
    }
    
    // [Bug Report methods remain unchanged]
    func startBugReportLogging() {
        bugReportLog = [LogEntry(timestamp: Date(), spaceUUID: currentRawSpaceUUID, ncCount: -1, action: "--- START LOGGING ---")]
        isBugReportActive = true
    }

    func stopBugReportLogging() {
        bugReportLog.append(LogEntry(timestamp: Date(), spaceUUID: currentRawSpaceUUID, ncCount: -1, action: "--- STOP LOGGING ---"))
        isBugReportActive = false
    }
    
    func prepareForTermination() {
        DistributedNotificationCenter.default().postNotificationName(
            SpaceAPI.apiToggleNotification,
            object: nil,
            userInfo: ["isEnabled": false],
            deliverImmediately: true
        )
    }
    
    deinit {
        SpaceHelper.stopMonitoring()
    }
    
    private func handleSpaceChange(_ rawUUID: String, ncCount: Int, source: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.handleSpaceChange(rawUUID, ncCount: ncCount, source: source) }
            return
        }
        
        self.currentNcCount = ncCount
        self.currentRawSpaceUUID = rawUUID
        
        // DETERMINE LOGICAL UUID
        var logicalUUID = rawUUID
        
        if SpaceManager.isManualSpacesEnabled {
            // In Manual Mode, we trust the rawUUID.
            // If it's not in our list, `getSpaceName` will call it "Fullscreen",
            // but we keep the ID valid so the "Add Spaces" UI can see it.
            logicalUUID = rawUUID
        } else {
            // In Auto Mode, we apply the threshold logic here
            if ncCount <= SpaceHelper.fullscreenThreshold {
                logicalUUID = "FULLSCREEN"
            }
        }
        
        // Logging
        if isBugReportActive {
            let action = (currentSpaceUUID != logicalUUID) ? "Space Switched (\(source))" : "State Check (\(source))"
            let entry = LogEntry(timestamp: Date(), spaceUUID: rawUUID, ncCount: ncCount, action: action)
            bugReportLog.append(entry)
        }
        
        guard currentSpaceUUID != logicalUUID else { return }

        currentSpaceUUID = logicalUUID
        
        // Auto-Add Logic (Only if Manual Mode is OFF)
        if !SpaceManager.isManualSpacesEnabled {
            if !spaceNameDict.contains(where: { $0.id == currentSpaceUUID }) && currentSpaceUUID != "FULLSCREEN" {
                currentTotalSpace += 1
                spaceNameDict.append(DesktopSpace(id: currentSpaceUUID, customName: "", num: currentTotalSpace))
                saveSpaces()
            }
        }
    }
    
    func addManualSpace(_ uuid: String) {
        guard uuid != "FULLSCREEN", !spaceNameDict.contains(where: { $0.id == uuid }) else { return }
        
        currentTotalSpace += 1
        spaceNameDict.append(DesktopSpace(id: uuid, customName: "", num: currentTotalSpace))
        saveSpaces()
        
        // Force refresh to update names/status bar immediately
        refreshSpaceState()
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
        
        if let space = spaceNameDict.first(where: { $0.id == spaceUUID }) {
            return space.num
        }
        
        if SpaceManager.isManualSpacesEnabled {
            return 0 // Treat unknown spaces as Fullscreen in manual mode
        }
        
        return -1
    }
    
    func getSpaceName(_ spaceUUID: String) -> String {
        if SpaceManager.isManualSpacesEnabled {
             // If Manual Mode: Unknown UUIDs are visually treated as "Fullscreen"
             if spaceUUID != "FULLSCREEN" && !spaceNameDict.contains(where: { $0.id == spaceUUID }) {
                 return "Fullscreen"
             }
        }
        
        if spaceUUID == "FULLSCREEN" { return "Fullscreen" }
        
        var ret = spaceNameDict.first(where: {$0.id == spaceUUID})?.customName
        if ret == nil || ret == "" {
            ret = String(format: NSLocalizedString("Space.DefaultName", comment: ""), getSpaceNum(spaceUUID))
        }
        return ret ?? ""
    }
    
    // [resetNames and renameSpace remain unchanged]
    func resetAllNames() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            UserDefaults.standard.removeObject(forKey: SpaceManager.spacesKey)
            self.currentTotalSpace = 0
            self.spaceNameDict.removeAll()
            self.saveSpaces()
            
            // Re-identify
            self.refreshSpaceState()
        }
    }
    
    func renameSpace(_ spaceUUID: String, to newName: String) {
        if let index = spaceNameDict.firstIndex(where: { $0.id == spaceUUID }) {
            spaceNameDict[index].customName = newName
            saveSpaces()
        }
    }
}
