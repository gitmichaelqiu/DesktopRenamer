import Foundation
import AppKit
import SwiftUI
import WidgetKit

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
    // App Group ID for Widget Sharing
    static let appGroupId = "group.com.michaelqiu.DesktopRenamer"
    
    static private let spacesKey = "com.michaelqiu.desktoprenamer.spaces"
    static private let nameCacheKey = "com.michaelqiu.desktoprenamer.namecache"
    static private let indexCacheKey = "com.michaelqiu.desktoprenamer.indexcache"
    static private let isAPIEnabledKey = "com.michaelqiu.desktoprenamer.isapienabled"
    static private let detectionMethodKey = "com.michaelqiu.desktoprenamer.detectionMethod"
    static private let isManualSpacesEnabledKey = "com.michaelqiu.desktoprenamer.ismanualspacesenabled"
    
    @Published private(set) var currentSpaceUUID: String = ""
    @Published private(set) var currentRawSpaceUUID: String = ""
    @Published private(set) var currentDisplayID: String = "Main"
    
    @Published var spaceNameDict: [DesktopSpace] = []
    
    // MARK: - Computed Properties
    
    var currentDisplaySpaces: [DesktopSpace] {
        spaceNameDict
            .filter { $0.displayID == currentDisplayID }
            .sorted { $0.num < $1.num }
    }
    
    private var nameCache: [String: String] = [:]
    private var indexCache: [String: String] = [:]
    
    @Published var currentNcCount: Int = 0
    @Published var currentIsDesktop: Bool = false
    
    @Published var isBugReportActive: Bool = false
    @Published private(set) var bugReportLog: [LogEntry] = []
    
    // Widget Debouncer
    private var widgetUpdateWorkItem: DispatchWorkItem?
    
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
        
        var shouldUpdateWidget = false
        
        if detectionMethod == .automatic {
            guard let cgsState = SpaceHelper.getSystemState() else { return }
            
            // PRE-CHECK: Identify which names are already securely claimed by existing UUIDs.
            var claimedNames: Set<String> = []
            let activeUUIDs = Set(cgsState.spaces.map { $0.id })
            
            for (uuid, name) in nameCache {
                if activeUUIDs.contains(uuid) && !name.isEmpty {
                    claimedNames.insert(name)
                }
            }
            
            var newSpaceList: [DesktopSpace] = []
            
            // 1. Build List and Apply Cache (Skip cache for fullscreen)
            for sysSpace in cgsState.spaces {
                var finalSpace = sysSpace
                
                if finalSpace.isFullscreen {
                     // For fullscreen spaces, we do NOT load custom names.
                     // The name will be auto-generated in the numbering pass below.
                     finalSpace.customName = "" // Placeholder
                } else {
                    if let cachedName = nameCache[sysSpace.id], !cachedName.isEmpty {
                        finalSpace.customName = cachedName
                    } else {
                        let indexKey = "\(finalSpace.displayID)|\(finalSpace.num)"
                        
                        if let fallbackName = indexCache[indexKey], !fallbackName.isEmpty {
                            if !claimedNames.contains(fallbackName) {
                                finalSpace.customName = fallbackName
                                nameCache[sysSpace.id] = fallbackName
                            }
                        } else if let existing = spaceNameDict.first(where: { $0.id == sysSpace.id }), !existing.customName.isEmpty {
                            finalSpace.customName = existing.customName
                            nameCache[sysSpace.id] = existing.customName
                            indexCache[indexKey] = existing.customName
                        }
                    }
                }
                newSpaceList.append(finalSpace)
            }
            
            // 2. Fullscreen Naming Pass (Group by App Name and Number)
            // Group indices of fullscreen spaces by their appName
            var appGroups: [String: [Int]] = [:]
            
            for (index, space) in newSpaceList.enumerated() {
                if space.isFullscreen {
                    let name = space.appName ?? "Fullscreen"
                    appGroups[name, default: []].append(index)
                }
            }
            
            // Apply names: "Xcode", or "Xcode 1", "Xcode 2"
            for (appName, indices) in appGroups {
                let sortedIndices = indices.sorted { newSpaceList[$0].num < newSpaceList[$1].num }
                
                if sortedIndices.count == 1 {
                    newSpaceList[sortedIndices[0]].customName = appName
                } else {
                    for (i, index) in sortedIndices.enumerated() {
                        newSpaceList[index].customName = "\(appName) \(i + 1)"
                    }
                }
            }
            
            if self.spaceNameDict != newSpaceList {
                self.spaceNameDict = newSpaceList
                
                // Update index cache with currently detected spaces.
                // We do NOT clear the cache here to preserve names for spaces/displays that might 
                // be temporarily undetected (active display only, sleeping connection, etc).
                for space in self.spaceNameDict where !space.customName.isEmpty && !space.isFullscreen {
                    let key = "\(space.displayID)|\(space.num)"
                    self.indexCache[key] = space.customName
                }
                
                saveData()
                shouldUpdateWidget = true
            }
            
            if self.currentSpaceUUID != cgsState.currentUUID {
                self.currentSpaceUUID = cgsState.currentUUID
                shouldUpdateWidget = true
            }
            if self.currentDisplayID != cgsState.displayID {
                self.currentDisplayID = cgsState.displayID
            }
            if self.currentRawSpaceUUID != cgsState.currentUUID {
                self.currentRawSpaceUUID = cgsState.currentUUID
            }
            
            // Update desktop check based on fullscreen status of the matched space
            let isCurrentDesktop = !(self.spaceNameDict.first(where: { $0.id == self.currentSpaceUUID })?.isFullscreen ?? false)
            if self.currentIsDesktop != isCurrentDesktop {
                self.currentIsDesktop = isCurrentDesktop
                shouldUpdateWidget = true
            }
            
            if isBugReportActive {
                bugReportLog.append(LogEntry(timestamp: Date(), spaceUUID: cgsState.currentUUID, isDesktop: currentIsDesktop, ncCount: 0, action: "CGS Update (\(source))"))
            }
            
            if shouldUpdateWidget { scheduleWidgetUpdate() }
            return
        }
        
        // Legacy Detection logic
        if self.currentIsDesktop != isDesktop {
            self.currentIsDesktop = isDesktop
            shouldUpdateWidget = true
        }
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
        
        if currentSpaceUUID != logicalUUID {
            currentSpaceUUID = logicalUUID
            shouldUpdateWidget = true
        }

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
                shouldUpdateWidget = true
            }
        }
        
        if shouldUpdateWidget { scheduleWidgetUpdate() }
    }
    
    // MARK: - Widget Integration (Debounced)
    private func scheduleWidgetUpdate() {
        widgetUpdateWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.performWidgetUpdate()
        }
        
        widgetUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    struct WidgetSpace: Codable {
        let id: String
        let name: String
        let num: Int
        let displayID: String
    }

    private func performWidgetUpdate() {
        guard let defaults = UserDefaults(suiteName: SpaceManager.appGroupId) else { return }
        
        let name = getSpaceName(currentSpaceUUID)
        let num = getSpaceNum(currentSpaceUUID)
        // Check if current space is desktop
        let isDesktop = !(spaceNameDict.first(where: { $0.id == currentSpaceUUID })?.isFullscreen ?? false)
        
        // Prepare structured data for Widget
        let sortedSpaces = spaceNameDict.sorted {
            if $0.displayID != $1.displayID {
                return $0.displayID < $1.displayID
            }
            return $0.num < $1.num
        }
        
        let widgetSpaces = sortedSpaces.map { space in
            WidgetSpace(
                id: space.id,
                name: space.customName.isEmpty ? String(format: NSLocalizedString("Space.DefaultName", comment: ""), space.num) : space.customName,
                num: space.num,
                displayID: space.displayID
            )
        }
        
        if let data = try? JSONEncoder().encode(widgetSpaces) {
            defaults.set(data, forKey: "widget_spacesData")
        }
        
        // Legacy fields for backward compatibility or simple widgets
        let allSpaceNames = sortedSpaces.map { $0.customName.isEmpty ? "\($0.num)" : $0.customName }
        defaults.set(allSpaceNames, forKey: "widget_allSpaces")
        
        defaults.set(name, forKey: "widget_spaceName")
        defaults.set(num, forKey: "widget_spaceNum")
        defaults.set(isDesktop, forKey: "widget_isDesktop")
        defaults.set(currentSpaceUUID, forKey: "widget_currentSpaceUUID")
        
        defaults.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
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
        if let data = UserDefaults.standard.data(forKey: SpaceManager.spacesKey),
           let spaces = try? JSONDecoder().decode([DesktopSpace].self, from: data) {
            spaceNameDict = spaces
        }
        if let data = UserDefaults.standard.data(forKey: SpaceManager.nameCacheKey),
           let cache = try? JSONDecoder().decode([String: String].self, from: data) {
            nameCache = cache
        }
        if let data = UserDefaults.standard.data(forKey: SpaceManager.indexCacheKey),
           let cache = try? JSONDecoder().decode([String: String].self, from: data) {
            indexCache = cache
        }
        if (nameCache.isEmpty || indexCache.isEmpty) && !spaceNameDict.isEmpty {
            for space in spaceNameDict where !space.customName.isEmpty && !space.isFullscreen {
                nameCache[space.id] = space.customName
                let indexKey = "\(space.displayID)|\(space.num)"
                indexCache[indexKey] = space.customName
            }
            saveData()
        }
    }
    
    public func saveSpaces() {
        saveData()
    }
    
    private func saveData() {
        // We only save the spaces. Naming logic for fullscreen is re-run on load/refresh.
        if let data = try? JSONEncoder().encode(spaceNameDict) {
            UserDefaults.standard.set(data, forKey: SpaceManager.spacesKey)
        }
        if let data = try? JSONEncoder().encode(nameCache) {
            UserDefaults.standard.set(data, forKey: SpaceManager.nameCacheKey)
        }
        if let data = try? JSONEncoder().encode(indexCache) {
            UserDefaults.standard.set(data, forKey: SpaceManager.indexCacheKey)
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
            UserDefaults.standard.removeObject(forKey: SpaceManager.indexCacheKey)
            self.spaceNameDict.removeAll()
            self.nameCache.removeAll()
            self.indexCache.removeAll()
            self.saveData()
            self.refreshSpaceState()
            self.scheduleWidgetUpdate()
        }
    }
    
    func renameSpace(_ spaceUUID: String, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = spaceNameDict.firstIndex(where: { $0.id == spaceUUID }) {
            // Prevent renaming fullscreen spaces manually if needed, or just let it be overwritten on next refresh.
            // But UI filters them out, so this is mostly safe.
            spaceNameDict[index].customName = trimmedName
            let space = spaceNameDict[index]
            let indexKey = "\(space.displayID)|\(space.num)"
            
            if !space.isFullscreen {
                if trimmedName.isEmpty {
                    nameCache.removeValue(forKey: spaceUUID)
                    indexCache.removeValue(forKey: indexKey)
                } else {
                    nameCache[spaceUUID] = trimmedName
                    indexCache[indexKey] = trimmedName
                }
            }
            saveData()
            scheduleWidgetUpdate()
        }
    }
    
    // MARK: - Switching
    
    func switchToSpace(_ space: DesktopSpace) {
        SpaceHelper.switchToSpace(space.id)
    }
    
    func switchToPreviousSpace(onDisplayID displayID: String? = nil) {
        var targetDisplayID = displayID
        var currentSpaceID = currentSpaceUUID
        
        // If a specific display is requested, find its current space
        if let requestedDisplayID = displayID {
            if let space = SpaceHelper.getCurrentSpaceID(for: requestedDisplayID) {
                currentSpaceID = space
                targetDisplayID = requestedDisplayID
            } else {
                return // Invalid display or state
            }
        }
        
        // Find current space info in our dictionary
        guard let current = spaceNameDict.first(where: { $0.id == currentSpaceID }) else { return }
        
        // Double check display ID match if one was not constrained
        if targetDisplayID == nil { targetDisplayID = current.displayID }
        
        // Use spaces from the TARGET display
        let displaySpaces = spaceNameDict
            .filter { $0.displayID == targetDisplayID }
            .sorted { $0.num < $1.num }
        
        // Find index and move left
        guard let currentIndex = displaySpaces.firstIndex(of: current), currentIndex > 0 else { return }
        
        let target = displaySpaces[currentIndex - 1]
        switchToSpace(target)
    }

    func switchToNextSpace(onDisplayID displayID: String? = nil) {
        var targetDisplayID = displayID
        var currentSpaceID = currentSpaceUUID
        
        // If a specific display is requested, find its current space
        if let requestedDisplayID = displayID {
            if let space = SpaceHelper.getCurrentSpaceID(for: requestedDisplayID) {
                currentSpaceID = space
                targetDisplayID = requestedDisplayID
            } else {
                return // Invalid display or state
            }
        }
        
        // Find current space info in our dictionary
        guard let current = spaceNameDict.first(where: { $0.id == currentSpaceID }) else { return }
        
        // Double check display ID match
        if targetDisplayID == nil { targetDisplayID = current.displayID }
        
        // Use spaces from the TARGET display
        let displaySpaces = spaceNameDict
            .filter { $0.displayID == targetDisplayID }
            .sorted { $0.num < $1.num }
        
        // Find index and move right
        guard let currentIndex = displaySpaces.firstIndex(of: current), currentIndex < displaySpaces.count - 1 else { return }
        
        let target = displaySpaces[currentIndex + 1]
        switchToSpace(target)
    }
    func isFirstSpace(onDisplayID displayID: String? = nil) -> Bool {
        var targetDisplayID = displayID
        var currentSpaceID = currentSpaceUUID
        
        if let requestedDisplayID = displayID {
            if let space = SpaceHelper.getCurrentSpaceID(for: requestedDisplayID) {
                currentSpaceID = space
                targetDisplayID = requestedDisplayID
            } else { return false }
        }
        
        guard let current = spaceNameDict.first(where: { $0.id == currentSpaceID }) else { return false }
        if targetDisplayID == nil { targetDisplayID = current.displayID }
        
        // Check manual filtering logic in displaySpaces
        let displaySpaces = spaceNameDict
            .filter { $0.displayID == targetDisplayID }
            .sorted { $0.num < $1.num }
            
        guard let currentIndex = displaySpaces.firstIndex(of: current) else { return false }
        return currentIndex == 0
    }
    
    func isLastSpace(onDisplayID displayID: String? = nil) -> Bool {
        var targetDisplayID = displayID
        var currentSpaceID = currentSpaceUUID
        
        if let requestedDisplayID = displayID {
             if let space = SpaceHelper.getCurrentSpaceID(for: requestedDisplayID) {
                 currentSpaceID = space
                 targetDisplayID = requestedDisplayID
             } else { return false }
         }
         
         guard let current = spaceNameDict.first(where: { $0.id == currentSpaceID }) else { return false }
         if targetDisplayID == nil { targetDisplayID = current.displayID }
         
         let displaySpaces = spaceNameDict
             .filter { $0.displayID == targetDisplayID }
             .sorted { $0.num < $1.num }
             
         guard let currentIndex = displaySpaces.firstIndex(of: current) else { return false }
         return currentIndex == displaySpaces.count - 1
    }
}
