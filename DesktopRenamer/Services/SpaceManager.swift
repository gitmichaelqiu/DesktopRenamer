import Foundation
import AppKit

class SpaceManager: ObservableObject {
    @Published private(set) var currentSpaceUUID: String = ""
    @Published var spaceNameDict: [DesktopSpace] = []
    
    private let userDefaults = UserDefaults.standard
    private let spacesKey = "com.gitmichaelqiu.desktoprenamer.spaces"
    
    private var currentTotalSpace = 0
    
    init() {
        loadSavedSpaces()
        
        // Start monitoring
        SpaceHelper.startMonitoring { [weak self] newSpaceUUID in
            self?.handleSpaceChange(newSpaceUUID)
        }
    }
    
    deinit {
        SpaceHelper.stopMonitoring()
    }
    
    private func handleSpaceChange(_ newSpaceUUID: String) {
        // Handle on main thread
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.handleSpaceChange(newSpaceUUID)
            }
            return
        }
        
        currentSpaceUUID = newSpaceUUID
        
        // Check if the space was handled before
        if !spaceNameDict.contains(where: { $0.id == currentSpaceUUID }) && currentSpaceUUID != "FULLSCREEN" {
            currentTotalSpace += 1
            spaceNameDict.append(DesktopSpace(id: currentSpaceUUID, customName: "", num: currentTotalSpace))
            saveSpaces()
        }
        
        objectWillChange.send()
    }
    
    private func loadSavedSpaces() {
        if let data = userDefaults.data(forKey: spacesKey),
           let spaces = try? JSONDecoder().decode([DesktopSpace].self, from: data) {
            spaceNameDict = spaces
            currentTotalSpace = spaceNameDict.count
        }
    }
    
    private func saveSpaces() {
        if let data = try? JSONEncoder().encode(spaceNameDict) {
            userDefaults.set(data, forKey: spacesKey)
            userDefaults.synchronize()
        }
    }
    
    private func isValidUUID(_ spaceUUID: String) -> Bool {
        if spaceUUID == "FULLSCREEN" {
            return true
        }
        
        // Check if the space is removed
        if spaceNameDict.contains(where: { $0.id == spaceUUID }) { // Still exist
            return true
        }
        
        // Remove space
        spaceNameDict.removeAll(where: {$0.id == spaceUUID})
        return false
    }
    
    func getSpaceNum(_ spaceUUID: String) -> Int {
        guard isValidUUID(spaceUUID) else { return -1 }
        if spaceUUID == "FULLSCREEN" {
            return 0
        }
        return spaceNameDict.first(where: { $0.id == spaceUUID })?.num ?? -1
    }
    
    func getSpaceName(_ spaceUUID: String) -> String {
        guard isValidUUID(spaceUUID) else { return "" }
        
        if spaceUUID == "FULLSCREEN" {
            return "Fullscreen"
        }
        
        var ret = spaceNameDict.first(where: {$0.id == spaceUUID})?.customName
        if ret == "" {
            ret = String(format: NSLocalizedString("space.default_name", comment: ""), getSpaceNum(spaceUUID))
        }
        
        return ret ?? ""
    }
    
    func resetAllNames() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Clear userDefaults
            userDefaults.removeObject(forKey: spacesKey)
            
            // Clear all custom names
            currentTotalSpace = 0
            self.spaceNameDict.removeAll()
            self.saveSpaces()
            
            // Force refresh current space
            currentSpaceUUID = SpaceHelper.getSpaceUUID()
            self.handleSpaceChange(currentSpaceUUID)
            
            // Notify observers
            self.objectWillChange.send()
        }
    }
    
    func renameSpace(_ spaceUUID: String, to newName: String) {
        guard isValidUUID(spaceUUID) else { return }
        
        if let index = spaceNameDict.firstIndex(where: { $0.id == spaceUUID }) {
            spaceNameDict[index].customName = newName
            saveSpaces()
        } else {
            print("Debug: Services/SM renameSpace failed")
        }
        
        objectWillChange.send()
    }
}
