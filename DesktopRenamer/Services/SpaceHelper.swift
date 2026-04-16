import AppKit
import CoreGraphics
import Foundation

@_silgen_name("_CGSDefaultConnection") private func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32)
    -> CFArray?
@_silgen_name("CGSCopyActiveMenuBarDisplayIdentifier")
private func CGSCopyActiveMenuBarDisplayIdentifier(_ cid: Int32) -> CFString?

class SpaceHelper {
    static var fullscreenThreshold: Int {
        get {
            UserDefaults.standard.integer(
                forKey: "com.michaelqiu.desktoprenamer.fullscreenthreshold")
        }
        set {
            UserDefaults.standard.set(
                newValue, forKey: "com.michaelqiu.desktoprenamer.fullscreenthreshold")
        }
    }

    private static var onSpaceChange: ((String, Bool, Int, String) -> Void)?
    static var isActivating: Bool = false
    private static var globalEventMonitor: Any?
    private static var localEventMonitor: Any?

    // Track switch state to prevent recursion glitches
    private static var isSwitching = false
    
    // Dragging session state
    private static var originalMousePoint: CGPoint? = nil
    private static var restorationTask: DispatchWorkItem? = nil
    private static var pendingMoveCount = 0
    static var isDragging: Bool { originalMousePoint != nil }

    // The meat of space switching logic
    static func switchToSpace(_ spaceID: String, forceMissionControl: Bool = false) {
        guard !isSwitching else { return }
        isSwitching = true

        defer {
            // Short delay to allow OS animations to settle before allowing another switch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isSwitching = false
            }
        }

        NotificationCenter.default.post(
            name: NSNotification.Name("SpaceSwitchRequested"), object: nil)

        // 1. Resolve Target Space Info
        var targetNum: Int? = nil
        var targetGlobalNum: Int? = nil
        var targetIsFullscreen = false
        var currentIsFullscreen = false
        var targetDisplayID: String = ""

        if let state = getSystemState(),
           let targetSpace = state.spaces.first(where: { $0.id == spaceID })
        {
            targetNum = targetSpace.num
            targetGlobalNum = targetSpace.globalShortcutNum
            targetIsFullscreen = targetSpace.isFullscreen
            targetDisplayID = targetSpace.displayID
            
            print("SpaceHelper: Switching to space \(spaceID) (Num: \(targetNum ?? -1), Global: \(targetGlobalNum ?? -1), Display: \(targetDisplayID))")
            
            // Check if we are already on the target space on its own display
            if let currentOnDisplay = state.currentSpaces[targetSpace.displayID], 
               currentOnDisplay == spaceID {
                print("SpaceHelper: Target space is already current on display \(targetDisplayID). Activating window.")
                _ = switchByActivatingOwnWindow(for: spaceID, isFullscreen: targetIsFullscreen)
                return
            }
            
            if let currentSpace = state.spaces.first(where: { $0.id == state.currentUUID }) {
                currentIsFullscreen = currentSpace.isFullscreen
            }
        } else {
            print("SpaceHelper: ERROR - Could not resolve target space state for \(spaceID)")
        }
        
        // Force Mission Control Automation for Fullscreen Transitions (if applicable)
        if forceMissionControl && (targetIsFullscreen || currentIsFullscreen) {
            if let num = targetNum {
                print("SpaceHelper: Using Mission Control fallback for fullscreen transition to \(num)")
                switchViaMissionControl(to: num)
                return
            }
        }

        // --- NEW PRIORITY START ---
        
        // Ensure the space is 'seeded' with an anchor window if it isn't already.
        // This is critical for fresh launches or newly created spaces.
        // Use synchronous dispatch to ensure window exists before activation attempt.
        let seedWindow = {
            MainActor.assumeIsolated {
                if let manager = AppDelegate.shared.statusBarController?.labelManager {
                    let spaceName = AppDelegate.shared.spaceManager?.getSpaceName(spaceID) ?? "Space"
                    manager.ensureWindow(for: spaceID, name: spaceName, displayID: targetDisplayID)
                }
            }
        }
        
        if Thread.isMainThread {
            seedWindow()
        } else {
            DispatchQueue.main.sync {
                seedWindow()
            }
        }
        
        // HIGHEST PRIORITY: Try window activation first. It's the most reliable 
        // across monitors and arrangements.
        print("SpaceHelper: Attempting primary method (Window Activation) for \(spaceID)")
        if switchByActivatingOwnWindow(for: spaceID, isFullscreen: targetIsFullscreen) {
            print("SpaceHelper: Window activation switch successful.")
            
            // High-priority fix for Fullscreen Focus:
            if targetIsFullscreen {
                if let pid = getOwnerPID(for: spaceID),
                    let app = NSRunningApplication(processIdentifier: pid)
                {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        app.activate(options: .activateIgnoringOtherApps)
                    }
                }
            }
            return
        }

        // SECOND PRIORITY: Try native shortcuts (if enabled and applicable)
        var shouldUseShortcut = !targetIsFullscreen
        if shouldUseShortcut {
            if let state = getSystemState(),
               let targetSpace = state.spaces.first(where: { $0.id == spaceID }) {
                let spacesOnDisplay = state.spaces.filter { $0.displayID == targetSpace.displayID }
                if spacesOnDisplay.prefix(while: { $0.id != spaceID }).contains(where: { $0.isFullscreen }) {
                    shouldUseShortcut = false
                }
            }
        }

        if shouldUseShortcut {
            if let globalNum = targetGlobalNum {
                print("SpaceHelper: Trying shortcut simulation for Global Num \(globalNum)")
                if isShortcutEnabled(for: globalNum) && simulateDesktopShortcut(for: globalNum) {
                    return
                }
            } else if let localNum = targetNum {
                print("SpaceHelper: Trying shortcut simulation for Local Num \(localNum)")
                if isShortcutEnabled(for: localNum) && simulateDesktopShortcut(for: localNum) {
                    return
                }
            }
        }
        
        // LAST RESORT: Mission Control
        if let num = targetNum {
            print("SpaceHelper: All methods failed. Falling back to Mission Control UI click for \(num)")
            switchViaMissionControl(to: num)
        }

        print("SpaceHelper: Switch attempt cycle finished for \(spaceID)")
    }

    private static func switchByActivatingOwnWindow(for spaceID: String, isFullscreen: Bool) -> Bool
    {
        if isActivating { return false }
        isActivating = true
        defer { isActivating = false }
        
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
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)

        return true
    }

    // MARK: - Window Moving Logic
    
    static func dragActiveWindow(to spaceID: String) {
        // Cancel any pending restoration from a previous "chained" move
        restorationTask?.cancel()
        restorationTask = nil
        
        let source = CGEventSource(stateID: .hidSystemState)
        
        // 1. Session Initialization: Only capture original mouse point and MouseDown for the FIRST move in a series
        if originalMousePoint == nil {
            // Save starting location
            originalMousePoint = CGEvent(source: nil)?.location
            
            // Get Active Window Frame & Position to calculate grab point
            guard let frame = getActiveWindowFrame() else {
                originalMousePoint = nil
                return 
            }
            
            let grabX: CGFloat
            let grabY: CGFloat
            
            if let sm = AppDelegate.shared.spaceManager {
                grabX = frame.origin.x + CGFloat(sm.grabOffsetX)
                grabY = frame.origin.y + CGFloat(sm.grabOffsetY)
            } else {
                grabX = frame.origin.x + 13
                grabY = frame.origin.y + 25
            }
            
            let grabPoint = CGPoint(x: grabX, y: grabY)
            
            // Move to grab point and Down
            if let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: grabPoint, mouseButton: .left) {
                moveEvent.flags = []
                moveEvent.post(tap: .cghidEventTap)
            }
            
            if let downEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: grabPoint, mouseButton: .left) {
                downEvent.flags = []
                downEvent.post(tap: .cghidEventTap)
            }
            
            usleep(50000) // 0.05s grip
        }
        
        // 2. Trigger Space Switch and track the move
        pendingMoveCount += 1
        switchToSpace(spaceID)
        
        // 3. Replace any existing restoration/drop tasks with a long safety fallback
        // This ensures the Mouse stays down until either a space change or a timeout.
        scheduleRestoration(delay: 2.0)
    }
    
    /// Fast-forwards the restoration process because we detected a successful space change.
    static func signalSpaceSwitchComplete() {
        guard originalMousePoint != nil else { return }
        
        // Decrement pending moves
        pendingMoveCount = max(0, pendingMoveCount - 1)
        
        // Only trigger the "Drop & Restore" if all pending moves are accounted for.
        // We replace the 2.0s safety timer with a quick 0.15s settle-and-restore.
        if pendingMoveCount == 0 {
            scheduleRestoration(delay: 0.15)
        }
    }
    
    /// Schedules an atomic cleanup task that drops the window and restores the cursor.
    /// Calling this automatically cancels any previously scheduled restoration job.
    private static func scheduleRestoration(delay: TimeInterval) {
        // Atomic Cancellation: This is the critical fix for "multi restoration" bugs.
        restorationTask?.cancel()
        
        let source = CGEventSource(stateID: .hidSystemState)
        let task = DispatchWorkItem { [originalPoint = originalMousePoint] in
            guard let restorePoint = originalPoint else { 
                originalMousePoint = nil
                restorationTask = nil
                pendingMoveCount = 0
                return 
            }
            
            // 1. Drop (Mouse Up)
            if let upEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: CGEvent(source: nil)?.location ?? .zero, mouseButton: .left) {
                upEvent.flags = []
                upEvent.post(tap: .cghidEventTap)
            }
            
            // 2. Restore Mouse
            usleep(50000)
            if let restoreEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: restorePoint, mouseButton: .left) {
                restoreEvent.flags = []
                restoreEvent.post(tap: .cghidEventTap)
            }
            
            // 3. Reset Session
            originalMousePoint = nil
            restorationTask = nil
            pendingMoveCount = 0
        }
        
        restorationTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }
    
    static func getActiveWindowFrame() -> CGRect? {
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
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else {
            return nil
        }

        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for space in spaces {
                guard let managedID = space["ManagedSpaceID"] as? Int,
                    String(managedID) == spaceID
                else { continue }

                return space["pid"] as? Int32 ?? space["owner pid"] as? Int32
            }
        }
        return nil
    }

    private static func switchViaMissionControl(to targetNum: Int) {
        let source = """
            tell application "Mission Control" to launch
            tell application "System Events"
                delay 0.4
                tell process "Dock"
                    -- Try to find the button in any of the potential mission control button lists (for multiple monitors)
                    set found to false
                    try
                        -- Common hierarchy for main display
                        click button \(targetNum) of list 1 of group 2 of group 1 of group 1
                        set found to true
                    on error
                        try
                            -- Often for secondary displays
                            click button \(targetNum) of list 1 of group 1 of group 1 of group 1
                            set found to true
                        on error
                             -- Fallback: try iteration if the above fixed paths fail
                             set allGroups to every group of group 1 of group 1
                             repeat with g in allGroups
                                 try
                                     click button \(targetNum) of list 1 of g
                                     set found to true
                                     exit repeat
                                 end try
                             end repeat
                        end try
                    end try
                    
                    if not found then
                        key code 53 -- Esc to exit if failed
                    end if
                end tell
            end tell
            """

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: source) {
                scriptObject.executeAndReturnError(&error)
            }
        }
    }

    // Help with shortcut logic

    private static func isShortcutEnabled(for number: Int) -> Bool {
        let baseID = 118
        let targetID = baseID + (number - 1)

        guard
            let dict = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
            let hotkeys = dict["AppleSymbolicHotKeys"] as? [String: Any]
        else {
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
            parameters.count >= 3
        {

            let registeredKeyCode = parameters[1]
            let registeredModifiers = parameters[2]

            let expectedKeyCode = Int(getKeyCode(for: number))
            let expectedModifiers = 262144  // Control

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
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskControl
        keyUp.flags = .maskControl

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        return true
    }

    static func startMonitoring(onChange: @escaping (String, Bool, Int, String) -> Void) {
        self.onSpaceChange = onChange

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in detectSpaceChange() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { _ in detectSpaceChange() }

        // Event monitors to catch when the user clicks around or does something that might change spaces
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { event in
            detectSpaceChange()
            return event
        }

        detectSpaceChange()
    }

    static func stopMonitoring() {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }

    private static func getActiveDisplay() -> NSScreen? {
        if let frontApp = NSWorkspace.shared.frontmostApplication,
            frontApp.bundleIdentifier != "com.apple.finder"
        {
            let options = CGWindowListOption(
                arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
            let windowList =
                CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

            for window in windowList {
                if let pid = window[kCGWindowOwnerPID as String] as? Int,
                    pid == frontApp.processIdentifier,
                    let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                    let bounds = window[kCGWindowBounds as String] as? [String: Any],
                    let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                    let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat
                {
                    let center = CGPoint(x: x + w / 2, y: y + h / 2)
                    for screen in NSScreen.screens {
                        if isPoint(center, inside: screen.frame) { return screen }
                    }
                }
            }
        }
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }

    static func getRawSpaceUUID(completion: @escaping (String, Bool, Int, String) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let activeScreen = getActiveDisplay() else {
                completion("", false, 0, "Unknown")
                return
            }
            let screenID =
                activeScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber ?? 0
            
            var displayIdentifier = "\(activeScreen.localizedName) (\(screenID))"
            if let uuidRef = CGDisplayCreateUUIDFromDisplayID(screenID.uint32Value) {
                let uuid = uuidRef.takeRetainedValue()
                if let uuidStr = CFUUIDCreateString(nil, uuid) as String? {
                    displayIdentifier = uuidStr.uppercased()
                }
            }

            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
            let windowList =
                CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

            var uuid = ""
            var ncCnt = 0
            var hasFinderDesktop = false
            for window in windowList {
                guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                    let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                    let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat
                else { continue }

                if isPoint(CGPoint(x: x + w / 2, y: y + h / 2), inside: activeScreen.frame),
                    let owner = window[kCGWindowOwnerName as String] as? String
                {
                    if owner == "Dock", let name = window[kCGWindowName as String] as? String,
                        name.starts(with: "Wallpaper-")
                    {
                        uuid = String(name.dropFirst("Wallpaper-".count))
                        if uuid == "" { uuid = "MAIN" }
                    }
                    if owner == "Notification Center" { ncCnt += 1 }
                    if owner == "Finder", let layer = window[kCGWindowLayer as String] as? Int,
                        layer < 0
                    {
                        hasFinderDesktop = true
                    }
                }
            }
            completion(uuid, hasFinderDesktop, ncCnt, displayIdentifier)
        }
    }

    static func getVisibleSpaceUUIDs(completion: @escaping (Set<String>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
            let windowList =
                CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            let screens = NSScreen.screens
            var visibleUUIDs = Set<String>()

            if screens.isEmpty {
                completion([])
                return
            }
            for screen in screens {
                for window in windowList {
                    guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                        let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                        let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat
                    else { continue }
                    if isPoint(CGPoint(x: x + w / 2, y: y + h / 2), inside: screen.frame) {
                        if let owner = window[kCGWindowOwnerName as String] as? String,
                            owner == "Dock",
                            let name = window[kCGWindowName as String] as? String,
                            name.starts(with: "Wallpaper-")
                        {
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

    private static func getAllDisplayUUIDs() -> [String] {
        return NSScreen.screens.compactMap { screen -> String? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
            return CFUUIDCreateString(nil, uuid) as String
        }
    }

    private static func normalizeDisplayID(_ id: String, mainUUID: String?) -> String {
        guard let main = mainUUID else { return id.uppercased() }
        let result = id == "Main" ? main : id
        return result.uppercased()
    }

    static func getSystemState() -> (
        spaces: [DesktopSpace], currentUUID: String, displayID: String,
        currentSpaces: [String: String] // Mapping: displayID -> currentSpaceUUID
    )? {
        let conn = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else {
            return nil
        }
        guard let activeDisplayRaw = CGSCopyActiveMenuBarDisplayIdentifier(conn) as? String else {
            return nil
        }

        let screenUUIDs = getAllDisplayUUIDs()
        let mainScreenUUID = screenUUIDs.first
        
        let activeDisplay = normalizeDisplayID(activeDisplayRaw, mainUUID: mainScreenUUID)
        
        var detectedSpaces: [DesktopSpace] = []
        var currentSpaceID = "FULLSCREEN"
        var currentSpaces: [String: String] = [:]

        var targetDisplayID = activeDisplay // Default to active menu bar display
        
        // Find if target display is actually present in CGS displays (handling normalization)
        let foundDisplay = displays.first { d in
            let dID = d["Display Identifier"] as? String ?? ""
            return normalizeDisplayID(dID, mainUUID: mainScreenUUID) == activeDisplay
        }
        
        if foundDisplay == nil {
            // If active display not found, fallback to Main
            targetDisplayID = mainScreenUUID ?? activeDisplay
        }

        var globalDesktopCounter = 0

        // SORT: Ensure displays are processed in the order macOS assigns shortcuts.
        // For multi-monitor, this usually follows primary monitor then spatial arrangement.
        let screenFrames: [String: CGRect] = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { s in
            let sID = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber ?? 0
            guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(sID.uint32Value)?.takeRetainedValue() else { return nil }
            let uuid = (CFUUIDCreateString(nil, uuidRef) as String).uppercased()
            return (uuid, s.frame)
        })

        let sortedDisplays = displays.sorted { d1, d2 in
            let id1raw = d1["Display Identifier"] as? String ?? ""
            let id2raw = d2["Display Identifier"] as? String ?? ""
            let id1 = normalizeDisplayID(id1raw, mainUUID: mainScreenUUID)
            let id2 = normalizeDisplayID(id2raw, mainUUID: mainScreenUUID)
            
            guard let frame1 = screenFrames[id1], let frame2 = screenFrames[id2] else {
                let idx1 = screenUUIDs.firstIndex(of: id1) ?? Int.max
                let idx2 = screenUUIDs.firstIndex(of: id2) ?? Int.max
                return idx1 < idx2
            }
            
            // Spatial Sort: 
            // 1. Primary monitor (origin 0,0) always comes first for shortcut indexing
            if frame1.origin.x == 0 && frame1.origin.y == 0 { return true }
            if frame2.origin.x == 0 && frame2.origin.y == 0 { return false }
            
            // 2. Top-to-Bottom (Higher Y origin means Top)
            if abs(frame1.origin.y - frame2.origin.y) > 50 { 
                return frame1.origin.y > frame2.origin.y
            }
            // 3. Left-to-Right
            return frame1.origin.x < frame2.origin.x
        }

        for display in sortedDisplays {
            guard let displayIDRaw = display["Display Identifier"] as? String,
                let spaces = display["Spaces"] as? [[String: Any]]
            else { continue }
            
            let displayID = normalizeDisplayID(displayIDRaw, mainUUID: mainScreenUUID)

            var regularIndex = 0
            for space in spaces {
                guard let managedID = space["ManagedSpaceID"] as? Int else { continue }
                let idString = String(managedID)
                let isFullscreen = space["TileLayoutManager"] != nil

                var appName: String? = nil
                var globalShortcutNum: Int? = nil

                if isFullscreen {
                    if let p = space["pid"] as? Int32 ?? space["owner pid"] as? Int32 {
                        appName = NSRunningApplication(processIdentifier: p)?.localizedName
                    }
                } else {
                    globalDesktopCounter += 1
                    globalShortcutNum = globalDesktopCounter
                }

                regularIndex += 1
                detectedSpaces.append(
                    DesktopSpace(
                        id: idString,
                        customName: "",
                        num: regularIndex,
                        displayID: displayID,
                        isFullscreen: isFullscreen,
                        appName: appName,
                        globalShortcutNum: globalShortcutNum
                    ))

                if let currentDict = display["Current Space"] as? [String: Any],
                    let currentID = currentDict["ManagedSpaceID"] as? Int, currentID == managedID
                {
                    currentSpaces[displayID] = idString
                    if displayID == targetDisplayID {
                        currentSpaceID = idString
                    }
                }
            }
        }
        return (detectedSpaces, currentSpaceID, targetDisplayID, currentSpaces)
    }

    static func getVisibleSystemSpaceIDs() -> Set<String> {
        let conn = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else { return [] }
        var visibleIDs = Set<String>()
        for display in displays {
            if let currentDict = display["Current Space"] as? [String: Any],
                let currentID = currentDict["ManagedSpaceID"] as? Int
            {
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
        guard
            let screen = NSScreen.screens.first(where: {
                NSMouseInRect(mouseLocation, $0.frame, false)
            })
        else { return nil }

        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID
        else { return nil }
        guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
        let uuid = uuidRef.takeRetainedValue()
        return (CFUUIDCreateString(nil, uuid) as String).uppercased()
    }

    static func getWindowDisplayID(for frame: CGRect) -> String? {
        // Calculate center of the window
        // Note: Window server uses top-left origin for frames from CGWindowListCopyWindowInfo
        let center = CGPoint(x: frame.origin.x + frame.width / 2, y: frame.origin.y + frame.height / 2)
        
        // Find screen using CGWindowList coordinates (top-left origin, Y increases downwards)
        // We find the screen whose frame contains this point in CG coordinates
        for screen in NSScreen.screens {
            // Convert screen frame to CG coordinates (top-left)
            // Primary screen is at 0,0. Others relative.
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            let cgFrame = CGDisplayBounds(screenID)
            
            if cgFrame.contains(center) {
                guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(screenID) else { continue }
                let uuid = uuidRef.takeRetainedValue()
                return (CFUUIDCreateString(nil, uuid) as String).uppercased()
            }
        }
        
        return nil
    }

    static func getCurrentSpaceID(for displayID: String) -> String? {
        let conn = _CGSDefaultConnection()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else {
            return nil
        }
        
        let screenUUIDs = getAllDisplayUUIDs()
        let mainScreenUUID = screenUUIDs.first

        for display in displays {
            if let rawID = display["Display Identifier"] as? String {
                let currentID = normalizeDisplayID(rawID, mainUUID: mainScreenUUID)
                if currentID == displayID,
                   let currentDict = display["Current Space"] as? [String: Any],
                   let managedID = currentDict["ManagedSpaceID"] as? Int
                {
                    return String(managedID)
                }
            }
        }
        return nil
    }

    static func isPoint(_ point: CGPoint, inside screenFrame: CGRect) -> Bool {
        guard
            let primaryScreen = NSScreen.screens.first(where: {
                $0.frame.origin.x == 0 && $0.frame.origin.y == 0
            })
        else {
            return screenFrame.contains(point)
        }
        let flippedY = NSMaxY(primaryScreen.frame) - point.y
        return screenFrame.contains(CGPoint(x: point.x, y: flippedY))
    }
}
