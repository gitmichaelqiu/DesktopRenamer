import AppKit
import Combine
import Foundation

@MainActor
class SpaceLabelManager: ObservableObject {
    // Persistence Keys
    let kActiveFontScale = "kActiveFontScale"
    let kActivePaddingScale = "kActivePaddingScale"
    let kPreviewFontScale = "kPreviewFontScale"
    let kPreviewPaddingScale = "kPreviewPaddingScale"

    let kShowPreviewLabels = "kShowPreviewLabels"
    let kShowActiveLabels = "kShowActiveLabels"
    let kDisablePreviewLiquidGlass = "kDisablePreviewLiquidGlass"
    let kDisableActiveLiquidGlass = "kDisableActiveLiquidGlass"
    let kShowOnDesktop = "kShowOnDesktop"
    let kHideWhenSwitching = "kHideWhenSwitching"
    
    let kGlobalIsDocked = "kGlobalIsDocked"
    let kGlobalDockEdge = "kGlobalDockEdge"
    let kGlobalCenterX = "kGlobalCenterX"
    let kGlobalCenterY = "kGlobalCenterY"

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
    @Published var disablePreviewLiquidGlass: Bool {
        didSet {
            saveSettings()
            updateWindows()
        }
    }
    @Published var disableActiveLiquidGlass: Bool {
        didSet {
            saveSettings()
            updateWindows()
        }
    }
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

    // Preview and active labels use independent windows so a switch never
    // animates one window between the two layouts.
    var createdWindows: [String: SpaceLabelWindow] = [:]
    var activeWindows: [String: SpaceLabelWindow] = [:]
    weak var spaceManager: SpaceManager?
    var cancellables = Set<AnyCancellable>()
    var delayedRestoreWorkItem: DispatchWorkItem?
    var previewTransitionRestoreWorkItem: DispatchWorkItem?
    var activeSyncWorkItems: [DispatchWorkItem] = []
    var reloadWorkItem: DispatchWorkItem?
    var workspaceSpaceChangeObserver: NSObjectProtocol?
    var reloadGeneration = 0
    var startupSpaceRestoreWorkItem: DispatchWorkItem?
    var knownSpaceIDs: Set<String> = []
    var knownFullscreenSpaceIDs: Set<String> = []
    var previewLabelsSuppressedUntil: Date?
    let startupDisplayID: String?
    let startupSpaceID: String?

    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
        let startupState = SpaceHelper.getSystemState()
        self.startupDisplayID = startupState?.displayID
        self.startupSpaceID = startupState?.currentUUID
        self.knownSpaceIDs = Set(spaceManager.spaceNameDict.map(\.id))
        self.knownFullscreenSpaceIDs = Set(spaceManager.spaceNameDict.filter(\.isFullscreen).map(\.id))

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
        self.showActiveLabels =
            UserDefaults.standard.object(forKey: kShowActiveLabels) == nil
            ? true : UserDefaults.standard.bool(forKey: kShowActiveLabels)
        self.disablePreviewLiquidGlass = UserDefaults.standard.bool(forKey: kDisablePreviewLiquidGlass)
        self.disableActiveLiquidGlass = UserDefaults.standard.bool(forKey: kDisableActiveLiquidGlass)
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
        if let observer = workspaceSpaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        delayedRestoreWorkItem?.cancel()
        previewTransitionRestoreWorkItem?.cancel()
        startupSpaceRestoreWorkItem?.cancel()
        reloadWorkItem?.cancel()
        let windows = Array(createdWindows.values) + Array(activeWindows.values)
        Task { @MainActor in
            for window in windows {
                window.pendingVisibilityTask?.cancel()
                window.close()
            }
        }
    }
}
