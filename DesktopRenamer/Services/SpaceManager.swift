import Foundation
import AppKit
import SwiftUI

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
    
    @Published private(set) var currentSpaceUUID: String = ""
    @Published private(set) var currentRawSpaceUUID: String = ""
    // UPDATED: Track current display
    @Published private(set) var currentDisplayID: String = "Main"
    
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
        }
        
        // UPDATED: Callback signature
        SpaceHelper.startMonitoring { [weak self] rawUUID, ncCnt, displayID in
            self?.handleSpaceChange(rawUUID, ncCount: ncCnt, displayID: displayID, source: "Monitor")
        }
    }
    
    func refreshSpaceState() {
        SpaceHelper.getRawSpaceUUID { [weak self] rawUUID, ncCnt, displayID in
            self?.handleSpaceChange(rawUUID, ncCount: ncCnt, displayID: displayID, source: "Refresh")
        }
    }
    
    // UPDATED: Logic to handle Display ID and separate numbering
    private func handleSpaceChange(_ rawUUID: String, ncCount: Int, displayID: String, source: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.handleSpaceChange(rawUUID, ncCount: ncCount, displayID: displayID, source: source) }
            return
        }
        
        self.currentNcCount = ncCount
        self.currentRawSpaceUUID = rawUUID
        self.currentDisplayID = displayID
        
        var logicalUUID = rawUUID
        
        if SpaceManager.isManualSpacesEnabled {
            logicalUUID = rawUUID
        } else {
            if ncCount <= SpaceHelper.fullscreenThreshold {
                logicalUUID = "FULLSCREEN"
            }
        }
        
        if isBugReportActive {
            let action = (currentSpaceUUID != logicalUUID) ? "Space Switched (\(source))" : "State Check (\(source))"
            let entry = LogEntry(timestamp: Date(), spaceUUID: rawUUID, ncCount: ncCount, action: "\(action) [\(displayID)]")
            bugReportLog.append(entry)
        }
        
        // Check if we need to update state
        if currentSpaceUUID != logicalUUID {
            currentSpaceUUID = logicalUUID
        }
        
        // Auto-Add Logic
        if !SpaceManager.isManualSpacesEnabled && logicalUUID != "FULLSCREEN" {
            // Check if this space is already known
            if !spaceNameDict.contains(where: { $0.id == logicalUUID }) {
                // Determine new number specific to this display
                let existingSpacesOnDisplay = spaceNameDict.filter { $0.displayID == displayID }
                let maxNum = existingSpacesOnDisplay.map { $0.num }.max() ?? 0
                let newNum = maxNum + 1
                
                let newSpace = DesktopSpace(
                    id: logicalUUID,
                    customName: "",
                    num: newNum,
                    displayID: displayID
                )
                
                spaceNameDict.append(newSpace)
                saveSpaces()
            }
        }
    }
    
    // UPDATED: Manual add now needs to know which display the candidate came from.
    // For simplicity, if we add manual space, we assume it comes from the current display if not specified,
    // but the `AddSpacesView` should really track it.
    // Here we will use currentDisplayID for now, or you can update AddSpacesView to pass it.
    func addManualSpace(_ uuid: String) {
        // Warning: This assumes the manual space being added is on the currently active display
        // which is usually true because the user has to visit it to see it in the "Add" list.
        guard uuid != "FULLSCREEN", !spaceNameDict.contains(where: { $0.id == uuid }) else { return }
        
        let existingSpacesOnDisplay = spaceNameDict.filter { $0.displayID == currentDisplayID }
        let maxNum = existingSpacesOnDisplay.map { $0.num }.max() ?? 0
        let newNum = maxNum + 1
        
        spaceNameDict.append(DesktopSpace(id: uuid, customName: "", num: newNum, displayID: currentDisplayID))
        saveSpaces()
        refreshSpaceState()
    }
    
    // ... [Load/Save/Logging methods remain the same] ...
    
    func startBugReportLogging() {
        bugReportLog = [LogEntry(timestamp: Date(), spaceUUID: currentRawSpaceUUID, ncCount: -1, action: "--- START ---")]
        isBugReportActive = true
    }

    func stopBugReportLogging() {
        bugReportLog.append(LogEntry(timestamp: Date(), spaceUUID: currentRawSpaceUUID, ncCount: -1, action: "--- STOP ---"))
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
    
    private func loadSavedSpaces() {
        if let data = UserDefaults.standard.data(forKey: SpaceManager.spacesKey),
           let spaces = try? JSONDecoder().decode([DesktopSpace].self, from: data) {
            spaceNameDict = spaces
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
        return SpaceManager.isManualSpacesEnabled ? 0 : -1
    }
    
    func getSpaceName(_ spaceUUID: String) -> String {
        if SpaceManager.isManualSpacesEnabled {
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
    
    func resetAllNames() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            UserDefaults.standard.removeObject(forKey: SpaceManager.spacesKey)
            self.spaceNameDict.removeAll()
            self.saveSpaces()
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
