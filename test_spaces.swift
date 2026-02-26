import AppKit

@_silgen_name("_CGSDefaultConnection") func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray?
@_silgen_name("CGSAddWindowsToSpaces") func CGSAddWindowsToSpaces(_ cid: Int32, _ windows: CFArray, _ spaces: CFArray)
@_silgen_name("CGSRemoveWindowsFromSpaces") func CGSRemoveWindowsFromSpaces(_ cid: Int32, _ windows: CFArray, _ spaces: CFArray)

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Test Window"
        window.makeKeyAndOrderFront(nil)
        window.collectionBehavior = .managed
        
        // Wait 2 seconds, then move window to the next space
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let cid = _CGSDefaultConnection()
            guard let displays = CGSCopyManagedDisplaySpaces(cid) as? [NSDictionary] else { return }
            var allSpaces = [Int]()
            var currentSpace = 0
            for display in displays {
                if let spaces = display["Spaces"] as? [[String: Any]] {
                    for space in spaces {
                        if let id = space["ManagedSpaceID"] as? Int {
                            allSpaces.append(id)
                        }
                    }
                }
                if let currentDict = display["Current Space"] as? [String: Any],
                   let currentID = currentDict["ManagedSpaceID"] as? Int {
                   currentSpace = currentID
                }
            }
            
            guard let idx = allSpaces.firstIndex(of: currentSpace), idx + 1 < allSpaces.count else {
                print("No next space found. Spaces: \(allSpaces), Current: \(currentSpace)")
                exit(0)
            }
            
            let targetSpace = allSpaces[idx + 1]
            let winID = [NSNumber(value: self.window.windowNumber)] as CFArray
            let currentSpaces = [NSNumber(value: currentSpace)] as CFArray
            let targetSpaces = [NSNumber(value: targetSpace)] as CFArray
            
            print("Moving window from \(currentSpace) to \(targetSpace)")
            CGSAddWindowsToSpaces(cid, winID, targetSpaces)
            CGSRemoveWindowsFromSpaces(cid, winID, currentSpaces)
            print("Moved!")
            
            // Exit after 5 seconds to let user verify
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                exit(0)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
