import Foundation
import AppKit
import SwiftUI

enum DetectionMethod: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case metric = "Metric-based"
    case manual = "Manual"
    
    var id: String { self.rawValue }
    var localizedName: LocalizedStringKey {
        switch self {
        case .automatic: return "Settings.General.Method.Auto"
        case .metric: return "Settings.General.Method.Metric"
        case .manual: return "Settings.General.Method.Manual"
        }
    }
}

struct LogEntry: Identifiable, CustomStringConvertible {
    let id = UUID()
    let timestamp: Date
    let spaceUUID: String
    let isDesktop: Bool
    let ncCount: Int
    let action: String
    
    var description: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return "[\(formatter.string(from: timestamp))] ACTION: \(action) | UUID: \(spaceUUID) | Desktop: \(isDesktop) | NC: \(ncCount)"
    }
}

class SpaceManager: ObservableObject {
    static private let spacesKey = "com.michaelqiu.desktoprenamer.spaces"
    static private let nameCacheKey = "com.michaelqiu.desktoprenamer.namecache"
    static private let isAPIEnabledKey = "com.michaelqiu.desktoprenamer.isapienabled"
    static private let detectionMethodKey = "com.michaelqiu.desktoprenamer.detectionMethod"
    static private let isManualSpacesEnabledKey = "com.michaelqiu.desktoprenamer.ismanualspacesenabled"
    
    @Published private(set) var currentSpaceUUID: String = ""
    @Published private(set) var currentRawSpaceUUID: String = ""
    @Published private(set) var currentDisplayID: String = "Main"
    
    @Published var spaceNameDict: [DesktopSpace] = []
    // Cache to persist names even if display disconnects
    private var nameCache: [String: String] = [:]
    
    @Published var currentNcCount: Int = 0
    @Published var currentIsDesktop: Bool = false
    
    @Published var isBugReportActive: Bool = false
    @Published private(set) var bugReportLog: [LogEntry] = []
    
    @Published var detectionMethod: DetectionMethod {
        didSet {
            UserDefaults.standard.set(detectionMethod.rawValue, forKey: SpaceManager.detectionMethodKey)
            refreshSpaceState()
        }
    }
    
    var isManualMode: Bool { detectionMethod == .manual }
    
    static var isAPIEnabled: Bool {
        get { UserDefaults.standard.object(forKey: isAPIEnabledKey) == nil ? true : UserDefaults.standard.bool(forKey: isAPIEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: isAPIEnabledKey) }
    }
    
    public var spaceAPI: SpaceAPI?
    
    init() {
        let legacyManual = UserDefaults.standard.bool(forKey: SpaceManager.isManualSpacesEnabledKey)
        let savedMethod = UserDefaults.standard.string(forKey: SpaceManager.detectionMethodKey)
        
        if let saved = savedMethod, let method = DetectionMethod(rawValue: saved) {
            self.detectionMethod = method
        } else if legacyManual {
            self.detectionMethod = .manual
        } else {
            self.detectionMethod = .automatic
        }
        
        loadSavedData()
        self.spaceAPI = SpaceAPI(spaceManager: self)
        
        if SpaceManager.isAPIEnabled {
            self.spaceAPI?.setupListener()
            DistributedNotificationCenter.default().postNotificationName(SpaceAPI.apiToggleNotification, object: nil, userInfo: ["isEnabled": true], deliverImmediately: true)
        }
        
        SpaceHelper.startMonitoring { [weak self] rawUUID, isDesktop, ncCnt, displayID in
            self?.handleSpaceChange(rawUUID, isDesktop: isDesktop, ncCount: ncCnt, displayID: displayID, source: "Monitor")
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersDidChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func screenParametersDidChange() {
        refreshSpaceState()
    }
    
    func refreshSpaceState() {
        SpaceHelper.getRawSpaceUUID { [weak self] rawUUID, isDesktop, ncCnt, displayID in
            self?.handleSpaceChange(rawUUID, isDesktop: isDesktop, ncCount: ncCnt, displayID: displayID, source: "Refresh")
        }
    }
    
    private func handleSpaceChange(_ rawUUID: String, isDesktop: Bool, ncCount: Int, displayID: String, source: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.handleSpaceChange(rawUUID, isDesktop: isDesktop, ncCount: ncCount, displayID: displayID, source: source) }
            return
        }
        
        if detectionMethod == .automatic {
            guard let cgsState = SpaceHelper.getSystemState() else { return }
            
            var newSpaceList: [DesktopSpace] = []
            for sysSpace in cgsState.spaces {
                var finalSpace = sysSpace
                
                // 1. Try to find name in Persistent Cache
                if let cachedName = nameCache[sysSpace.id], !cachedName.isEmpty {
                    finalSpace.customName = cachedName
                }
                // 2. Fallback to existing dict (in case cache missing but dict has it currently)
                else if let existing = spaceNameDict.first(where: { $0.id == sysSpace.id }), !existing.customName.isEmpty {
                    finalSpace.customName = existing.customName
                    // Heal cache
                    nameCache[sysSpace.id] = existing.customName
                }
                
                newSpaceList.append(finalSpace)
            }
            
            // Only update if changed to avoid loop
            if self.spaceNameDict != newSpaceList {
                self.spaceNameDict = newSpaceList
                saveData()
            }
            
            self.currentSpaceUUID = cgsState.currentUUID
            self.currentDisplayID = cgsState.displayID
            self.currentRawSpaceUUID = cgsState.currentUUID
            self.currentIsDesktop = (cgsState.currentUUID != "FULLSCREEN")
            self.currentNcCount = 0
            
            if isBugReportActive {
                bugReportLog.append(LogEntry(timestamp: Date(), spaceUUID: cgsState.currentUUID, isDesktop: currentIsDesktop, ncCount: 0, action: "CGS Update (\(source))"))
            }
            return
        }
        
        // Legacy Logic
        self.currentIsDesktop = isDesktop
        self.currentNcCount = ncCount
        self.currentRawSpaceUUID = rawUUID
        self.currentDisplayID = displayID
        
        var logicalUUID = rawUUID
        switch detectionMethod {
        case .automatic: if !isDesktop { logicalUUID = "FULLSCREEN" }
        case .metric: if ncCount <= SpaceHelper.fullscreenThreshold { logicalUUID = "FULLSCREEN" }
        case .manual: logicalUUID = rawUUID
        }
        
        if isBugReportActive {
            let action = (currentSpaceUUID != logicalUUID) ? "Space Switched (\(source))" : "State Check (\(source))"
            bugReportLog.append(LogEntry(timestamp: Date(), spaceUUID: rawUUID, isDesktop: isDesktop, ncCount: ncCount, action: "\(action) [\(detectionMethod.rawValue)]"))
        }
        
        if currentSpaceUUID != logicalUUID { currentSpaceUUID = logicalUUID }

        if let index = spaceNameDict.firstIndex(where: { $0.id == logicalUUID }) {
            if spaceNameDict[index].displayID != displayID {
                spaceNameDict[index].displayID = displayID
                saveData()
            }
        }
        
        if detectionMethod != .manual && detectionMethod != .automatic && logicalUUID != "FULLSCREEN" {
            if !spaceNameDict.contains(where: { $0.id == logicalUUID }) {
                let existingSpacesOnDisplay = spaceNameDict.filter { $0.displayID == displayID }
                let newNum = (existingSpacesOnDisplay.map { $0.num }.max() ?? 0) + 1
                spaceNameDict.append(DesktopSpace(id: logicalUUID, customName: "", num: newNum, displayID: displayID))
                saveData()
            }
        }
    }
    
    func addManualSpace(_ uuid: String) {
        guard uuid != "FULLSCREEN", !spaceNameDict.contains(where: { $0.id == uuid }) else { return }
        let existingSpacesOnDisplay = spaceNameDict.filter { $0.displayID == currentDisplayID }
        let newNum = (existingSpacesOnDisplay.map { $0.num }.max() ?? 0) + 1
        spaceNameDict.append(DesktopSpace(id: uuid, customName: "", num: newNum, displayID: currentDisplayID))
        saveData()
        refreshSpaceState()
    }
    
    func startBugReportLogging() {
        bugReportLog = [LogEntry(timestamp: Date(), spaceUUID: currentRawSpaceUUID, isDesktop: currentIsDesktop, ncCount: currentNcCount, action: "--- START ---")]
        isBugReportActive = true
    }

    func stopBugReportLogging() {
        bugReportLog.append(LogEntry(timestamp: Date(), spaceUUID: currentRawSpaceUUID, isDesktop: currentIsDesktop, ncCount: currentNcCount, action: "--- STOP ---"))
        isBugReportActive = false
    }
    
    func prepareForTermination() {
        DistributedNotificationCenter.default().postNotificationName(SpaceAPI.apiToggleNotification, object: nil, userInfo: ["isEnabled": false], deliverImmediately: true)
    }
    
    private func loadSavedData() {
        // 1. Load active list
        if let data = UserDefaults.standard.data(forKey: SpaceManager.spacesKey),
           let spaces = try? JSONDecoder().decode([DesktopSpace].self, from: data) {
            spaceNameDict = spaces
        }
        
        // 2. Load name cache
        if let data = UserDefaults.standard.data(forKey: SpaceManager.nameCacheKey),
           let cache = try? JSONDecoder().decode([String: String].self, from: data) {
            nameCache = cache
        }
        
        // 3. Migration: If cache is empty but we have legacy names, populate cache
        if nameCache.isEmpty && !spaceNameDict.isEmpty {
            for space in spaceNameDict where !space.customName.isEmpty {
                nameCache[space.id] = space.customName
            }
            saveData()
        }
    }
    
    public func saveSpaces() {
        saveData()
    }
    
    private func saveData() {
        if let data = try? JSONEncoder().encode(spaceNameDict) {
            UserDefaults.standard.set(data, forKey: SpaceManager.spacesKey)
        }
        if let data = try? JSONEncoder().encode(nameCache) {
            UserDefaults.standard.set(data, forKey: SpaceManager.nameCacheKey)
        }
        UserDefaults.standard.synchronize()
    }

    func getSpaceNum(_ spaceUUID: String) -> Int {
        if spaceUUID == "FULLSCREEN" { return 0 }
        if let space = spaceNameDict.first(where: { $0.id == spaceUUID }) { return space.num }
        return detectionMethod == .manual ? 0 : -1
    }
    
    func getSpaceName(_ spaceUUID: String) -> String {
        if detectionMethod == .manual {
             if spaceUUID != "FULLSCREEN" && !spaceNameDict.contains(where: { $0.id == spaceUUID }) { return "Fullscreen" }
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
            UserDefaults.standard.removeObject(forKey: SpaceManager.nameCacheKey)
            self.spaceNameDict.removeAll()
            self.nameCache.removeAll()
            self.saveData()
            self.refreshSpaceState()
        }
    }
    
    func renameSpace(_ spaceUUID: String, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Update Live List
        if let index = spaceNameDict.firstIndex(where: { $0.id == spaceUUID }) {
            spaceNameDict[index].customName = trimmedName
        }
        
        // Update Persistent Cache
        if trimmedName.isEmpty {
            nameCache.removeValue(forKey: spaceUUID)
        } else {
            nameCache[spaceUUID] = trimmedName
        }
        
        saveData()
    }
}
