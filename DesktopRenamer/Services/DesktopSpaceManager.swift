import Foundation
import AppKit

class DesktopSpaceManager: ObservableObject {
    @Published private(set) var currentSpaceId: Int = 1
    @Published var desktopSpaces: [DesktopSpace] = []
    
    private let userDefaults = UserDefaults.standard
    private let spacesKey = "DesktopSpaces"
    
    init() {
        loadSavedSpaces()
        startSpaceMonitoring()
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
        updateCurrentSpace()
    }
    
    @objc private func activeSpaceDidChange() {
        updateCurrentSpace()
    }
    
    private func updateCurrentSpace() {
        // Get the current space number using CGWindowListCopyWindowInfo
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        for window in windowList {
            if let owner = window[kCGWindowOwnerName as String] as? String,
               owner == "Dock",
               let name = window[kCGWindowName as String] as? String,
               name.contains("Desktop") {
                if let spaceNumber = name.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .joined()
                    .first.map({ Int(String($0)) }) ?? nil {
                    currentSpaceId = spaceNumber
                    ensureSpaceExists(spaceNumber)
                    break
                }
            }
        }
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
    }
    
    func getSpaceName(_ spaceId: Int) -> String {
        return desktopSpaces.first(where: { $0.id == spaceId })?.displayName ?? "Desktop \(spaceId)"
    }
} 