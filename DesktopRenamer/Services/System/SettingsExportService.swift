import AppKit
import Foundation

struct SettingsExportDocument: Codable {
    let format: String
    let version: Int
    let exportedAt: Date
    let settings: ExportedSettings

    init(settings: ExportedSettings, exportedAt: Date = Date()) {
        self.format = "dev.mqiu.desktoprenamer.settings"
        self.version = 1
        self.exportedAt = exportedAt
        self.settings = settings
    }
}

/// An explicit allowlist of portable preferences; never serialize UserDefaults wholesale.
@MainActor
struct ExportedSettings: Codable {
    let spaceNames: [ExportedSpaceName]
    let labels: LabelSettings
    let switching: SwitchingSettings
    let hotkeys: HotkeySettings
    let launcher: LauncherSettings
    let general: GeneralSettings

    init(
        spaceManager: SpaceManager,
        labelManager: SpaceLabelManager,
        gestureManager: GestureManager,
        hotkeyManager: HotkeyManager,
        launcherViewModel: LauncherViewModel
    ) {
        spaceNames = spaceManager.spaceNameDict
            .filter { !$0.customName.isEmpty }
            .map { ExportedSpaceName(spaceAPIID: $0.spaceAPIID, name: $0.customName) }
            .sorted { $0.spaceAPIID < $1.spaceAPIID }

        labels = LabelSettings(manager: labelManager)
        switching = SwitchingSettings(spaceManager: spaceManager, gestureManager: gestureManager)
        hotkeys = HotkeySettings(manager: hotkeyManager)
        launcher = LauncherSettings(viewModel: launcherViewModel)
        general = GeneralSettings(isStatusBarHidden: StatusBarController.isStatusBarHidden)
    }

    struct ExportedSpaceName: Codable {
        let spaceAPIID: String
        let name: String
    }

    struct LabelSettings: Codable {
        let showPreviewLabels: Bool
        let showActiveLabels: Bool
        let hideWhenSwitching: Bool
        let showOnDesktop: Bool
        let disablePreviewLiquidGlass: Bool
        let disableActiveLiquidGlass: Bool
        let activeFontScale: Double
        let activePaddingScale: Double
        let previewFontScale: Double
        let previewPaddingScale: Double
        let isDocked: Bool
        let dockEdge: String

        @MainActor
        init(manager: SpaceLabelManager) {
            showPreviewLabels = manager.showPreviewLabels
            showActiveLabels = manager.showActiveLabels
            hideWhenSwitching = manager.hideWhenSwitching
            showOnDesktop = manager.showOnDesktop
            disablePreviewLiquidGlass = manager.disablePreviewLiquidGlass
            disableActiveLiquidGlass = manager.disableActiveLiquidGlass
            activeFontScale = manager.activeFontScale
            activePaddingScale = manager.activePaddingScale
            previewFontScale = manager.previewFontScale
            previewPaddingScale = manager.previewPaddingScale
            isDocked = manager.globalIsDocked
            dockEdge = Self.edgeName(manager.globalDockEdge)
        }

        private static func edgeName(_ edge: NSRectEdge) -> String {
            switch edge {
            case .minX: return "left"
            case .minY: return "bottom"
            case .maxX: return "right"
            case .maxY: return "top"
            @unknown default: return "right"
            }
        }
    }

    struct SwitchingSettings: Codable {
        let returnToOriginalAfterBatchMove: Bool
        let autoRearrangeFullscreenSpaces: Bool
        let autoRestoreWindowsOnUnlock: Bool
        let grabOffsetX: Double
        let grabOffsetY: Double
        let appGrabExceptions: [AppGrabException]
        let gesturesEnabled: Bool
        let gestureFingerCount: Int
        let gestureSwitchOverride: String
        let gestureSwipeThreshold: Float
        let moveWindowOnOption: Bool
        let gestureSwitchDuration: TimeInterval

        @MainActor
        init(spaceManager: SpaceManager, gestureManager: GestureManager) {
            returnToOriginalAfterBatchMove = spaceManager.returnToOriginalAfterBatchMove
            autoRearrangeFullscreenSpaces = spaceManager.autoRearrangeFullscreenSpaces
            autoRestoreWindowsOnUnlock = spaceManager.autoRestoreWindowsOnUnlock
            grabOffsetX = spaceManager.grabOffsetX
            grabOffsetY = spaceManager.grabOffsetY
            appGrabExceptions = spaceManager.appGrabExceptions
            gesturesEnabled = gestureManager.isEnabled
            gestureFingerCount = gestureManager.fingerCount
            gestureSwitchOverride = gestureManager.switchOverride.rawValue
            gestureSwipeThreshold = gestureManager.swipeThreshold
            moveWindowOnOption = gestureManager.moveWindowOnOption
            gestureSwitchDuration = gestureManager.switchDuration
        }
    }

    struct HotkeySettings: Codable {
        let main: Shortcut
        let switchLeft: Shortcut
        let switchRight: Shortcut
        let moveWindowNext: Shortcut
        let moveWindowPrevious: Shortcut
        let moveWindowNumber: Shortcut
        let switchSpaceNumber: Shortcut
        let reloadLabels: Shortcut
        let moveWindowNextDisplay: Shortcut
        let moveWindowPreviousDisplay: Shortcut
        let toggleLock: Shortcut
        let restoreWindows: Shortcut
        let launcher: Shortcut

        @MainActor
        init(manager: HotkeyManager) {
            main = manager.mainShortcut
            switchLeft = manager.switchLeftShortcut
            switchRight = manager.switchRightShortcut
            moveWindowNext = manager.moveWindowNextShortcut
            moveWindowPrevious = manager.moveWindowPreviousShortcut
            moveWindowNumber = manager.moveWindowNumberShortcut
            switchSpaceNumber = manager.switchSpaceNumberShortcut
            reloadLabels = manager.reloadLabelsShortcut
            moveWindowNextDisplay = manager.moveWindowNextDisplayShortcut
            moveWindowPreviousDisplay = manager.moveWindowPreviousDisplayShortcut
            toggleLock = manager.toggleLockShortcut
            restoreWindows = manager.restoreWindowsShortcut
            launcher = manager.launcherShortcut
        }
    }

    struct LauncherSettings: Codable {
        let automaticallyRankCommands: Bool
        let manualCommandOrder: [String]

        @MainActor
        init(viewModel: LauncherViewModel) {
            automaticallyRankCommands = viewModel.automaticallyRankCommands
            manualCommandOrder = viewModel.launcherManualCommandOrder
                .split(separator: ",")
                .map(String.init)
        }
    }

    struct GeneralSettings: Codable {
        let isStatusBarHidden: Bool
    }
}

@MainActor
enum SettingsExportService {
    static func makeExport(
        spaceManager: SpaceManager,
        labelManager: SpaceLabelManager,
        gestureManager: GestureManager,
        hotkeyManager: HotkeyManager,
        launcherViewModel: LauncherViewModel
    ) throws -> Data {
        let settings = ExportedSettings(
            spaceManager: spaceManager,
            labelManager: labelManager,
            gestureManager: gestureManager,
            hotkeyManager: hotkeyManager,
            launcherViewModel: launcherViewModel
        )
        let document = SettingsExportDocument(settings: settings)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }
}
