import Foundation
import AppKit
import Combine

class SpaceLabelManager: ObservableObject {
    private let spacesKey = "com.michaelqiu.desktoprenamer.slw"
    
    // Persistence Keys
    private let kActiveFontScale = "kActiveFontScale"
    private let kActivePaddingScale = "kActivePaddingScale"
    private let kPreviewFontScale = "kPreviewFontScale"
    private let kPreviewPaddingScale = "kPreviewPaddingScale"
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: spacesKey)
            updateLabelsVisibility()
        }
    }
    
    // NEW: Customizable Scales (Default 1.0)
    @Published var activeFontScale: Double { didSet { saveSettings(); updateWindows() } }
    @Published var activePaddingScale: Double { didSet { saveSettings(); updateWindows() } }
    @Published var previewFontScale: Double { didSet { saveSettings(); recalculateUnifiedSize() } }
    @Published var previewPaddingScale: Double { didSet { saveSettings(); recalculateUnifiedSize() } }
    
    private var createdWindows: [String: SpaceLabelWindow] = [:]
    private weak var spaceManager: SpaceManager?
    private var cancellables = Set<AnyCancellable>()
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
        // Load isEnabled directly
        self.isEnabled = UserDefaults.standard.bool(forKey: spacesKey)
        
        // 1. Load values into local variables first
        let loadedActiveFont = UserDefaults.standard.double(forKey: kActiveFontScale)
        let loadedActivePadding = UserDefaults.standard.double(forKey: kActivePaddingScale)
        let loadedPreviewFont = UserDefaults.standard.double(forKey: kPreviewFontScale)
        let loadedPreviewPadding = UserDefaults.standard.double(forKey: kPreviewPaddingScale)
        
        // 2. Validate/Default them locally
        // (If key doesn't exist, double returns 0.0, so we default to 1.0)
        let finalActiveFont = (loadedActiveFont == 0) ? 1.0 : loadedActiveFont
        let finalActivePadding = (loadedActivePadding == 0) ? 1.0 : loadedActivePadding
        let finalPreviewFont = (loadedPreviewFont == 0) ? 1.0 : loadedPreviewFont
        let finalPreviewPadding = (loadedPreviewPadding == 0) ? 1.0 : loadedPreviewPadding
        
        // 3. Assign to properties (Initializing them)
        self.activeFontScale = finalActiveFont
        self.activePaddingScale = finalActivePadding
        self.previewFontScale = finalPreviewFont
        self.previewPaddingScale = finalPreviewPadding
        
        // 4. Now 'self' is fully initialized, we can call instance methods
        setupObservers()
    }
    
    deinit {
        removeAllWindows()
        cancellables.removeAll()
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(activeFontScale, forKey: kActiveFontScale)
        UserDefaults.standard.set(activePaddingScale, forKey: kActivePaddingScale)
        UserDefaults.standard.set(previewFontScale, forKey: kPreviewFontScale)
        UserDefaults.standard.set(previewPaddingScale, forKey: kPreviewPaddingScale)
    }
    
    private func updateWindows() {
        // Trigger live updates for active windows
        for window in createdWindows.values {
            window.refreshAppearance()
        }
    }
    
    private func setupObservers() {
        guard let spaceManager = spaceManager else { return }
        
        // 1. Monitor Current Space (Mode Switching)
        spaceManager.$currentSpaceUUID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateAllWindowModes() }
            .store(in: &cancellables)
            
        // 2. Monitor Space Names (Size Calculation)
        spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recalculateUnifiedSize() }
            .store(in: &cancellables)
    }
    
    // UPDATED: Calculate unified size using sliders
    private func recalculateUnifiedSize() {
        guard let spaceManager = spaceManager else { return }
        
        // Apply Preview Font Scale
        let baseFontSize: CGFloat = 180
        let scaledFontSize = baseFontSize * CGFloat(previewFontScale)
        let referenceFont = NSFont.systemFont(ofSize: scaledFontSize, weight: .bold)
        
        var maxWidth: CGFloat = 600
        var maxHeight: CGFloat = 300
        
        for space in spaceManager.spaceNameDict {
            let name = spaceManager.getSpaceName(space.id)
            let size = name.size(withAttributes: [.font: referenceFont])
            if size.width > maxWidth { maxWidth = size.width }
            if size.height > maxHeight { maxHeight = size.height }
        }
        
        // Apply Preview Padding Scale
        let basePadH: CGFloat = 200
        let basePadV: CGFloat = 150
        let paddingH = basePadH * CGFloat(previewPaddingScale)
        let paddingV = basePadV * CGFloat(previewPaddingScale)
        
        var finalSize = NSSize(width: maxWidth + paddingH, height: maxHeight + paddingV)
        
        // Cap at screen size
        if let screen = NSScreen.main {
            let maxW = screen.frame.width * 0.95
            let maxH = screen.frame.height * 0.9
            finalSize.width = min(finalSize.width, maxW)
            finalSize.height = min(finalSize.height, maxH)
        }
        
        for window in createdWindows.values {
            window.setPreviewSize(finalSize)
        }
    }
    
    // ... (Keep updateAllWindowModes, updateLabel, ensureWindow, createWindow, removeAllWindows from previous version) ...
    // Note: ensureWindow and createWindow need to access 'self' to get scales,
    // which they do because SpaceLabelWindow now holds a reference to Manager or we pass values.
    // Ideally, pass the manager reference to window is enough.
    
    private func updateAllWindowModes() {
        SpaceHelper.getVisibleSpaceUUIDs { [weak self] visibleUUIDs in
            guard let self = self, self.isEnabled else { return }
            for (spaceId, window) in self.createdWindows {
                let isVisibleOnAnyScreen = visibleUUIDs.contains(spaceId)
                window.setMode(isCurrentSpace: isVisibleOnAnyScreen)
            }
        }
    }
    
    // Re-paste standard methods for completeness if needed, or assume they exist
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
        // Pass 'self' (LabelManager) to Window so it can read settings
        let window = SpaceLabelWindow(spaceId: spaceId, name: name, displayID: displayID, spaceManager: spaceManager, labelManager: self)
        createdWindows[spaceId] = window
        let isCurrent = (spaceId == spaceManager.currentSpaceUUID)
        window.setMode(isCurrentSpace: isCurrent)
        self.recalculateUnifiedSize() // Ensure it gets current unified size
        window.orderFront(nil)
    }
    
    private func removeAllWindows() {
        for (_, window) in createdWindows { window.orderOut(nil) }
        createdWindows.removeAll()
    }
    
    private func updateLabelsVisibility() {
        if !isEnabled { removeAllWindows() } else {
            if let spaceId = spaceManager?.currentSpaceUUID, let name = spaceManager?.getSpaceName(spaceId) {
                updateLabel(for: spaceId, name: name, verifySpace: false)
            }
        }
    }
    
    func toggleEnabled() {
        isEnabled.toggle()
        // ... (standard toggle logic)
    }
}
