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
        var targetGlobalNum: Int? = nil
        var shouldUseShortcut = true
        var targetIsFullscreen = false
        
        if let state = getSystemState(),
           let targetSpace = state.spaces.first(where: { $0.id == spaceID }) {
            targetNum = targetSpace.num
            targetGlobalNum = targetSpace.globalShortcutNum
            targetIsFullscreen = targetSpace.isFullscreen
            
            // If we are already on the target space, stop.
            if state.currentUUID == spaceID { return }
            
            // CHECK: Native shortcuts (Ctrl+1, Ctrl+2) only map to Desktops.
            if targetSpace.isFullscreen {
                shouldUseShortcut = false
            } else {
                let spacesBefore = state.spaces.filter { $0.displayID == targetSpace.displayID && $0.num < targetSpace.num }
                if spacesBefore.contains(where: { $0.isFullscreen }) {
                    shouldUseShortcut = false
                }
            }
        }
        
        // 2. PRIORITY: Simulate Keyboard Shortcut (Control + Number)
        // Only valid for standard desktops.
        // multi-display support: use global shortcut index if available
        if shouldUseShortcut {
            if let globalNum = targetGlobalNum {
                if isShortcutEnabled(for: globalNum) && simulateDesktopShortcut(for: globalNum) {
                    return
                }
            } else if let localNum = targetNum {
                // Fallback to local num if global is missing (should verify if this is ever needed/correct)
                if isShortcutEnabled(for: localNum) && simulateDesktopShortcut(for: localNum) {
                    return
                }
            }
        }
        
        // 3. Unified Activation Logic
        // We use our own SpaceLabelWindow for both Desktop and Fullscreen because it is the fastest method.
        // However, each requires specific handling to avoid bugs (reversion/focus stealing).
        if switchByActivatingOwnWindow(for: spaceID, isFullscreen: targetIsFullscreen) {
            
            // FIX for Fullscreen Focus:
            // When switching to a Fullscreen space via SpaceLabelWindow, DesktopRenamer initially gets focus.
            // This can cause the OS to revert to the previous space if we don't hand off focus immediately.
            // We must identify the "owner" app of the fullscreen space and activate it.
            // Since we just triggered the visual switch, activating the app now should correctly
            // prioritize the window on the target space (resolving the "multiple windows" ambiguity).
            if targetIsFullscreen {
                if let pid = getOwnerPID(for: spaceID),
                   let app = NSRunningApplication(processIdentifier: pid) {
                    
                    // A very short delay ensures the Window Server registers the space switch intent
                    // before we force the app activation.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        app.activate(options: .activateIgnoringOtherApps)
                    }
                }
            }
            return
        }
        
        // 4. Fallback: Mission Control UI Scripting
        if let num = targetNum {
            switchViaMissionControl(to: num)
        }
    }
    
    private static func switchByActivatingOwnWindow(for spaceID: String, isFullscreen: Bool) -> Bool {
        var targetWindow: SpaceLabelWindow? = nil
        var windowsToHide: [SpaceLabelWindow] = []
        
        // 1. Identify Target and Potential Conflict Windows
        for window in NSApp.windows {
            if let labelWindow = window as? SpaceLabelWindow {
                if labelWindow.spaceId == spaceID {
                    targetWindow = labelWindow
                } else if labelWindow.isVisible {
                    windowsToHide.append(labelWindow)
                }
            }
        }
        
        guard let window = targetWindow else { return false }
        
        // 2. "Hide Others" Logic
        // For Desktop targets: We hide other windows to remove ambiguity about "Last Active Space".
        // This forces the OS to switch to the target window.
        // For Fullscreen targets: We MUST NOT hide the desktop window. Doing so removes the app's
        // anchor on the main desktop, causing the OS to panic and revert to the previous space.
        if !isFullscreen {
            for other in windowsToHide {
                other.orderOut(nil)
            }
        }
        
        // 3. Force Activation
        // 3. Force Activation
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        
        return true
    }
    
    // MARK: - Window Moving Logic
    
    static func dragActiveWindow(to spaceID: String) {
        // 1. Get Active Window Frame & Position
        guard let frame = getActiveWindowFrame() else { return }
        
        // 2. Calculate Grab Point (Top Center - likely title bar)
        // Ensure we don't click too high (menu bar) or off window
        let headerHeight: CGFloat = 20
        let grabX = frame.origin.x + (frame.width / 2)
        let grabY = frame.origin.y + (headerHeight / 2) + 5 // 15px down from top
        let grabPoint = CGPoint(x: grabX, y: grabY)
        
        // 3. Save Current Mouse Position
        let currentMouse = CGEvent(source: nil)?.location ?? grabPoint
        
        // 4. Perform Drag Sequence
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Move to grab point
        let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: grabPoint, mouseButton: .left)
        moveEvent?.post(tap: .cghidEventTap)
        
        // Click Down (Hold)
        let downEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: grabPoint, mouseButton: .left)
        downEvent?.post(tap: .cghidEventTap)
        
        // Small delay to ensure grip
        usleep(50000) // 0.05s
        
        // 5. Trigger Space Switch
        switchToSpace(spaceID)
        
        // 6. Wait for switch to complete, then Drop
        // We use a decent delay to allow the animation to start/cross threshold. 
        // macOS handles the "window dragged to edge" logic during the space swich.
        // Actually, if we just hold the mouse down and switch space, the window SHOULD move with the focus?
        // No, in Mission Control switching, the window stays unless we are dragging it.
        // By simulating a hold ("Drag"), the OS considers the window attached to the cursor.
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
            // Drop (Mouse Up)
            let upEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: grabPoint, mouseButton: .left)
            upEvent?.post(tap: .cghidEventTap)
            
            // Restore Mouse
            usleep(50000)
            let restoreEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: currentMouse, mouseButton: .left)
            restoreEvent?.post(tap: .cghidEventTap)
        }
    }
    
    private static func getActiveWindowFrame() -> CGRect? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier
        
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        for window in windowList {
            if let windowPid = window[kCGWindowOwnerPID as String] as? Int,
               windowPid == pid,
               let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
               let bounds = window[kCGWindowBounds as String] as? [String: Any],
               let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
               let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat {
                   return CGRect(x: x, y: y, width: w, height: h)
               }
        }
        return nil
    }
    
    private static func getOwnerPID(for spaceID: String) -> Int32? {
        let conn = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else { return nil }
        
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for space in spaces {
                guard let managedID = space["ManagedSpaceID"] as? Int,
                      String(managedID) == spaceID else { continue }
                
                return space["pid"] as? Int32 ?? space["owner pid"] as? Int32
            }
        }
        return nil
    }
    
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
        
        var globalDesktopCounter = 0
        
        // SORT: Ensure displays are processed in the order macOS assigns shortcuts (Main then others).
        // NSScreen.screens[0] is Main. The order typically matches the shortcut assignment.
        let screenOrder = NSScreen.screens.compactMap { screen -> String? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
            return CFUUIDCreateString(nil, uuid) as String
        }
        
        let sortedDisplays = displays.sorted { d1, d2 in
            guard let id1 = d1["Display Identifier"] as? String,
                  let id2 = d2["Display Identifier"] as? String else { return false }
            let idx1 = screenOrder.firstIndex(of: id1) ?? Int.max
            let idx2 = screenOrder.firstIndex(of: id2) ?? Int.max
            return idx1 < idx2
        }
        
        for display in sortedDisplays {
            guard let displayID = display["Display Identifier"] as? String,
                  let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            
            var regularIndex = 0
            for space in spaces {
                guard let managedID = space["ManagedSpaceID"] as? Int else { continue }
                let idString = String(managedID)
                let isFullscreen = space["TileLayoutManager"] != nil
                
                var appName: String? = nil
                var globalShortcutNum: Int? = nil
                
                if isFullscreen {
                    // Try to extract PID from space dictionary to get Name, but do NOT store PID in model
                    if let p = space["pid"] as? Int32 ?? space["owner pid"] as? Int32 {
                        appName = NSRunningApplication(processIdentifier: p)?.localizedName
                    }
                } else {
                    // Only standard desktops get a global shortcut number
                    globalDesktopCounter += 1
                    globalShortcutNum = globalDesktopCounter
                }

                regularIndex += 1
                detectedSpaces.append(DesktopSpace(
                    id: idString,
                    customName: "",
                    num: regularIndex,
                    displayID: displayID,
                    isFullscreen: isFullscreen,
                    appName: appName,
                    globalShortcutNum: globalShortcutNum
                ))
                
                if let currentDict = display["Current Space"] as? [String: Any],
                   let currentID = currentDict["ManagedSpaceID"] as? Int, currentID == managedID {
                    if displayID == targetDisplayID {
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

    static func getCursorDisplayID() -> String? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) else { return nil }
        
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
        guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
        let uuid = uuidRef.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func getCurrentSpaceID(for displayID: String) -> String? {
        let conn = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else { return nil }
        
        for display in displays {
            if let id = display["Display Identifier"] as? String, id == displayID,
               let currentDict = display["Current Space"] as? [String: Any],
               let currentID = currentDict["ManagedSpaceID"] as? Int {
                return String(currentID)
            }
        }
        return nil
    }

    static func isPoint(_ point: CGPoint, inside screenFrame: CGRect) -> Bool {
        guard let primaryScreen = NSScreen.screens.first(where: { $0.frame.origin.x == 0 && $0.frame.origin.y == 0 }) else {
            return screenFrame.contains(point)
        }
        let flippedY = NSMaxY(primaryScreen.frame) - point.y
        return screenFrame.contains(CGPoint(x: point.x, y: flippedY))
    }
}
