import AppKit
import Combine
import Foundation

@MainActor
class SpaceLabelManager: ObservableObject {
    // Persistence Keys
    private let kActiveFontScale = "kActiveFontScale"
    private let kActivePaddingScale = "kActivePaddingScale"
    private let kPreviewFontScale = "kPreviewFontScale"
    private let kPreviewPaddingScale = "kPreviewPaddingScale"

    private let kShowPreviewLabels = "kShowPreviewLabels"
    private let kShowActiveLabels = "kShowActiveLabels"
    private let kShowOnDesktop = "kShowOnDesktop"
    private let kHideWhenSwitching = "kHideWhenSwitching"
    
    private let kGlobalIsDocked = "kGlobalIsDocked"
    private let kGlobalDockEdge = "kGlobalDockEdge"
    private let kGlobalCenterX = "kGlobalCenterX"
    private let kGlobalCenterY = "kGlobalCenterY"

    // Settings
    @Published var showPreviewLabels: Bool {
        didSet {
            saveSettings()
            updateWindows()
        }
    }
    @Published var hideWhenSwitching: Bool { didSet { saveSettings() } }
    @Published var showActiveLabels: Bool {
        didSet {
            saveSettings()
            updateWindows()
        }
    }
    @Published var hideActiveLabel: Bool
    @Published var showOnDesktop: Bool {
        didSet {
            saveSettings()
            updateWindows()
        }
    }

    @Published var activeFontScale: Double {
        didSet {
            saveSettings()
            updateWindows()
        }
    }
    @Published var activePaddingScale: Double {
        didSet {
            saveSettings()
            updateWindows()
        }
    }
    @Published var previewFontScale: Double {
        didSet {
            saveSettings()
            recalculateUnifiedSize()
        }
    }
    @Published var previewPaddingScale: Double {
        didSet {
            saveSettings()
            recalculateUnifiedSize()
        }
    }

    // Current window state and docking configuration
    @Published var globalIsDocked: Bool
    @Published var globalDockEdge: NSRectEdge
    @Published var globalCenterPoint: NSPoint?

    private var createdWindows: [String: SpaceLabelWindow] = [:]
    private weak var spaceManager: SpaceManager?
    private var cancellables = Set<AnyCancellable>()
    private var delayedRestoreWorkItem: DispatchWorkItem?

    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager

        // Load Settings
        let loadedActiveFont = UserDefaults.standard.double(forKey: kActiveFontScale)
        self.activeFontScale = (loadedActiveFont == 0) ? 1.0 : loadedActiveFont

        let loadedActivePadding = UserDefaults.standard.double(forKey: kActivePaddingScale)
        self.activePaddingScale = (loadedActivePadding == 0) ? 1.0 : loadedActivePadding

        let loadedPreviewFont = UserDefaults.standard.double(forKey: kPreviewFontScale)
        self.previewFontScale = (loadedPreviewFont == 0) ? 1.0 : loadedPreviewFont

        let loadedPreviewPadding = UserDefaults.standard.double(forKey: kPreviewPaddingScale)
        self.previewPaddingScale = (loadedPreviewPadding == 0) ? 1.0 : loadedPreviewPadding

        self.showPreviewLabels =
            UserDefaults.standard.object(forKey: kShowPreviewLabels) == nil
            ? true : UserDefaults.standard.bool(forKey: kShowPreviewLabels)
        self.hideWhenSwitching = UserDefaults.standard.bool(forKey: kHideWhenSwitching)
        self.hideActiveLabel = false
        self.showActiveLabels =
            UserDefaults.standard.object(forKey: kShowActiveLabels) == nil
            ? true : UserDefaults.standard.bool(forKey: kShowActiveLabels)
        self.showOnDesktop = UserDefaults.standard.bool(forKey: kShowOnDesktop)

        // Load Global State
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
        
        // Populate Mission Control with labels after launch.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.seedAllLabels()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        let windows = createdWindows.values
        Task { @MainActor in
            for window in windows { window.orderOut(nil) }
        }
    }

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
        UserDefaults.standard.set(hideWhenSwitching, forKey: kHideWhenSwitching)
        UserDefaults.standard.set(showActiveLabels, forKey: kShowActiveLabels)
        UserDefaults.standard.set(showOnDesktop, forKey: kShowOnDesktop)
    }

    private func updateWindows() {
        let windows = Array(createdWindows.values)
        for window in windows {
            window.refreshAppearance()
        }
    }


    private func setupObservers() {
        guard let spaceManager = spaceManager else { return }

        spaceManager.$currentSpaceUUID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Cancel any pending delayed restore from a previous rapid switch
                // so the old restore doesn't fire in the middle of a new transition.
                self.delayedRestoreWorkItem?.cancel()
                self.delayedRestoreWorkItem = nil

                if self.hideWhenSwitching {
                    let isRecent = Date().timeIntervalSince1970 - SpaceHelper.lastProgrammaticSwitchTime < 1.0
                    if isRecent {
                        DiagnosticEventLog.shared.record(subsystem: "Labels", level: "info", "programmatic switch — hiding labels")
                        self.hideAllPreviewLabels()
                    } else {
                        DiagnosticEventLog.shared.record(subsystem: "Labels", level: "info", "native switch — restoring immediately")
                        self.updateAllWindowModes(forDisplay: self.spaceManager?.currentDisplayID)
                    }
                } else {
                    self.updateAllWindowModes(forDisplay: self.spaceManager?.currentDisplayID)
                }

                let workItem = DispatchWorkItem { [weak self] in
                    // Restore ALL displays — hideAllPreviewLabels hid everything,
                    // and when hideWhenSwitching is on the current display was not
                    // restored either. This unfiltered call is the sole restore point.
                    DiagnosticEventLog.shared.record(subsystem: "Labels", level: "info", "delayed restore firing")
                    self?.updateAllWindowModes()
                }
                self.delayedRestoreWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
            }
            .store(in: &cancellables)

        spaceManager.$spaceNameDict
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recalculateUnifiedSize()
                // When hideWhenSwitching is on, don't restore labels here —
                // the settling delay in the currentSpaceUUID observer is
                // the sole restore point. syncWindowsWithDict still creates
                // and removes windows, it just skips the final updateAllWindowModes.
                self?.syncWindowsWithDict(updateModes: self?.hideWhenSwitching != true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleSpaceSwitchRequested),
            name: NSNotification.Name("SpaceSwitchRequested"), object: nil)

    }

    @objc private func handleSpaceSwitchRequested() {
        // Cancel any pending delayed restore from a previous switch at the START
        // of each new switch (before currentSpaceUUID changes), so the old
        // restore never fires mid-transition of the next switch.
        // This may be called from a background thread (GestureManager's MT callback),
        // so dispatch to main for thread-safe access.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delayedRestoreWorkItem?.cancel()
            self.delayedRestoreWorkItem = nil
            if self.hideWhenSwitching {
                self.hideAllPreviewLabels()
            }
        }
    }

    private func syncWindowsWithDict(updateModes: Bool = true) {
        guard let spaceManager = spaceManager else { return }
        let allSpaces = spaceManager.spaceNameDict

        // Add windows for new spaces.
        for space in allSpaces {
            ensureWindow(for: space.id, name: space.customName, displayID: space.displayID, updateMode: updateModes)
        }

        // Remove windows for spaces that no longer exist.
        cleanupRedundantWindows()

        // Only restore label modes when hideWhenSwitching is off.
        if updateModes {
            updateAllWindowModes()
        }
    }

    // Removes windows for obsolete spaces.
    private func cleanupRedundantWindows() {
        guard let spaceManager = spaceManager else { return }
        let validUUIDs = Set(spaceManager.spaceNameDict.map { $0.id })

        let redundantIDs = createdWindows.keys.filter { !validUUIDs.contains($0) }

        for id in redundantIDs {
            if let window = createdWindows[id] {
                window.close()
            }
            createdWindows.removeValue(forKey: id)
            print("SpaceLabelManager: Removed redundant window for space \(id)")
        }
    }

    private func recalculateUnifiedSize() {
        guard let spaceManager = spaceManager else { return }

        if !Thread.isMainThread {
            Task { @MainActor [weak self] in self?.recalculateUnifiedSize() }
            return
        }

        let pFontScale = previewFontScale.isNaN || previewFontScale <= 0 ? 1.0 : previewFontScale
        let pPadScale =
            previewPaddingScale.isNaN || previewPaddingScale <= 0 ? 1.0 : previewPaddingScale

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

        if finalSize.width.isNaN || finalSize.height.isNaN || finalSize.width < 10
            || finalSize.height < 10
        {
            return
        }

        let windows = Array(createdWindows.values)
        for window in windows {
            window.setPreviewSize(finalSize)
        }
    }

    private func updateAllWindowModes(forDisplay displayID: String? = nil) {
        Task { @MainActor in
            let visibleUUIDs = SpaceHelper.getVisibleSystemSpaceIDs()
            self.applyVisibility(visibleUUIDs, forDisplay: displayID)
        }
    }

    private func applyVisibility(_ visibleUUIDs: Set<String>, forDisplay displayID: String? = nil) {
        if let id = displayID {
             print("SpaceLabelManager: applyVisibility(visibleUUIDs: \(visibleUUIDs)) SCOPED to display: \(id)")
        } else {
             print("SpaceLabelManager: applyVisibility(visibleUUIDs: \(visibleUUIDs)) GLOBAL refresh")
        }
        
        let windowsSnapshot = self.createdWindows

        for (key, window) in windowsSnapshot {
            if let targetDisplay = displayID, window.displayID != targetDisplay {
                continue // Skip windows that are on a different display than the one we are updating
            }
            
            let isVisibleOnAnyScreen = visibleUUIDs.contains(key)
            window.setMode(isCurrentSpace: isVisibleOnAnyScreen)
        }
    }

    private func hidePreviewLabel(for spaceId: String) {
        if let window = createdWindows[spaceId] {
            window.hideImmediately()
        }
    }

    private func hideAllPreviewLabels() {
        DiagnosticEventLog.shared.record(subsystem: "Labels", level: "info", "hideAllPreviewLabels (windows=\(createdWindows.count))")
        for window in createdWindows.values {
            window.hideImmediately()
        }
    }

    func updateLabel(for spaceId: String, name: String, verifySpace: Bool = true) {
        guard spaceId != "FULLSCREEN" else { return }

        if !verifySpace {
            let actualDisplayID = spaceManager?.spaceNameDict.first(where: { $0.id == spaceId })?.displayID ?? spaceManager?.currentDisplayID ?? "Main"
            ensureWindow(for: spaceId, name: name, displayID: actualDisplayID)
            return
        }

        Task { @MainActor in
            // FIX: Increase delay to 0.5s (500ms) to ensure macOS space transition (swipe animation)
            // is fully complete before creating the window. This prevents the window from being
            // created on the 'source' desktop instead of the 'destination' fullscreen app.
            try? await Task.sleep(nanoseconds: 500_000_000)

            guard let state = SpaceHelper.getSystemState() else { return }
            if state.currentUUID == spaceId {
                self.ensureWindow(for: spaceId, name: name, displayID: state.displayID)
            }
        }
    }

    // Asserts that a window exists for the specified space, refreshing if already present.
    private func ensureWindow(for spaceId: String, name: String, displayID: String, updateMode: Bool = true) {
        if let existingWindow = createdWindows[spaceId] {
            if existingWindow.displayID != displayID {
                existingWindow.orderOut(nil)
                createdWindows.removeValue(forKey: spaceId)
            } else {
                // BUG FIX: Even if the window exists and is visible, we MUST update its mode
                // (Active vs Preview) and refresh its appearance. Otherwise, labels can
                // get stuck in Preview mode when returning from fullscreen.
                // During a switch (updateMode: false), skip this — setMode + refreshAppearance
                // both call updateVisibility which can make labels visible prematurely.
                if updateMode {
                    let isCurrent = (spaceId == spaceManager?.currentSpaceUUID)
                    existingWindow.setMode(isCurrentSpace: isCurrent)
                    existingWindow.refreshAppearance()
                }
                return
            }
        }
        createWindow(for: spaceId, name: name, displayID: displayID)
    }

    private func createWindow(for spaceId: String, name: String, displayID: String) {
        guard let spaceManager = spaceManager else { return }

        // Inherit fullscreen status from the space manager.
        let isFullscreen =
            spaceManager.spaceNameDict.first(where: { $0.id == spaceId })?.isFullscreen ?? false

        let window = SpaceLabelWindow(
            spaceId: spaceId, name: name, displayID: displayID, isFullscreen: isFullscreen,
            spaceManager: spaceManager, labelManager: self)
        createdWindows[spaceId] = window
        let isCurrent = (spaceId == spaceManager.currentSpaceUUID)
        window.setMode(isCurrentSpace: isCurrent)
        self.recalculateUnifiedSize()
        window.refreshAppearance()
        window.bindToTargetSpace()
    }

    func reloadAllWindows() {
        removeAllWindows()
        syncWindowsWithDict()
    }

    private func removeAllWindows() {
        let windows = Array(createdWindows.values)
        for window in windows { window.orderOut(nil) }
        createdWindows.removeAll()
    }


    func seedAllLabels() {
        guard showPreviewLabels, let spaceManager = spaceManager else { return }
        print("SpaceLabelManager: Background seeding all labels for Mission Control...")
        let allSpaces = spaceManager.spaceNameDict
        for space in allSpaces {
            ensureWindow(for: space.id, name: space.customName, displayID: space.displayID)
        }
        updateAllWindowModes()
    }

    func toggleActiveLabels() {
        showActiveLabels.toggle()
    }

    func togglePreviewLabels() {
        showPreviewLabels.toggle()
    }

    func toggleActiveLabelVisibility() {
        hideActiveLabel.toggle()
        updateWindows()
    }
}
