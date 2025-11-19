import Foundation
import AppKit
import SwiftUI

class SpaceManager: ObservableObject {
    @Published private(set) var currentSpaceUUID: String = ""
    @Published var spaceNameDict: [DesktopSpace] = []
    
    // We observe this property to toggle the API automatically
    @AppStorage("isAPIEnabled") public var isAPIEnabled: Bool = true {
        didSet {
            // Toggle the internal API instance when setting changes
            spaceAPI?.toggleAPIState(isEnabled: isAPIEnabled)
        }
    }
    
    public var currentTotalSpace = 0
    private let userDefaults = UserDefaults.standard
    private let spacesKey = "com.michaelqiu.desktoprenamer.spaces"
    
    // Keep reference to API
    public var spaceAPI: SpaceAPI?
    
    init() {
        loadSavedSpaces()
        
        // Initialize API
        self.spaceAPI = SpaceAPI(spaceManager: self)
        
        // Set initial state based on saved setting
        if isAPIEnabled {
            self.spaceAPI?.toggleAPIState(isEnabled: true)
        }
        
        // Start monitoring
        SpaceHelper.startMonitoring { [weak self] newSpaceUUID in
            self?.handleSpaceChange(newSpaceUUID)
        }
    }
    
    // Called by AppDelegate when quitting
    func prepareForTermination() {
        print("SpaceManager: Shutting down...")
        // Explicitly send "False" notification
        spaceAPI?.toggleAPIState(isEnabled: false)
    }
    
    deinit {
        SpaceHelper.stopMonitoring()
    }
    
    // ... (Keep rest of handleSpaceChange, loadSavedSpaces, saveSpaces, etc. exactly as before) ...
    
    private func handleSpaceChange(_ newSpaceUUID: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.handleSpaceChange(newSpaceUUID) }
            return
        }
        currentSpaceUUID = newSpaceUUID
        if !spaceNameDict.contains(where: { $0.id == currentSpaceUUID }) && currentSpaceUUID != "FULLSCREEN" {
            currentTotalSpace += 1
            spaceNameDict.append(DesktopSpace(id: currentSpaceUUID, customName: "", num: currentTotalSpace))
            saveSpaces()
        }
    }
    
    private func loadSavedSpaces() {
        if let data = userDefaults.data(forKey: spacesKey),
           let spaces = try? JSONDecoder().decode([DesktopSpace].self, from: data) {
            spaceNameDict = spaces
            currentTotalSpace = spaceNameDict.count
        }
    }
    
    public func saveSpaces() {
        if let data = try? JSONEncoder().encode(spaceNameDict) {
            userDefaults.set(data, forKey: spacesKey)
            userDefaults.synchronize()
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
            self.userDefaults.removeObject(forKey: self.spacesKey)
            self.currentTotalSpace = 0
            self.spaceNameDict.removeAll()
            self.saveSpaces()
            SpaceHelper.getSpaceUUID { spaceUUID in
                self.currentSpaceUUID = spaceUUID
                self.handleSpaceChange(spaceUUID)
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
