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
        if createdWindows[spaceId] != nil { return }
        
        if verifySpace {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                // Confirm existence before creating
                SpaceHelper.getRawSpaceUUID { confirmedSpaceId, _, _, _ in
                    if confirmedSpaceId == spaceId {
                        if self.createdWindows[spaceId] == nil {
                            self.createWindow(for: spaceId, name: name)
                        }
                    }
                }
            }
        } else {
            self.createWindow(for: spaceId, name: name)
        }
    }
    
    private func createWindow(for spaceId: String, name: String) {
        guard let spaceManager = spaceManager else { return }
        
        // Find the Display ID for this space
        let displayID = spaceManager.spaceNameDict.first(where: { $0.id == spaceId })?.displayID ?? "Main"
        
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
