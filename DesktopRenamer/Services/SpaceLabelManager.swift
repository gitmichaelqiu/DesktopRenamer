import Foundation
import AppKit

class SpaceLabelManager: ObservableObject {
    private let spacesKey = "com.gitmichaelqiu.desktoprenamer.slw"
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: spacesKey)
            updateLabelsVisibility()
        }
    }
    
    private var currentWindow: SpaceLabelWindow?
    private var createdWindows: [String: SpaceLabelWindow] = [:]
    private weak var spaceManager: SpaceManager?
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
        self.isEnabled = UserDefaults.standard.bool(forKey: spacesKey)
    }
    
    deinit {
        removeAllWindows()
    }
    
    func toggleEnabled() {
        isEnabled.toggle()
        
        if isEnabled {
            let spaceId = self.spaceManager?.currentSpaceUUID
            let name = self.spaceManager?.getSpaceName(spaceId ?? "")
            self.updateLabel(for: spaceId ?? "", name: name ?? "")
        }
    }
    
    func updateLabel(for spaceId: String, name: String) {
        guard isEnabled, spaceId != "FULLSCREEN" else { return }
        if createdWindows[spaceId] != nil { return }
        
        // Double check before creating
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            // Get UUID again
            SpaceHelper.getSpaceUUID { confirmedSpaceId in
                // Create window only if two are identical
                if confirmedSpaceId == spaceId {
                    // Make sure not creating a duplicated window
                    if self.createdWindows[spaceId] == nil {
                        self.createWindow(for: spaceId, name: name)
                    }
                }
            }
        }
    }
    
    private func createWindow(for spaceId: String, name: String) {
        guard let spaceManager = spaceManager else { return }
        let window = SpaceLabelWindow(spaceId: spaceId, name: name, spaceManager: spaceManager)
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
}
