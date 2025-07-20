import Foundation
import AppKit

class DesktopSpaceManager: ObservableObject {
    @Published private(set) var currentSpaceId: Int = 1
    @Published var desktopSpaces: [DesktopSpace] = []
    
    private let userDefaults = UserDefaults.standard
    private let spacesKey = "DesktopSpaces"
    private var isUpdating = false
    
    init() {
        loadSavedSpaces()
        startSpaceMonitoring()
        
        // Initial update
        DispatchQueue.main.async {
            self.updateCurrentSpace()
        }
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
        }
    }
    
    private func startSpaceMonitoring() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func activeSpaceDidChange() {
        DispatchQueue.main.async {
            self.updateCurrentSpace()
        }
    }
    
    func refreshCurrentSpace() {
        DispatchQueue.main.async {
            self.updateCurrentSpace()
        }
    }
    
    private func updateCurrentSpace() {
        guard !isUpdating else { return }
        isUpdating = true
        
        // Get the current space number using CGWindowListCopyWindowInfo
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        var found = false
        for window in windowList {
            if let owner = window[kCGWindowOwnerName as String] as? String,
               owner == "Dock",
               let name = window[kCGWindowName as String] as? String,
               name.contains("Desktop") {
                if let spaceNumber = name.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .joined()
                    .first.map({ Int(String($0)) }) ?? nil {
                    if currentSpaceId != spaceNumber {
                        currentSpaceId = spaceNumber
                        ensureSpaceExists(spaceNumber)
                    }
                    found = true
                    break
                }
            }
        }
        
        // If we couldn't find the space number, keep the current one
        if !found {
            print("Could not detect space number, keeping current: \(currentSpaceId)")
        }
        
        isUpdating = false
    }
    
    private func ensureSpaceExists(_ spaceId: Int) {
        if !desktopSpaces.contains(where: { $0.id == spaceId }) {
            desktopSpaces.append(DesktopSpace(id: spaceId, customName: ""))
            saveSpaces()
        }
    }
    
    func renameSpace(_ spaceId: Int, to newName: String) {
        if let index = desktopSpaces.firstIndex(where: { $0.id == spaceId }) {
            desktopSpaces[index].customName = newName
            saveSpaces()
        } else {
            let newSpace = DesktopSpace(id: spaceId, customName: newName)
            desktopSpaces.append(newSpace)
            saveSpaces()
        }
        
        // Force a UI update
        objectWillChange.send()
    }
    
    func getSpaceName(_ spaceId: Int) -> String {
        return desktopSpaces.first(where: { $0.id == spaceId })?.displayName ?? "Desktop \(spaceId)"
    }
} 