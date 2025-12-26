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
    
    // Visibility Keys
    private let kShowPreviewLabels = "kShowPreviewLabels"
    private let kShowActiveLabels = "kShowActiveLabels"
    private let kShowOnDesktop = "kShowOnDesktop" // NEW
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: spacesKey)
            updateLabelsVisibility()
        }
    }
    
    // Visibility Toggles
    @Published var showPreviewLabels: Bool { didSet { saveSettings(); updateWindows() } }
    @Published var showActiveLabels: Bool { didSet { saveSettings(); updateWindows() } }
    
    // NEW: Active Label moves from "Hidden Corner" to "Visible Floating Widget"
    @Published var showOnDesktop: Bool {
        didSet {
            saveSettings()
            updateWindows()
        }
    }
    
    // Scales
    @Published var activeFontScale: Double { didSet { saveSettings(); updateWindows() } }
    @Published var activePaddingScale: Double { didSet { saveSettings(); updateWindows() } }
    @Published var previewFontScale: Double { didSet { saveSettings(); recalculateUnifiedSize() } }
    @Published var previewPaddingScale: Double { didSet { saveSettings(); recalculateUnifiedSize() } }
    
    private var createdWindows: [String: SpaceLabelWindow] = [:]
    private weak var spaceManager: SpaceManager?
    private var cancellables = Set<AnyCancellable>()
    
    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
        
        UserDefaults.standard.register(defaults: [spacesKey: true])
        self.isEnabled = UserDefaults.standard.bool(forKey: spacesKey)
        
        // Load Scales
        let loadedActiveFont = UserDefaults.standard.double(forKey: kActiveFontScale)
        let loadedActivePadding = UserDefaults.standard.double(forKey: kActivePaddingScale)
        let loadedPreviewFont = UserDefaults.standard.double(forKey: kPreviewFontScale)
        let loadedPreviewPadding = UserDefaults.standard.double(forKey: kPreviewPaddingScale)
        
        self.activeFontScale = (loadedActiveFont == 0) ? 1.0 : loadedActiveFont
        self.activePaddingScale = (loadedActivePadding == 0) ? 1.0 : loadedActivePadding
        self.previewFontScale = (loadedPreviewFont == 0) ? 1.0 : loadedPreviewFont
        self.previewPaddingScale = (loadedPreviewPadding == 0) ? 1.0 : loadedPreviewPadding
        
        // Load Visibility
        self.showPreviewLabels = UserDefaults.standard.object(forKey: kShowPreviewLabels) == nil ? true : UserDefaults.standard.bool(forKey: kShowPreviewLabels)
        self.showActiveLabels = UserDefaults.standard.object(forKey: kShowActiveLabels) == nil ? true : UserDefaults.standard.bool(forKey: kShowActiveLabels)
        self.showOnDesktop = UserDefaults.standard.bool(forKey: kShowOnDesktop) // Default false
        
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
        
        UserDefaults.standard.set(showPreviewLabels, forKey: kShowPreviewLabels)
        UserDefaults.standard.set(showActiveLabels, forKey: kShowActiveLabels)
        UserDefaults.standard.set(showOnDesktop, forKey: kShowOnDesktop)
    }
    
    private func updateWindows() {
        for window in createdWindows.values {
            window.refreshAppearance()
        }
    }
    
    private func setupObservers() {
        guard let spaceManager = spaceManager else { return }
        
        spaceManager.$currentSpaceUUID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateAllWindowModes() }
            .store(in: &cancellables)
            
        spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recalculateUnifiedSize() }
            .store(in: &cancellables)
    }
    
    private func recalculateUnifiedSize() {
        guard let spaceManager = spaceManager else { return }
        
        // Uses Preview Settings for the "Max Size" reference
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
        
        let basePadH: CGFloat = 200
        let basePadV: CGFloat = 150
        let paddingH = basePadH * CGFloat(previewPaddingScale)
        let paddingV = basePadV * CGFloat(previewPaddingScale)
        
        var finalSize = NSSize(width: maxWidth + paddingH, height: maxHeight + paddingV)
        
        if let screen = NSScreen.main {
            finalSize.width = min(finalSize.width, screen.frame.width * 0.95)
            finalSize.height = min(finalSize.height, screen.frame.height * 0.9)
        }
        
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
        let window = SpaceLabelWindow(spaceId: spaceId, name: name, displayID: displayID, spaceManager: spaceManager, labelManager: self)
        createdWindows[spaceId] = window
        let isCurrent = (spaceId == spaceManager.currentSpaceUUID)
        window.setMode(isCurrentSpace: isCurrent)
        self.recalculateUnifiedSize()
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
    }
}
