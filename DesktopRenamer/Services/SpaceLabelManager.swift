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
    private var cancellables = Set<AnyCancellable>()
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
        self.isEnabled = UserDefaults.standard.bool(forKey: spacesKey)
        setupObservers()
    }
    
    deinit {
        removeAllWindows()
        cancellables.removeAll()
    }
    
    private func setupObservers() {
        guard let spaceManager = spaceManager else { return }
        
        // 1. Monitor Current Space (For Mode Switching)
        spaceManager.$currentSpaceUUID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAllWindowModes()
            }
            .store(in: &cancellables)
            
        // 2. Monitor Space Names (For Size Calculation)
        spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculateUnifiedSize()
            }
            .store(in: &cancellables)
    }
    
    // NEW: Calculate the biggest text dimensions
    private func recalculateUnifiedSize() {
        guard let spaceManager = spaceManager else { return }
        
        let referenceFont = SpaceLabelWindow.referenceFont
        var maxWidth: CGFloat = 600 // Minimum width baseline
        var maxHeight: CGFloat = 300 // Minimum height baseline
        
        // 1. Find the largest text dimensions
        for space in spaceManager.spaceNameDict {
            let name = spaceManager.getSpaceName(space.id)
            let size = name.size(withAttributes: [.font: referenceFont])
            
            if size.width > maxWidth { maxWidth = size.width }
            if size.height > maxHeight { maxHeight = size.height }
        }
        
        // 2. Add padding
        let paddingH: CGFloat = 200
        let paddingV: CGFloat = 150
        var finalSize = NSSize(width: maxWidth + paddingH, height: maxHeight + paddingV)
        
        // 3. Cap at screen size (safety check)
        if let screen = NSScreen.main {
            let maxW = screen.frame.width * 0.9
            let maxH = screen.frame.height * 0.8
            finalSize.width = min(finalSize.width, maxW)
            finalSize.height = min(finalSize.height, maxH)
        }
        
        // 4. Update ALL windows with this size
        for window in createdWindows.values {
            window.setPreviewSize(finalSize)
        }
    }
    
    private func updateAllWindowModes() {
        SpaceHelper.getVisibleSpaceUUIDs { [weak self] visibleUUIDs in
            guard let self = self, self.isEnabled else { return }
            
            for (spaceId, window) in self.createdWindows {
                let isVisibleOnAnyScreen = visibleUUIDs.contains(spaceId)
                window.setMode(isCurrentSpace: isVisibleOnAnyScreen)
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
            } else if existingWindow.displayID != displayID {
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
        
        // Initialize with correct mode
        let isCurrent = (spaceId == spaceManager.currentSpaceUUID)
        window.setMode(isCurrentSpace: isCurrent)
        
        // Important: Ensure the new window gets the current unified size immediately
        // (recalculateUnifiedSize triggers updates, but we can also trigger one here if needed)
        // Ideally, we run recalculate once after creation.
        self.recalculateUnifiedSize()
        
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
            if let spaceId = spaceManager?.currentSpaceUUID,
               let name = spaceManager?.getSpaceName(spaceId) {
                updateLabel(for: spaceId, name: name, verifySpace: false)
            }
        }
    }
}
