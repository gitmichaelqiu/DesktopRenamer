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
            .map { space in
                let displayIndex = SpaceHelper.getAllDisplayUUIDs()
                    .firstIndex(of: space.displayID)
                let displaySpaces = spaceManager.spaceNameDict
                    .filter { $0.displayID == space.displayID && !$0.isFullscreen }
                    .sorted { $0.num < $1.num }
                let spaceIndex = displaySpaces.firstIndex { $0.spaceAPIID == space.spaceAPIID }
                    .map { $0 + 1 }
                return ExportedSpaceName(
                    spaceAPIID: space.spaceAPIID,
                    name: space.customName,
                    displayIndex: displayIndex,
                    spaceIndex: spaceIndex
                )
            }
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
        let displayIndex: Int?
        let spaceIndex: Int?

        init(spaceAPIID: String, name: String, displayIndex: Int?, spaceIndex: Int?) {
            self.spaceAPIID = spaceAPIID
            self.name = name
            self.displayIndex = displayIndex
            self.spaceIndex = spaceIndex
        }
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

@MainActor
enum SettingsImportService {
    private static let maximumFileSize = 5 * 1024 * 1024
    private static let formatIdentifier = "dev.mqiu.desktoprenamer.settings"
    private static let supportedVersion = 1

    struct Plan {
        let settings: ExportedSettings
        let spaceNameAssignments: [(spaceID: String, name: String)]
        let unmatchedSpaceNameCount: Int
    }

    enum ImportError: LocalizedError {
        case fileTooLarge
        case invalidDocument
        case unsupportedVersion

        var errorDescription: String? {
            switch self {
            case .fileTooLarge:
                return NSLocalizedString("Settings.General.Import.Error.TooLarge", comment: "")
            case .invalidDocument:
                return NSLocalizedString("Settings.General.Import.Error.Invalid", comment: "")
            case .unsupportedVersion:
                return NSLocalizedString("Settings.General.Import.Error.Version", comment: "")
            }
        }
    }

    static func makePlan(from data: Data, spaceManager: SpaceManager) throws -> Plan {
        guard data.count <= maximumFileSize else { throw ImportError.fileTooLarge }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              raw["format"] as? String == formatIdentifier,
              let version = raw["version"] as? Int else {
            throw ImportError.invalidDocument
        }
        guard version == supportedVersion else { throw ImportError.unsupportedVersion }
        try validateRawShortcuts(in: raw)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(SettingsExportDocument.self, from: data),
              document.format == formatIdentifier,
              document.version == supportedVersion else {
            throw ImportError.invalidDocument
        }
        try validate(document.settings)

        let screenDisplayIDs = SpaceHelper.getAllDisplayUUIDs()
        let availableSpaces = spaceManager.spaceNameDict.filter { !$0.isFullscreen }
        var usedSpaceIDs = Set<String>()
        var assignments: [(spaceID: String, name: String)] = []
        var unmatchedCount = 0

        for exportedName in document.settings.spaceNames {
            let exactMatch = availableSpaces.first {
                $0.spaceAPIID == exportedName.spaceAPIID && !usedSpaceIDs.contains($0.id)
            }
            let positionalMatch: DesktopSpace? = {
                guard let displayIndex = exportedName.displayIndex,
                      screenDisplayIDs.indices.contains(displayIndex),
                      let spaceIndex = exportedName.spaceIndex,
                      spaceIndex > 0 else { return nil }
                let displaySpaces = availableSpaces
                    .filter { $0.displayID == screenDisplayIDs[displayIndex] }
                    .sorted { $0.num < $1.num }
                guard displaySpaces.indices.contains(spaceIndex - 1) else { return nil }
                return displaySpaces[spaceIndex - 1]
            }()
            let match = exactMatch ?? positionalMatch
            guard let match, !usedSpaceIDs.contains(match.id) else {
                unmatchedCount += 1
                continue
            }
            usedSpaceIDs.insert(match.id)
            assignments.append((spaceID: match.id, name: exportedName.name))
        }

        return Plan(
            settings: document.settings,
            spaceNameAssignments: assignments,
            unmatchedSpaceNameCount: unmatchedCount
        )
    }

    static func apply(
        _ plan: Plan,
        spaceManager: SpaceManager,
        labelManager: SpaceLabelManager,
        gestureManager: GestureManager,
        hotkeyManager: HotkeyManager,
        launcherViewModel: LauncherViewModel
    ) {
        let settings = plan.settings

        for assignment in plan.spaceNameAssignments {
            spaceManager.renameSpace(assignment.spaceID, to: assignment.name)
        }

        labelManager.showPreviewLabels = settings.labels.showPreviewLabels
        labelManager.showActiveLabels = settings.labels.showActiveLabels
        labelManager.hideWhenSwitching = settings.labels.hideWhenSwitching
        labelManager.showOnDesktop = settings.labels.showOnDesktop
        labelManager.disablePreviewLiquidGlass = settings.labels.disablePreviewLiquidGlass
        labelManager.disableActiveLiquidGlass = settings.labels.disableActiveLiquidGlass
        labelManager.activeFontScale = settings.labels.activeFontScale
        labelManager.activePaddingScale = settings.labels.activePaddingScale
        labelManager.previewFontScale = settings.labels.previewFontScale
        labelManager.previewPaddingScale = settings.labels.previewPaddingScale
        labelManager.updateDockingSettings(
            isDocked: settings.labels.isDocked,
            edge: dockEdge(from: settings.labels.dockEdge)
        )

        spaceManager.returnToOriginalAfterBatchMove = settings.switching.returnToOriginalAfterBatchMove
        spaceManager.autoRearrangeFullscreenSpaces = settings.switching.autoRearrangeFullscreenSpaces
        spaceManager.autoRestoreWindowsOnUnlock = settings.switching.autoRestoreWindowsOnUnlock
        spaceManager.grabOffsetX = settings.switching.grabOffsetX
        spaceManager.grabOffsetY = settings.switching.grabOffsetY
        spaceManager.appGrabExceptions = settings.switching.appGrabExceptions

        gestureManager.isEnabled = settings.switching.gesturesEnabled
        gestureManager.fingerCount = settings.switching.gestureFingerCount
        gestureManager.switchOverride = GestureManager.SwitchOverrideMode(
            rawValue: settings.switching.gestureSwitchOverride
        ) ?? .cursor
        gestureManager.swipeThreshold = settings.switching.gestureSwipeThreshold
        gestureManager.moveWindowOnOption = settings.switching.moveWindowOnOption
        gestureManager.switchDuration = settings.switching.gestureSwitchDuration

        hotkeyManager.updateShortcuts {
            hotkeyManager.mainShortcut = settings.hotkeys.main
            hotkeyManager.switchLeftShortcut = settings.hotkeys.switchLeft
            hotkeyManager.switchRightShortcut = settings.hotkeys.switchRight
            hotkeyManager.moveWindowNextShortcut = settings.hotkeys.moveWindowNext
            hotkeyManager.moveWindowPreviousShortcut = settings.hotkeys.moveWindowPrevious
            hotkeyManager.moveWindowNumberShortcut = settings.hotkeys.moveWindowNumber
            hotkeyManager.switchSpaceNumberShortcut = settings.hotkeys.switchSpaceNumber
            hotkeyManager.reloadLabelsShortcut = settings.hotkeys.reloadLabels
            hotkeyManager.moveWindowNextDisplayShortcut = settings.hotkeys.moveWindowNextDisplay
            hotkeyManager.moveWindowPreviousDisplayShortcut = settings.hotkeys.moveWindowPreviousDisplay
            hotkeyManager.toggleLockShortcut = settings.hotkeys.toggleLock
            hotkeyManager.restoreWindowsShortcut = settings.hotkeys.restoreWindows
            hotkeyManager.launcherShortcut = settings.hotkeys.launcher
        }

        launcherViewModel.automaticallyRankCommands = settings.launcher.automaticallyRankCommands
        let knownCommandIDs = Set(launcherViewModel.allCommands.map(\.id))
        launcherViewModel.launcherManualCommandOrder = settings.launcher.manualCommandOrder
            .filter { knownCommandIDs.contains($0) }
            .joined(separator: ",")
        launcherViewModel.objectWillChange.send()

        if StatusBarController.isStatusBarHidden != settings.general.isStatusBarHidden {
            StatusBarController.toggleStatusBar()
        }
    }

    private static func validateRawShortcuts(in document: [String: Any]) throws {
        guard let settings = document["settings"] as? [String: Any],
              let hotkeys = settings["hotkeys"] as? [String: Any] else {
            throw ImportError.invalidDocument
        }

        let supportedModifierMask = [NSEvent.ModifierFlags.command, .option, .control, .shift]
            .reduce(UInt(0)) { $0 | $1.rawValue }
        let keys = [
            "main", "switchLeft", "switchRight", "moveWindowNext", "moveWindowPrevious",
            "moveWindowNumber", "switchSpaceNumber", "reloadLabels", "moveWindowNextDisplay",
            "moveWindowPreviousDisplay", "toggleLock", "restoreWindows", "launcher"
        ]

        for key in keys {
            guard let shortcut = hotkeys[key] as? [String: Any],
                  shortcut.keys.contains("key"),
                  let modifiers = shortcut["modifiers"] as? NSNumber,
                  modifiers.uintValue & ~supportedModifierMask == 0 else {
                throw ImportError.invalidDocument
            }
            if let keyDescription = shortcut["key"] as? String,
               Shortcut.keyFromDescription(keyDescription) == nil {
                throw ImportError.invalidDocument
            } else if shortcut["key"] != nil && !(shortcut["key"] is NSNull)
                && !(shortcut["key"] is String) {
                throw ImportError.invalidDocument
            }
        }
    }

    private static func validate(_ settings: ExportedSettings) throws {
        let labels = settings.labels
        guard [labels.activeFontScale, labels.previewFontScale].allSatisfy({ $0.isFinite && (0.5...2.0).contains($0) }),
              [labels.activePaddingScale, labels.previewPaddingScale].allSatisfy({ $0.isFinite && (0.5...3.0).contains($0) }),
              ["left", "bottom", "right", "top"].contains(labels.dockEdge) else {
            throw ImportError.invalidDocument
        }

        let switching = settings.switching
        guard switching.grabOffsetX.isFinite, (0...100).contains(switching.grabOffsetX),
              switching.grabOffsetY.isFinite, (0...100).contains(switching.grabOffsetY),
              switching.gestureFingerCount == 3 || switching.gestureFingerCount == 4,
              GestureManager.SwitchOverrideMode(rawValue: switching.gestureSwitchOverride) != nil,
              switching.gestureSwipeThreshold.isFinite, (0.05...0.50).contains(switching.gestureSwipeThreshold),
              switching.gestureSwitchDuration.isFinite, (0...1.0).contains(switching.gestureSwitchDuration),
              switching.appGrabExceptions.count <= 500,
              Set(switching.appGrabExceptions.map(\.bundleIdentifier)).count == switching.appGrabExceptions.count,
              switching.appGrabExceptions.allSatisfy({
                  !$0.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && $0.grabOffsetX.isFinite && (0...300).contains($0.grabOffsetX)
                      && $0.grabOffsetY.isFinite && (0...300).contains($0.grabOffsetY)
              }) else {
            throw ImportError.invalidDocument
        }

        let names = settings.spaceNames
        guard names.count <= 500,
              Set(names.map(\.spaceAPIID)).count == names.count,
              names.allSatisfy({
                  !$0.spaceAPIID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && $0.name.count <= 256
                      && ($0.displayIndex == nil || $0.displayIndex! >= 0)
                      && ($0.spaceIndex == nil || $0.spaceIndex! > 0)
              }),
              settings.launcher.manualCommandOrder.count <= 500,
              Set(settings.launcher.manualCommandOrder).count == settings.launcher.manualCommandOrder.count else {
            throw ImportError.invalidDocument
        }
    }

    private static func dockEdge(from value: String) -> NSRectEdge {
        switch value {
        case "left": return .minX
        case "bottom": return .minY
        case "top": return .maxY
        default: return .maxX
        }
    }
}
