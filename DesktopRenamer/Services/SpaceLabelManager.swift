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
    
    private var currentWindow: DesktopLabelWindow?
    private var createdWindows: [String: DesktopLabelWindow] = [:]
    private weak var spaceManager: SpaceManager?
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
        self.isEnabled = UserDefaults.standard.bool(forKey: spacesKey)

        // Monitor space changes
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            if self.isEnabled {
                self.handleSpaceChange()
            }
        }
        
        // Initial setup
        if isEnabled {
            handleSpaceChange()
        }
        
        // Refresh SLW
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.toggleEnabled()
            self.toggleEnabled()
        }
    }
    
    deinit {
        removeAllWindows()
    }
    
    func toggleEnabled() {
        isEnabled.toggle()
    }
    
    func updateLabel(for spaceId: String, name: String) {
        DispatchQueue.main.async {
            if self.isEnabled {
                if let window = self.createdWindows[spaceId] {
                    // Update existing window
                    window.updateName(name)
                } else if spaceId != "FULLSCREEN" {
                    // Create new window for this space
                    self.createWindow(for: spaceId, name: name)
                }
            }
        }
    }
    
    private func createWindow(for spaceId: String, name: String) {
        guard let spaceManager = spaceManager else { return }
        let window = DesktopLabelWindow(spaceId: spaceId, name: name, spaceManager: spaceManager)
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
        if isEnabled {
            handleSpaceChange()
        } else {
            removeAllWindows()
        }
    }
    
    @objc private func handleSpaceChange() {
        guard let spaceManager = spaceManager else { return }
        let currentSpace = SpaceHelper.getSpaceUUID()
        let name = spaceManager.getSpaceName(currentSpace)
        updateLabel(for: currentSpace, name: name)
    }
}
