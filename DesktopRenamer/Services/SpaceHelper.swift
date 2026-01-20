import Foundation
import AppKit
import CoreGraphics

// MARK: - CGS Private API Definitions (Read-Only)
@_silgen_name("_CGSDefaultConnection") private func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray?
@_silgen_name("CGSCopyActiveMenuBarDisplayIdentifier") private func CGSCopyActiveMenuBarDisplayIdentifier(_ cid: Int32) -> CFString?

class SpaceHelper {
    static var fullscreenThreshold: Int {
        get { UserDefaults.standard.integer(forKey: "com.michaelqiu.desktoprenamer.fullscreenthreshold") }
        set { UserDefaults.standard.set(newValue, forKey: "com.michaelqiu.desktoprenamer.fullscreenthreshold") }
    }

    private static var onSpaceChange: ((String, Bool, Int, String) -> Void)?
    private static var globalEventMonitor: Any?
    private static var localEventMonitor: Any?
    
    // Track switch state to prevent recursion glitches
    private static var isSwitching = false
    
    // MARK: - Space Switching Logic
    static func switchToSpace(_ spaceID: String) {
        guard !isSwitching else { return }
        isSwitching = true
        
        defer {
            // Short delay to allow OS animations to settle before allowing another switch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isSwitching = false
            }
        }
        
        // 1. Resolve Target Space Info
        var targetNum: Int? = nil
        var shouldUseShortcut = true
        
        if let state = getSystemState(),
           let targetSpace = state.spaces.first(where: { $0.id == spaceID }) {
            targetNum = targetSpace.num
            
            // If we are already on the target space, stop.
            if state.currentUUID == spaceID { return }
            
            // CHECK: Native shortcuts (Ctrl+1, Ctrl+2) only map to Desktops.
            // If there are any fullscreen apps *before* this target, or if the target itself is fullscreen,
            // the Visual Index (num) will not match the Native Desktop Index.
            // In such cases, we MUST NOT use shortcut simulation.
            
            if targetSpace.isFullscreen {
                shouldUseShortcut = false
            } else {
                // Check for any fullscreen spaces before this one on the same display
                let spacesBefore = state.spaces.filter { $0.displayID == targetSpace.displayID && $0.num < targetSpace.num }
                if spacesBefore.contains(where: { $0.isFullscreen }) {
                    shouldUseShortcut = false
                }
            }
        }
        
        // 2. PRIORITY: Simulate Keyboard Shortcut (Control + Number)
        // Native shortcuts are the cleanest way to switch, but only valid for pure desktop indexes.
        if shouldUseShortcut, let num = targetNum {
            if isShortcutEnabled(for: num) && simulateDesktopShortcut(for: num) {
                return
            }
        }
        
        // 3. Fallback A: Activate our own Space Label Window
        // This relies on SpaceLabelManager creating windows on every space.
        // Even if the user "disables" labels, the windows should be kept alive (alpha=0)
        // so this switching method remains available.
        if switchByActivatingOwnWindow(for: spaceID) {
            return
        }
        
        // 4. Fallback B: Mission Control UI Scripting
        // Note: targetNum corresponds to the visual slot in Mission Control, so this works for Fullscreen apps too.
        if let num = targetNum {
            switchViaMissionControl(to: num)
        }
    }
    
    private static func switchByActivatingOwnWindow(for spaceID: String) -> Bool {
        for window in NSApp.windows {
            // Check for SpaceLabelWindow
            if let labelWindow = window as? SpaceLabelWindow, labelWindow.spaceId == spaceID {
                // Force app activation first to ensure the window promotion works
                NSApp.activate(ignoringOtherApps: true)
                
                // Even if the window is invisible (alpha 0), makeKeyAndOrderFront
                // triggers the OS to switch to its space.
                labelWindow.makeKeyAndOrderFront(nil)
                return true
            }
        }
        return false
    }
    
    // MARK: - Mission Control Logic (Fallback C)
    
    private static func switchViaMissionControl(to targetNum: Int) {
        let source = """
        tell application "Mission Control" to launch
        tell application "System Events"
            delay 0.3
            try
                click button \(targetNum) of list 1 of group 2 of group 1 of group 1 of process "Dock"
            on error
                key code 53 -- Esc to exit if failed
            end try
        end tell
        """
        
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: source) {
                scriptObject.executeAndReturnError(&error)
            }
        }
    }
    
    // MARK: - Shortcut Helpers
    
    private static func isShortcutEnabled(for number: Int) -> Bool {
        let baseID = 118
        let targetID = baseID + (number - 1)
        
        guard let dict = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let hotkeys = dict["AppleSymbolicHotKeys"] as? [String: Any] else {
            return true
        }
        
        guard let targetKeyDict = hotkeys[String(targetID)] as? [String: Any] else {
            return true
        }
        
        if let enabled = targetKeyDict["enabled"] as? Bool, !enabled {
            return false
        }
        
        if let value = targetKeyDict["value"] as? [String: Any],
           let parameters = value["parameters"] as? [Int],
           parameters.count >= 3 {
            
            let registeredKeyCode = parameters[1]
            let registeredModifiers = parameters[2]
            
            let expectedKeyCode = Int(getKeyCode(for: number))
            let expectedModifiers = 262144 // Control
            
            if registeredKeyCode != expectedKeyCode || registeredModifiers != expectedModifiers {
                 return false
            }
        }
        
        return true
    }
    
    private static func getKeyCode(for number: Int) -> CGKeyCode {
        switch number {
        case 1: return 18
        case 2: return 19
        case 3: return 20
        case 4: return 21
        case 5: return 23
        case 6: return 22
        case 7: return 26
        case 8: return 28
        case 9: return 25
        case 10: return 29
        default: return 255
        }
    }

    @discardableResult
    private static func simulateDesktopShortcut(for number: Int) -> Bool {
        let code = getKeyCode(for: number)
        if code == 255 { return false }
        
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else {
            return false
        }
        
        keyDown.flags = .maskControl
        keyUp.flags = .maskControl
        
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        
        return true
    }
    
    static func startMonitoring(onChange: @escaping (String, Bool, Int, String) -> Void) {
        onSpaceChange = onChange
        
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in detectSpaceChange() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in detectSpaceChange() }
        
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in detectSpaceChange() }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
             detectSpaceChange()
             return event
        }
        
        detectSpaceChange()
    }
    
    static func stopMonitoring() {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let monitor = globalEventMonitor { NSEvent.removeMonitor(monitor); globalEventMonitor = nil }
        if let monitor = localEventMonitor { NSEvent.removeMonitor(monitor); localEventMonitor = nil }
    }
    
    private static func getActiveDisplay() -> NSScreen? {
        if let frontApp = NSWorkspace.shared.frontmostApplication, frontApp.bundleIdentifier != "com.apple.finder" {
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            
            for window in windowList {
                if let pid = window[kCGWindowOwnerPID as String] as? Int,
                   pid == frontApp.processIdentifier,
                   let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                   let bounds = window[kCGWindowBounds as String] as? [String: Any],
                   let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                   let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat {
                    let center = CGPoint(x: x + w/2, y: y + h/2)
                    for screen in NSScreen.screens { if isPoint(center, inside: screen.frame) { return screen } }
                }
            }
        }
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }
    
    static func getRawSpaceUUID(completion: @escaping (String, Bool, Int, String) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let activeScreen = getActiveDisplay() else { completion("", false, 0, "Unknown"); return }
            let screenID = activeScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber ?? 0
            let displayIdentifier = "\(activeScreen.localizedName) (\(screenID))"
            
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            
            var uuid = "", ncCnt = 0, hasFinderDesktop = false
            for window in windowList {
                guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                      let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                      let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat else { continue }
                
                if isPoint(CGPoint(x: x + w/2, y: y + h/2), inside: activeScreen.frame),
                   let owner = window[kCGWindowOwnerName as String] as? String {
                    if owner == "Dock", let name = window[kCGWindowName as String] as? String, name.starts(with: "Wallpaper-") {
                        uuid = String(name.dropFirst("Wallpaper-".count))
                        if uuid == "" { uuid = "MAIN" }
                    }
                    if owner == "Notification Center" { ncCnt += 1 }
                    if owner == "Finder", let layer = window[kCGWindowLayer as String] as? Int, layer < 0 { hasFinderDesktop = true }
                }
            }
            completion(uuid, hasFinderDesktop, ncCnt, displayIdentifier)
        }
    }
        
    static func getVisibleSpaceUUIDs(completion: @escaping (Set<String>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            let screens = NSScreen.screens
            var visibleUUIDs = Set<String>()

            if screens.isEmpty { completion([]); return }
            for screen in screens {
                for window in windowList {
                    guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                          let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                          let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat else { continue }
                    if isPoint(CGPoint(x: x + w/2, y: y + h/2), inside: screen.frame) {
                        if let owner = window[kCGWindowOwnerName as String] as? String, owner == "Dock",
                           let name = window[kCGWindowName as String] as? String, name.starts(with: "Wallpaper-") {
                            let uuid = String(name.dropFirst("Wallpaper-".count))
                            visibleUUIDs.insert(uuid.isEmpty ? "MAIN" : uuid)
                            break
                        }
                    }
                }
            }
            completion(visibleUUIDs)
        }
    }
    
    static func getSystemState() -> (spaces: [DesktopSpace], currentUUID: String, displayID: String)? {
        let conn = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else { return nil }
        guard let activeDisplay = CGSCopyActiveMenuBarDisplayIdentifier(conn) as? String else { return nil }
        
        var detectedSpaces: [DesktopSpace] = []
        var currentSpaceID = "FULLSCREEN"
        
        let targetDisplayID = displays.contains { ($0["Display Identifier"] as? String) == activeDisplay }
            ? activeDisplay
            : (displays.first { ($0["Display Identifier"] as? String) == "Main" }?["Display Identifier"] as? String ?? activeDisplay)
        
        for display in displays {
            guard let displayID = display["Display Identifier"] as? String,
                  let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            
            var regularIndex = 0
            for space in spaces {
                guard let managedID = space["ManagedSpaceID"] as? Int else { continue }
                let idString = String(managedID)
                let isFullscreen = space["TileLayoutManager"] != nil
                
                // CHANGE: We now include Fullscreen spaces in the detected list so they can be switched to.
                // We mark them with isFullscreen = true.
                regularIndex += 1
                detectedSpaces.append(DesktopSpace(id: idString, customName: "", num: regularIndex, displayID: displayID, isFullscreen: isFullscreen))
                
                if let currentDict = display["Current Space"] as? [String: Any],
                   let currentID = currentDict["ManagedSpaceID"] as? Int, currentID == managedID {
                    if displayID == targetDisplayID {
                        // CHANGE: We use the real UUID for detection even if it is fullscreen,
                        // instead of collapsing it to "FULLSCREEN".
                        currentSpaceID = idString
                    }
                }
            }
        }
        return (detectedSpaces, currentSpaceID, targetDisplayID)
    }
    
    static func getVisibleSystemSpaceIDs() -> Set<String> {
        let conn = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else { return [] }
        var visibleIDs = Set<String>()
        for display in displays {
            if let currentDict = display["Current Space"] as? [String: Any],
               let currentID = currentDict["ManagedSpaceID"] as? Int {
                visibleIDs.insert(String(currentID))
            }
        }
        return visibleIDs
    }
    
    static func detectSpaceChange() {
        getRawSpaceUUID { spaceUUID, isDesktop, ncCnt, displayID in
            onSpaceChange?(spaceUUID, isDesktop, ncCnt, displayID)
        }
    }

    static func isPoint(_ point: CGPoint, inside screenFrame: CGRect) -> Bool {
        guard let primaryScreen = NSScreen.screens.first(where: { $0.frame.origin.x == 0 && $0.frame.origin.y == 0 }) else {
            return screenFrame.contains(point)
        }
        let flippedY = NSMaxY(primaryScreen.frame) - point.y
        return screenFrame.contains(CGPoint(x: point.x, y: flippedY))
    }
}
