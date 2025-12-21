import Foundation
import AppKit
import Combine

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
    private var cancellables = Set<AnyCancellable>() // Added Cancellables storage
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
        self.isEnabled = UserDefaults.standard.bool(forKey: spacesKey)
        setupObservers() // Start listening immediately
    }
    
    deinit {
        removeAllWindows()
        cancellables.removeAll()
    }
    
    private func setupObservers() {
        guard let spaceManager = spaceManager else { return }
        
        // NEW: Listen to Space Switches
        spaceManager.$currentSpaceUUID
            .dropFirst() // Skip initial load
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentSpaceId in
                guard let self = self, self.isEnabled else { return }
                self.updateAllWindowModes(currentSpaceId: currentSpaceId)
            }
            .store(in: &cancellables)
    }
    
    private func updateAllWindowModes(currentSpaceId: String) {
        for (spaceId, window) in createdWindows {
            if spaceId == currentSpaceId {
                // CURRENT SPACE: Shrink & Hide (So user can work)
                window.setMode(isCurrentSpace: true)
            } else {
                // OTHER SPACES: Expand & Show (For Mission Control Preview)
                window.setMode(isCurrentSpace: false)
            }
        }
    }
    
    func updateLabel(for spaceId: String, name: String, verifySpace: Bool = true) {
        guard isEnabled, spaceId != "FULLSCREEN" else { return }
        
        if !verifySpace {
            let currentDisplayID = spaceManager?.currentDisplayID ?? "Main"
            ensureWindow(for: spaceId, name: name, displayID: currentDisplayID)
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            SpaceHelper.getRawSpaceUUID { confirmedSpaceId, _, _, liveDisplayID in
                if confirmedSpaceId == spaceId {
                    self.ensureWindow(for: spaceId, name: name, displayID: liveDisplayID)
                }
            }
        }
    }
    
    private func ensureWindow(for spaceId: String, name: String, displayID: String) {
        if let existingWindow = createdWindows[spaceId] {
            if !existingWindow.isVisible {
                createdWindows.removeValue(forKey: spaceId)
            }
            else if existingWindow.displayID != displayID {
                print("Label Manager: Space \(spaceId) moved. Recreating window.")
                existingWindow.orderOut(nil)
                createdWindows.removeValue(forKey: spaceId)
            } else {
                return
            }
        }
        createWindow(for: spaceId, name: name, displayID: displayID)
    }
    
    private func createWindow(for spaceId: String, name: String, displayID: String) {
        guard let spaceManager = spaceManager else { return }
        
        let window = SpaceLabelWindow(spaceId: spaceId, name: name, displayID: displayID, spaceManager: spaceManager)
        createdWindows[spaceId] = window
        
        // Initialize Mode:
        // If this is the active space, hide it. If it's a background space, show preview.
        let isCurrent = (spaceId == spaceManager.currentSpaceUUID)
        window.setMode(isCurrentSpace: isCurrent)
        
        window.orderFront(nil)
    }
    
    // Legacy override support (unused now but kept for safety)
    private func createWindow(for spaceId: String, name: String) {
        guard let spaceManager = spaceManager else { return }
        let displayID = (spaceId == spaceManager.currentSpaceUUID) ? spaceManager.currentDisplayID : "Main"
        createWindow(for: spaceId, name: name, displayID: displayID)
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
            // Restore labels for visible spaces
            if let spaceId = spaceManager?.currentSpaceUUID,
               let name = spaceManager?.getSpaceName(spaceId) {
                updateLabel(for: spaceId, name: name, verifySpace: false)
            }
        }
    }
    
    func toggleEnabled() {
        isEnabled.toggle()
        if isEnabled {
            if let spaceId = spaceManager?.currentSpaceUUID,
               let name = spaceManager?.getSpaceName(spaceId) {
                updateLabel(for: spaceId, name: name, verifySpace: false)
            }
        }
    }
}
