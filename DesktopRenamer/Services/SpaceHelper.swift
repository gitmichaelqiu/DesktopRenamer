import Foundation
import AppKit

class SpaceHelper {
    private static var lastKnownSpace: Int = 1
    private static var onSpaceChange: ((Int) -> Void)?
    private static var wallpaperCache: [String: Int] = [:]
    private static var isFirstRun = true
    private static var isProcessing = false
    
    static func startMonitoring(onChange: @escaping (Int) -> Void) {
        onSpaceChange = onChange
        
        // Monitor space changes using distributed notifications
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.spaces.switchedSpaces"),
            object: nil,
            queue: .main
        ) { _ in
            detectSpaceChange()
        }
        
        // Also monitor window layout changes
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            detectSpaceChange()
        }
        
        // Initial detection
        detectSpaceChange()
    }
    
    static func stopMonitoring() {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        onSpaceChange = nil
    }
    
    private static func detectSpaceChange() {
        guard !isProcessing else { return }
        isProcessing = true
        
        if let spaceNumber = getCurrentSpaceNumber() {
            if spaceNumber != lastKnownSpace || isFirstRun {
                lastKnownSpace = spaceNumber
                isFirstRun = false
                onSpaceChange?(spaceNumber)
            }
        }
        
        isProcessing = false
    }
    
    static func getCurrentSpaceNumber() -> Int? {
        // Get all windows
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        // Look for the wallpaper window from Dock
        for window in windowList {
            if let owner = window[kCGWindowOwnerName as String] as? String,
               owner == "Dock",
               let name = window[kCGWindowName as String] as? String,
               name.starts(with: "Wallpaper-"),
               let layer = window[kCGWindowLayer as String] as? Int32,
               layer == -2147483624 { // This is the wallpaper layer
                
                // Extract UUID from wallpaper name
                let uuid = String(name.dropFirst("Wallpaper-".count))
                
                // If we haven't seen this wallpaper before, assign it the next space number
                if wallpaperCache[uuid] == nil {
                    let nextSpace = wallpaperCache.count + 1
                    wallpaperCache[uuid] = nextSpace
                }
                
                return wallpaperCache[uuid]
            }
        }
        
        return lastKnownSpace
    }
    
    static func showAlert(title: String, message: String, defaultText: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            
            // Create input field
            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            input.stringValue = defaultText
            alert.accessoryView = input
            
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            
            // Create a window to host the alert
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            
            // Position the window in the center of the current screen
            if let screen = NSScreen.main {
                let centerX = screen.frame.midX - (window.frame.width / 2)
                let centerY = screen.frame.midY - (window.frame.height / 2)
                window.setFrameOrigin(NSPoint(x: centerX, y: centerY))
            }
            
            // Make the window stay in the current space
            window.collectionBehavior = [.moveToActiveSpace]
            
            // Run the alert as a sheet on our temporary window
            window.makeKeyAndOrderFront(nil)
            alert.beginSheetModal(for: window) { response in
                let result = response == .alertFirstButtonReturn ? input.stringValue : nil
                window.close()
                completion(result)
            }
            
            // Focus the input field
            window.makeFirstResponder(input)
        }
    }
    
    static func debugPrintWindowInfo() {
        // Get all windows
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        print("\n--- Window Information Debug ---")
        for (index, window) in windowList.enumerated() {
            print("\nWindow \(index):")
            for (key, value) in window {
                print("\(key): \(value)")
            }
        }
        print("\n---------------------------")
    }
} 
 