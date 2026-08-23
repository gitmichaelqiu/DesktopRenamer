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

    var createdWindows: [String: SpaceLabelWindow] = [:]
    weak var spaceManager: SpaceManager?
    var cancellables = Set<AnyCancellable>()
    var delayedRestoreWorkItem: DispatchWorkItem?
    var delayedRearrangementRestoreWorkItem: DispatchWorkItem?
    var seedTask: Task<Void, Never>?
    var labelUpdateTasks: [String: Task<Void, Never>] = [:]

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
        seedTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                self?.seedAllLabels()
            } catch {
                // Cancellation is expected when the app terminates before seeding.
            }
        }
    }

    deinit {
        seedTask?.cancel()
        delayedRestoreWorkItem?.cancel()
        delayedRearrangementRestoreWorkItem?.cancel()
        labelUpdateTasks.values.forEach { $0.cancel() }
        NotificationCenter.default.removeObserver(self)
        let windows = createdWindows.values
        for window in windows { window.orderOut(nil) }
    }
}
