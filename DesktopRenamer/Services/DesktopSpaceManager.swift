import Foundation
import AppKit

class DesktopSpaceManager: ObservableObject {
    @Published private(set) var currentSpaceId: Int = 1
    @Published var desktopSpaces: [DesktopSpace] = []
    
    private let userDefaults = UserDefaults.standard
    private let spacesKey = "DesktopSpaces"
    private var isUpdating = false
    private let maxSpaceNumber = 99  // Reasonable limit for number of spaces
    
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
        // Monitor space changes
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        
        // Also monitor window changes as a backup
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSNotification.Name("com.apple.spaces.switchedSpaces"),
            object: nil
        )
        
        // Monitor window focus changes
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
    
    @objc private func activeSpaceDidChange() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.updateCurrentSpace()
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
        
        var detectedSpaceId: Int?
        
        // Get all visible windows
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        // Sort windows by layer to prioritize desktop windows
        let sortedWindows = windowList.sorted { win1, win2 in
            let layer1 = win1[kCGWindowLayer as String] as? Int32 ?? 0
            let layer2 = win2[kCGWindowLayer as String] as? Int32 ?? 0
            return layer1 < layer2
        }
        
        // Look for Mission Control/Dock windows with space information
        for window in sortedWindows {
            if let owner = window[kCGWindowOwnerName as String] as? String,
               owner == "Dock" {
                
                // Check window name
                if let name = window[kCGWindowName as String] as? String {
                    // First try: Direct desktop number in window name
                    if let spaceId = extractSpaceNumber(from: name),
                       isValidSpaceNumber(spaceId) {
                        detectedSpaceId = spaceId
                        break
                    }
                    
                    // Second try: Look for specific desktop patterns
                    if name.contains("Desktop") || name.contains("desktop") || name.contains("space") {
                        if let spaceId = extractSpaceNumber(from: name),
                           isValidSpaceNumber(spaceId) {
                            detectedSpaceId = spaceId
                            break
                        }
                    }
                }
                
                // Check window bounds for additional context
                if let bounds = window[kCGWindowBounds as String] as? [String: Any],
                   let y = bounds["Y"] as? Double,
                   y < 50 {  // Desktop windows are typically at the top
                    if let name = window[kCGWindowName as String] as? String,
                       let spaceId = extractSpaceNumber(from: name),
                       isValidSpaceNumber(spaceId) {
                        detectedSpaceId = spaceId
                        break
                    }
                }
            }
        }
        
        // Update the space ID if we found a valid one
        if let spaceId = detectedSpaceId {
            updateSpaceId(spaceId)
        } else {
            print("Could not detect valid space number, keeping current: \(currentSpaceId)")
        }
        
        isUpdating = false
    }
    
    private func extractSpaceNumber(from name: String) -> Int? {
        // Try different patterns
        let patterns = [
            "Desktop (\\d+)",           // "Desktop 1"
            "desktop_(\\d+)",           // "desktop_1"
            "space_(\\d+)",             // "space_1"
            "^\\s*(\\d+)\\s*$",        // Just the number with optional whitespace
            "\\D(\\d{1,2})\\D"         // 1-2 digits surrounded by non-digits
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) {
                let numberRange = Range(match.range(at: 1), in: name)
                if let range = numberRange,
                   let number = Int(name[range]),
                   isValidSpaceNumber(number) {
                    return number
                }
            }
        }
        
        return nil
    }
    
    private func isValidSpaceNumber(_ number: Int) -> Bool {
        return number > 0 && number <= maxSpaceNumber
    }
    
    private func updateSpaceId(_ newId: Int) {
        guard isValidSpaceNumber(newId) else { return }
        
        if currentSpaceId != newId {
            currentSpaceId = newId
            ensureSpaceExists(newId)
            objectWillChange.send()
        }
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