import Foundation
import AppKit

class DesktopSpaceManager: ObservableObject {
    @Published private(set) var currentSpaceId: Int = 1
    @Published var desktopSpaces: [DesktopSpace] = []
    
    private let userDefaults = UserDefaults.standard
    private let spacesKey = "com.desktoprenamer.spaces"  // Unique key for storing space names
    private var isUpdating = false
    private let maxSpaceNumber = 99  // Reasonable limit for number of spaces
    
    init() {
        loadSavedSpaces()
        
        // Start monitoring spaces
        SpaceHelper.startMonitoring { [weak self] newSpaceId in
            self?.handleSpaceChange(newSpaceId)
        }
    }
    
    deinit {
        SpaceHelper.stopMonitoring()
    }
    
    private func loadSavedSpaces() {
        if let data = userDefaults.data(forKey: spacesKey),
           let spaces = try? JSONDecoder().decode([DesktopSpace].self, from: data) {
            desktopSpaces = spaces
        }
    }
    
    private func saveSpaces() {
        if let data = try? JSONEncoder().encode(desktopSpaces) {
            userDefaults.set(data, forKey: spacesKey)
            userDefaults.synchronize()  // Ensure changes are saved immediately
        }
    }
    
    func resetAllNames() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Clear all custom names
            self.desktopSpaces.removeAll()
            self.saveSpaces()
            
            // Force refresh current space
            if let currentSpace = SpaceHelper.getCurrentSpaceNumber() {
                self.handleSpaceChange(currentSpace)
            }
            
            // Notify observers
            self.objectWillChange.send()
        }
    }
    
    private func handleSpaceChange(_ newSpaceId: Int) {
        // Always handle on main thread
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.handleSpaceChange(newSpaceId)
            }
            return
        }
        
        guard !isUpdating else { return }
        isUpdating = true
        
        if isValidSpaceNumber(newSpaceId) {
            // Only update if the space actually changed
            if currentSpaceId != newSpaceId {
                currentSpaceId = newSpaceId
                ensureSpaceExists(newSpaceId)
                objectWillChange.send()
            }
        } else {
            print("Invalid space number received: \(newSpaceId)")
        }
        
        isUpdating = false
    }
    
    private func isValidSpaceNumber(_ number: Int) -> Bool {
        return number > 0 && number <= maxSpaceNumber
    }
    
    private func ensureSpaceExists(_ spaceId: Int) {
        if !desktopSpaces.contains(where: { $0.id == spaceId }) {
            desktopSpaces.append(DesktopSpace(id: spaceId, customName: ""))
            saveSpaces()
        }
    }
    
    func renameSpace(_ spaceId: Int, to newName: String) {
        guard isValidSpaceNumber(spaceId) else { return }
        
        if let index = desktopSpaces.firstIndex(where: { $0.id == spaceId }) {
            desktopSpaces[index].customName = newName
            saveSpaces()
        } else {
            let newSpace = DesktopSpace(id: spaceId, customName: newName)
            desktopSpaces.append(newSpace)
            saveSpaces()
        }
        
        objectWillChange.send()
    }
    
    func getSpaceName(_ spaceId: Int) -> String {
        guard isValidSpaceNumber(spaceId) else { return "Invalid Space" }
        return desktopSpaces.first(where: { $0.id == spaceId })?.displayName ?? "Desktop \(spaceId)"
    }
} 