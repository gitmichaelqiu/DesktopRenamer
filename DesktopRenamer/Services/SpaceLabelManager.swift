import Foundation
import AppKit
import Combine

@MainActor
class SpaceLabelManager: ObservableObject {
    private let spacesKey = "com.michaelqiu.desktoprenamer.slw"
    
    // Persistence Keys (Settings)
    private let kActiveFontScale = "kActiveFontScale"
    private let kActivePaddingScale = "kActivePaddingScale"
    private let kPreviewFontScale = "kPreviewFontScale"
    private let kPreviewPaddingScale = "kPreviewPaddingScale"
    
    private let kShowPreviewLabels = "kShowPreviewLabels"
    private let kShowActiveLabels = "kShowActiveLabels"
    private let kShowOnDesktop = "kShowOnDesktop"
    
    // Persistence Keys (Window State Synchronization)
    private let kGlobalIsDocked = "kGlobalIsDocked"
    private let kGlobalDockEdge = "kGlobalDockEdge"
    private let kGlobalCenterX = "kGlobalCenterX"
    private let kGlobalCenterY = "kGlobalCenterY"
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: spacesKey)
            updateLabelsVisibility()
        }
    }
    
    // Visibility Toggles
    @Published var showPreviewLabels: Bool { didSet { saveSettings(); updateWindows() } }
    @Published var showActiveLabels: Bool { didSet { saveSettings(); updateWindows() } }
    @Published var showOnDesktop: Bool { didSet { saveSettings(); updateWindows() } }
    
    // Scales
    @Published var activeFontScale: Double { didSet { saveSettings(); updateWindows() } }
    @Published var activePaddingScale: Double { didSet { saveSettings(); updateWindows() } }
    @Published var previewFontScale: Double { didSet { saveSettings(); recalculateUnifiedSize() } }
    @Published var previewPaddingScale: Double { didSet { saveSettings(); recalculateUnifiedSize() } }
    
    // MARK: - Global Window State (Synced)
    @Published var globalIsDocked: Bool
    @Published var globalDockEdge: NSRectEdge
    @Published var globalCenterPoint: NSPoint?
    
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
        self.showOnDesktop = UserDefaults.standard.bool(forKey: kShowOnDesktop)
        
        // MARK: - Load Global Sync State
        if UserDefaults.standard.object(forKey: kGlobalIsDocked) != nil {
            self.globalIsDocked = UserDefaults.standard.bool(forKey: kGlobalIsDocked)
        } else {
            self.globalIsDocked = true
        }
        
        if UserDefaults.standard.object(forKey: kGlobalDockEdge) != nil {
            let edgeRaw = UserDefaults.standard.integer(forKey: kGlobalDockEdge)
            self.globalDockEdge = NSRectEdge(rawValue: UInt(edgeRaw)) ?? .maxX
        } else {
            self.globalDockEdge = .maxX
        }
        
        if UserDefaults.standard.object(forKey: kGlobalCenterX) != nil {
            let cx = UserDefaults.standard.double(forKey: kGlobalCenterX)
            let cy = UserDefaults.standard.double(forKey: kGlobalCenterY)
            self.globalCenterPoint = NSPoint(x: cx, y: cy)
        } else {
            self.globalCenterPoint = nil
        }
        
        setupObservers()
    }
    
    deinit {
        let windows = createdWindows.values
        Task { @MainActor in
            for window in windows { window.orderOut(nil) }
        }
    }
    
    // MARK: - State Synchronization
    
    func updateGlobalState(isDocked: Bool, edge: NSRectEdge, center: NSPoint) {
        self.globalIsDocked = isDocked
        self.globalDockEdge = edge
        self.globalCenterPoint = center
        
        UserDefaults.standard.set(isDocked, forKey: kGlobalIsDocked)
        UserDefaults.standard.set(Int(edge.rawValue), forKey: kGlobalDockEdge)
        UserDefaults.standard.set(center.x, forKey: kGlobalCenterX)
        UserDefaults.standard.set(center.y, forKey: kGlobalCenterY)
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
        guard !createdWindows.isEmpty else { return }
        let keys = Array(createdWindows.keys)
        for key in keys {
            createdWindows[key]?.refreshAppearance()
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
        
        // Ensure this runs on main thread
        if !Thread.isMainThread {
            Task { @MainActor [weak self] in self?.recalculateUnifiedSize() }
            return
        }
        
        let pFontScale = previewFontScale.isNaN || previewFontScale <= 0 ? 1.0 : previewFontScale
        let pPadScale = previewPaddingScale.isNaN || previewPaddingScale <= 0 ? 1.0 : previewPaddingScale
        
        let baseFontSize: CGFloat = 180
        let scaledFontSize = baseFontSize * CGFloat(pFontScale)
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
        let paddingH = basePadH * CGFloat(pPadScale)
        let paddingV = basePadV * CGFloat(pPadScale)
        
        var finalSize = NSSize(width: maxWidth + paddingH, height: maxHeight + paddingV)
        
        if let screen = NSScreen.screens.first {
            finalSize.width = min(finalSize.width, screen.frame.width * 0.95)
            finalSize.height = min(finalSize.height, screen.frame.height * 0.9)
        }
        
        if finalSize.width.isNaN || finalSize.height.isNaN || finalSize.width.isInfinite || finalSize.height.isInfinite || finalSize.width < 10 || finalSize.height < 10 {
            return
        }
        
        if !createdWindows.isEmpty {
            let keys = Array(createdWindows.keys)
            for key in keys {
                createdWindows[key]?.setPreviewSize(finalSize)
            }
        }
    }
    
    private func updateAllWindowModes() {
        let detectionMethod = spaceManager?.detectionMethod ?? .automatic
        
        if detectionMethod == .automatic {
            // Use CGS based visibility (Task ensures MainActor isolation)
            Task { @MainActor in
                let visibleUUIDs = SpaceHelper.getVisibleSystemSpaceIDs()
                self.applyVisibility(visibleUUIDs)
            }
        } else {
            // Use Legacy visibility (Wait for callback, then hop back to Actor)
            SpaceHelper.getVisibleSpaceUUIDs { [weak self] visibleUUIDs in
                // CRITICAL FIX: Use Task { @MainActor } to guarantee thread safety for dictionary access
                Task { @MainActor [weak self] in
                    self?.applyVisibility(visibleUUIDs)
                }
            }
        }
    }
    
    private func applyVisibility(_ visibleUUIDs: Set<String>) {
        guard self.isEnabled, !self.createdWindows.isEmpty else { return }
        
        // Taking a snapshot of keys is good, but strictly ensuring we are on MainActor
        // (as guaranteed by the Task wrapper in updateAllWindowModes) prevents the crash.
        let keys = Array(self.createdWindows.keys)
        
        for key in keys {
            // This dictionary lookup is safe only if we are strictly serial on the MainActor
            guard let window = self.createdWindows[key] else { continue }
            let isVisibleOnAnyScreen = visibleUUIDs.contains(key)
            window.setMode(isCurrentSpace: isVisibleOnAnyScreen)
        }
    }
    
    func updateLabel(for spaceId: String, name: String, verifySpace: Bool = true) {
        guard isEnabled, spaceId != "FULLSCREEN" else { return }
        if !verifySpace {
            let currentDisplayID = spaceManager?.currentDisplayID ?? "Main"
            ensureWindow(for: spaceId, name: name, displayID: currentDisplayID)
            return
        }
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000) // 0.02s
            
            if spaceManager?.detectionMethod == .automatic {
                guard let state = SpaceHelper.getSystemState() else { return }
                if state.currentUUID == spaceId {
                    self.ensureWindow(for: spaceId, name: name, displayID: state.displayID)
                }
            } else {
                SpaceHelper.getRawSpaceUUID { [weak self] confirmedSpaceId, _, _, liveDisplayID in
                    Task { @MainActor [weak self] in
                        if confirmedSpaceId == spaceId {
                            self?.ensureWindow(for: spaceId, name: name, displayID: liveDisplayID)
                        }
                    }
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
        if !createdWindows.isEmpty {
            let values = Array(createdWindows.values)
            for window in values { window.orderOut(nil) }
            createdWindows.removeAll()
        }
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
