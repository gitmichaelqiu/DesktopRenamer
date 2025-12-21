import Foundation
import AppKit

class SpaceLabelManager: ObservableObject {
    private let spacesKey = "com.michaelqiu.desktoprenamer.slw"
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: spacesKey)
            updateLabelsVisibility()
            objectWillChange.send()
        }
    }
    
    private var createdWindows: [String: SpaceLabelWindow] = [:]
    private weak var spaceManager: SpaceManager?
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
        self.isEnabled = UserDefaults.standard.bool(forKey: spacesKey)
    }
    
    deinit {
        removeAllWindows()
    }
    
    func updateLabel(for spaceId: String, name: String, verifySpace: Bool = true) {
        guard isEnabled, spaceId != "FULLSCREEN" else { return }
        
        // If we are not verifying (e.g. forced toggle), just use current manager state
        if !verifySpace {
            let currentDisplayID = spaceManager?.currentDisplayID ?? "Main"
            ensureWindow(for: spaceId, name: name, displayID: currentDisplayID)
            return
        }
        
        // VERIFY: Check live state before creating
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            // FIX: Capture the 'displayID' (4th parameter) from the helper
            SpaceHelper.getRawSpaceUUID { confirmedSpaceId, _, _, liveDisplayID in
                if confirmedSpaceId == spaceId {
                    self.ensureWindow(for: spaceId, name: name, displayID: liveDisplayID)
                }
            }
        }
    }
    
    private func ensureWindow(for spaceId: String, name: String, displayID: String) {
        // 1. Check if window exists
        if let existingWindow = createdWindows[spaceId] {
            // 2. Check if it's on the right screen. If not, destroy it.
            if existingWindow.displayID != displayID {
                print("Label Manager: Space \(spaceId) moved from \(existingWindow.displayID) to \(displayID). Recreating window.")
                existingWindow.orderOut(nil)
                createdWindows.removeValue(forKey: spaceId)
            } else {
                return // Window exists and is correct
            }
        }
        
        // 3. Create new window with the EXPLICIT live displayID
        createWindow(for: spaceId, name: name, displayID: displayID)
    }
    
    private func createWindow(for spaceId: String, name: String, displayID: String) {
        guard let spaceManager = spaceManager else { return }
        
        // We pass the explicit 'displayID' here, ignoring the database
        let window = SpaceLabelWindow(spaceId: spaceId, name: name, displayID: displayID, spaceManager: spaceManager)
        createdWindows[spaceId] = window
        window.orderFront(nil)
    }
    
    private func createWindow(for spaceId: String, name: String) {
            guard let spaceManager = spaceManager else { return }
            
            // FIX: If we are creating the label for the space user is CURRENTLY on,
            // use the live detected DisplayID. Otherwise, fallback to saved data.
            let displayID: String
            if spaceId == spaceManager.currentSpaceUUID {
                displayID = spaceManager.currentDisplayID
            } else {
                displayID = spaceManager.spaceNameDict.first(where: { $0.id == spaceId })?.displayID ?? "Main"
            }
            
            let window = SpaceLabelWindow(spaceId: spaceId, name: name, displayID: displayID, spaceManager: spaceManager)
            createdWindows[spaceId] = window
            window.orderFront(nil)
        }
    
    private func removeAllWindows() {
        for (_, window) in createdWindows {
            window.orderOut(nil)
        }
        createdWindows.removeAll()
    }
    
    private func updateLabelsVisibility() {
        if !isEnabled {
            removeAllWindows()
        } else {
            if let spaceId = spaceManager?.currentSpaceUUID,
               let name = spaceManager?.getSpaceName(spaceId) {
                updateLabel(for: spaceId, name: name, verifySpace: false)
            }
        }
    }
    
    func toggleEnabled() {
        isEnabled.toggle()
        if isEnabled {
            let spaceId = self.spaceManager?.currentSpaceUUID
            let name = self.spaceManager?.getSpaceName(spaceId ?? "")
            self.updateLabel(for: spaceId ?? "", name: name ?? "", verifySpace: false)
        }
    }
}
