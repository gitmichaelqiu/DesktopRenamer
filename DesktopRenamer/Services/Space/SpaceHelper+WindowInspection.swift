import AppKit
import CoreGraphics
import Foundation

extension SpaceHelper {

    static func getActiveWindowInfo() -> (id: Int, pid: Int32, frame: CGRect)? {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        if frontApp.processIdentifier == ourPID {
            // Find the first window in Z-order that is layer 0, not our PID, has valid size, and belongs to a regular app.
            for window in windowList {
                guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                      let windowPid = window[kCGWindowOwnerPID as String] as? Int,
                      windowPid != Int(ourPID),
                      let wid = window[kCGWindowNumber as String] as? Int,
                      let bounds = window[kCGWindowBounds as String] as? [String: Any],
                      let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                      let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat,
                      w >= minActiveWindowWidth, h >= minActiveWindowHeight
                else { continue }
                
                // Reject transparent or non-shared utility windows
                if let alpha = window[kCGWindowAlpha as String] as? Double, alpha <= 0.1 { continue }
                if let sharing = window[kCGWindowSharingState as String] as? Int, sharing == 0 { continue }
                
                // Ensure it's a regular application window (not a system overlay)
                if let app = NSRunningApplication(processIdentifier: Int32(windowPid)),
                   app.activationPolicy == .regular {
                    let info = (id: wid, pid: Int32(windowPid), frame: CGRect(x: x, y: y, width: w, height: h))
                    print("SpaceHelper: Captured active window ID: \(info.id), PID: \(info.pid), frame: \(info.frame) (using fallback scan)")
                    return info
                }
            }
        } else {
            let pid = frontApp.processIdentifier
            for window in windowList {
                if let windowPid = window[kCGWindowOwnerPID as String] as? Int,
                   windowPid == pid,
                   let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                   let wid = window[kCGWindowNumber as String] as? Int,
                   let bounds = window[kCGWindowBounds as String] as? [String: Any],
                   let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                   let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat {
                       
                       // Apply the same strict filtering for foreign windows to avoid capturing transparent/overlay helper windows!
                       if w < minActiveWindowWidth || h < minActiveWindowHeight { continue }
                       if let alpha = window[kCGWindowAlpha as String] as? Double, alpha <= 0.1 { continue }
                       if let sharing = window[kCGWindowSharingState as String] as? Int, sharing == 0 { continue }
                       
                       let info = (id: wid, pid: Int32(pid), frame: CGRect(x: x, y: y, width: w, height: h))
                       print("SpaceHelper: Captured active window ID: \(info.id), PID: \(info.pid), frame: \(info.frame)")
                       return info
                   }
            }
        }
        return nil
    }

    static func getActiveWindowInfo(forPID pid: Int32) -> (id: Int, pid: Int32, frame: CGRect)? {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        
        for window in windowList {
            if let windowPid = window[kCGWindowOwnerPID as String] as? Int,
               windowPid == Int(pid),
               let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
               let wid = window[kCGWindowNumber as String] as? Int,
               let bounds = window[kCGWindowBounds as String] as? [String: Any],
               let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
               let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat {
                   
                   // Apply filtering
                   if w < minActiveWindowWidth || h < minActiveWindowHeight { continue }
                   if let alpha = window[kCGWindowAlpha as String] as? Double, alpha <= 0.1 { continue }
                   if let sharing = window[kCGWindowSharingState as String] as? Int, sharing == 0 { continue }
                   
                   return (id: wid, pid: pid, frame: CGRect(x: x, y: y, width: w, height: h))
               }
        }
        return nil
    }

    static func getWindowInfo(id: Int) -> (pid: Int32, frame: CGRect)? {
        let options = CGWindowListOption(arrayLiteral: .optionIncludingWindow)
        let windowList = CGWindowListCopyWindowInfo(options, CGWindowID(id)) as? [[String: Any]] ?? []
        
        if let window = windowList.first,
           let pid = window[kCGWindowOwnerPID as String] as? Int32,
           let bounds = window[kCGWindowBounds as String] as? [String: Any],
           let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
           let w = bounds["Width"] as? CGFloat, let h = bounds["Height"] as? CGFloat {
               return (pid: pid, frame: CGRect(x: x, y: y, width: w, height: h))
        }
        return nil
    }

    static func getWindowSpaceID(id: Int) -> String? {
        let conn = _CGSDefaultConnection()
        let widArray = [id as NSNumber] as CFArray
        if let result = CGSCopySpacesForWindows(conn, 7, widArray),
           let spaceIDs = result as? [NSNumber],
           let firstSpace = spaceIDs.first {
            return String(firstSpace.intValue)
        }
        return nil
    }

    /// Returns the set of space IDs a window is currently assigned to by the CGS window server.
    static func getWindowCurrentSpaces(windowID: Int) -> Set<String> {
        let conn = _CGSDefaultConnection()
        let widArray = [windowID as NSNumber] as CFArray
        guard let result = CGSCopySpacesForWindows(conn, 7, widArray) as? [NSNumber] else {
            return []
        }
        return Set(result.map { String($0.intValue) })
    }

    static func getActiveWindowFrame() -> CGRect? {
        return getActiveWindowInfo()?.frame
    }

    static func getOwnerPID(for spaceID: String) -> Int32? {
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



    // Shortcut configuration helpers.

    static func isShortcutEnabled(for number: Int) -> Bool {
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
    static func simulateDesktopShortcut(for number: Int) -> Bool {
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

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)

        return true
    }
}
