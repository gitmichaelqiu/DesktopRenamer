import Foundation
import AppKit

class SpaceLabelManager: ObservableObject {
    private let spacesKey = "com.gitmichaelqiu.desktoprenamer.slw"
    
    @Published private(set) var isEnabled: Bool {
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
        DispatchQueue.main.async {
            if self.isEnabled {
                if self.isEnabled, spaceId != "FULLSCREEN", self.createdWindows[spaceId] == nil {
                    // Create new window for this space
                    self.createWindow(for: spaceId, name: name)
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
