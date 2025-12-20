import Foundation
import AppKit
import SwiftUI

struct LogEntry: Identifiable, CustomStringConvertible {
    let id = UUID()
    let timestamp: Date
    let spaceUUID: String
    let isDesktop: Bool
    let action: String
    
    var description: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timeString = formatter.string(from: timestamp)
        // Updated description to show Desktop status instead of NC Count
        return "[\(timeString)] ACTION: \(action) | UUID: \(spaceUUID) | Desktop: \(isDesktop)"
    }
}

class SpaceManager: ObservableObject {
    static private let spacesKey = "com.michaelqiu.desktoprenamer.spaces"
    static private let isAPIEnabledKey = "com.michaelqiu.desktoprenamer.isapienabled"
    static private let isManualSpacesEnabledKey = "com.michaelqiu.desktoprenamer.ismanualspacesenabled"
    
    @Published private(set) var currentSpaceUUID: String = ""
    @Published private(set) var currentRawSpaceUUID: String = ""
    @Published private(set) var currentDisplayID: String = "Main"
    
    @Published var spaceNameDict: [DesktopSpace] = []
    @Published var currentNcCount: Int = 0
    // Renamed for clarity, though internal logic mainly uses the new Bool
    @Published var currentIsDesktop: Bool = false
    
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
        
        SpaceHelper.startMonitoring { [weak self] rawUUID, isDesktop, displayID in
            self?.handleSpaceChange(rawUUID, isDesktop: isDesktop, displayID: displayID, source: "Monitor")
        }
    }
    
    func refreshSpaceState() {
        SpaceHelper.getRawSpaceUUID { [weak self] rawUUID, isDesktop, displayID in
            self?.handleSpaceChange(rawUUID, isDesktop: isDesktop, displayID: displayID, source: "Refresh")
        }
    }
    
    // UPDATED: Now takes isDesktop (Bool)
    private func handleSpaceChange(_ rawUUID: String, isDesktop: Bool, displayID: String, source: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.handleSpaceChange(rawUUID, isDesktop: isDesktop, displayID: displayID, source: source) }
            return
        }
        
        self.currentIsDesktop = isDesktop
        self.currentRawSpaceUUID = rawUUID
        self.currentDisplayID = displayID
        
        var logicalUUID = rawUUID
        
        if SpaceManager.isManualSpacesEnabled {
            logicalUUID = rawUUID
        } else {
            // NEW LOGIC: Use the boolean directly.
            // If the Finder Desktop window is missing, it's a Fullscreen App.
            if !isDesktop {
                logicalUUID = "FULLSCREEN"
            }
        }
        
        if isBugReportActive {
            let action = (currentSpaceUUID != logicalUUID) ? "Space Switched (\(source))" : "State Check (\(source))"
            let entry = LogEntry(timestamp: Date(), spaceUUID: rawUUID, isDesktop: isDesktop, action: "\(action) [\(displayID)]")
            bugReportLog.append(entry)
        }
        
        if currentSpaceUUID != logicalUUID {
            currentSpaceUUID = logicalUUID
        }
        
        if !SpaceManager.isManualSpacesEnabled && logicalUUID != "FULLSCREEN" {
            if !spaceNameDict.contains(where: { $0.id == logicalUUID }) {
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
    
    func addManualSpace(_ uuid: String) {
        guard uuid != "FULLSCREEN", !spaceNameDict.contains(where: { $0.id == uuid }) else { return }
        
        let existingSpacesOnDisplay = spaceNameDict.filter { $0.displayID == currentDisplayID }
        let maxNum = existingSpacesOnDisplay.map { $0.num }.max() ?? 0
        let newNum = maxNum + 1
        
        spaceNameDict.append(DesktopSpace(id: uuid, customName: "", num: newNum, displayID: currentDisplayID))
        saveSpaces()
        refreshSpaceState()
    }
    
    func startBugReportLogging() {
        bugReportLog = [LogEntry(timestamp: Date(), spaceUUID: currentRawSpaceUUID, isDesktop: currentIsDesktop, action: "--- START ---")]
        isBugReportActive = true
    }

    func stopBugReportLogging() {
        bugReportLog.append(LogEntry(timestamp: Date(), spaceUUID: currentRawSpaceUUID, isDesktop: currentIsDesktop, action: "--- STOP ---"))
        isBugReportActive = false
    }
    
    // ... [Rest of the class (loadSavedSpaces, saveSpaces, getSpaceNum, etc) remains exactly the same] ...
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
