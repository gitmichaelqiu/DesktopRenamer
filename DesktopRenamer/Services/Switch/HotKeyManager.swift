import Foundation
import AppKit
import Combine
import HotKey

enum HotkeyType {
    case main
    case switchLeft
    case switchRight
    case moveWindowNext
    case moveWindowPrevious
    case moveWindowNumber
    case switchSpaceNumber
    case reloadLabels
    case moveWindowNextDisplay
    case moveWindowPreviousDisplay
    case toggleLock
    case restoreWindows
    case launcher
}

class HotkeyManager: ObservableObject {
    // Subjects to broadcast hotkey trigger events.
    // Note: PassthroughSubject is used for decoupled event handling in the AppDelegate.
    let mainShortcutTriggered = PassthroughSubject<Void, Never>()
    let switchLeftTriggered = PassthroughSubject<Void, Never>()
    let switchRightTriggered = PassthroughSubject<Void, Never>()
    let moveWindowNextTriggered = PassthroughSubject<Void, Never>()
    let moveWindowPreviousTriggered = PassthroughSubject<Void, Never>()
    let moveWindowNumberTriggered = PassthroughSubject<Int, Never>()
    let switchSpaceNumberTriggered = PassthroughSubject<Int, Never>()
    let reloadLabelsTriggered = PassthroughSubject<Void, Never>()
    let moveWindowNextDisplayTriggered = PassthroughSubject<Void, Never>()
    let moveWindowPreviousDisplayTriggered = PassthroughSubject<Void, Never>()
    let toggleLockTriggered = PassthroughSubject<Void, Never>()
    let restoreWindowsTriggered = PassthroughSubject<Void, Never>()
    let launcherTriggered = PassthroughSubject<Void, Never>()

    // Internal state
    @Published var mainShortcut: Shortcut {
        didSet {
            saveShortcut(mainShortcut, key: mainShortcutKey)
            registerShortcuts()
        }
    }
    
    @Published var switchLeftShortcut: Shortcut {
        didSet {
            saveShortcut(switchLeftShortcut, key: switchLeftKey)
            registerShortcuts()
        }
    }
    
    @Published var switchRightShortcut: Shortcut {
        didSet {
            saveShortcut(switchRightShortcut, key: switchRightKey)
            registerShortcuts()
        }
    }
    
    @Published var moveWindowNextShortcut: Shortcut {
        didSet {
            saveShortcut(moveWindowNextShortcut, key: moveWindowNextKey)
            registerShortcuts()
        }
    }
    
    @Published var moveWindowPreviousShortcut: Shortcut {
        didSet {
            saveShortcut(moveWindowPreviousShortcut, key: moveWindowPreviousKey)
            registerShortcuts()
        }
    }
    
    @Published var moveWindowNumberShortcut: Shortcut { // Stores modifiers only for number-based space switching.
        didSet {
            saveShortcut(moveWindowNumberShortcut, key: moveWindowNumberKey)
            registerShortcuts()
        }
    }
    
    @Published var switchSpaceNumberShortcut: Shortcut {
        didSet {
            saveShortcut(switchSpaceNumberShortcut, key: switchSpaceNumberKey)
            registerShortcuts()
        }
    }
    
    @Published var reloadLabelsShortcut: Shortcut {
        didSet {
            saveShortcut(reloadLabelsShortcut, key: reloadLabelsKey)
            registerShortcuts()
        }
    }
    
    @Published var moveWindowNextDisplayShortcut: Shortcut {
        didSet {
            saveShortcut(moveWindowNextDisplayShortcut, key: moveWindowNextDisplayKey)
            registerShortcuts()
        }
    }
    
    @Published var moveWindowPreviousDisplayShortcut: Shortcut {
        didSet {
            saveShortcut(moveWindowPreviousDisplayShortcut, key: moveWindowPreviousDisplayKey)
            registerShortcuts()
        }
    }
    
    @Published var toggleLockShortcut: Shortcut {
        didSet {
            saveShortcut(toggleLockShortcut, key: toggleLockKey)
            registerShortcuts()
        }
    }
    
    @Published var restoreWindowsShortcut: Shortcut {
        didSet {
            saveShortcut(restoreWindowsShortcut, key: restoreWindowsKey)
            registerShortcuts()
        }
    }
    
    @Published var launcherShortcut: Shortcut {
        didSet {
            saveShortcut(launcherShortcut, key: launcherKey)
            registerShortcuts()
        }
    }

    @Published var isListening: Bool = false
    @Published var listeningType: HotkeyType? = nil

    // Internal hotkey objects from the library
    var mainHotKey: HotKey?
    var switchLeftHotKey: HotKey?
    var switchRightHotKey: HotKey?
    var moveWindowNextHotKey: HotKey?
    var moveWindowPreviousHotKey: HotKey?
    var moveWindowNumberHotKeys: [HotKey] = []
    var switchSpaceNumberHotKeys: [HotKey] = []
    var reloadLabelsHotKey: HotKey?
    var moveWindowNextDisplayHotKey: HotKey?
    var moveWindowPreviousDisplayHotKey: HotKey?
    var toggleLockHotKey: HotKey?
    var restoreWindowsHotKey: HotKey?
    var launcherHotKey: HotKey?

    var monitor: Any?

    // Default shortcut configurations.
    let defaultMain = Shortcut(key: nil, modifiers: [])
    let defaultNone = Shortcut(key: nil, modifiers: [])

    let mainShortcutKey = "HotkeyManager.Shortcut"
    let switchLeftKey = "HotkeyManager.SwitchLeft"
    let switchRightKey = "HotkeyManager.SwitchRight"
    let moveWindowNextKey = "HotkeyManager.MoveWindowNext"
    let moveWindowPreviousKey = "HotkeyManager.MoveWindowPrevious"
    let moveWindowNumberKey = "HotkeyManager.MoveWindowNumber"
    let switchSpaceNumberKey = "HotkeyManager.SwitchSpaceNumber"
    let reloadLabelsKey = "HotkeyManager.ReloadLabels"
    let moveWindowNextDisplayKey = "HotkeyManager.MoveWindowNextDisplay"
    let moveWindowPreviousDisplayKey = "HotkeyManager.MoveWindowPreviousDisplay"
    let toggleLockKey = "HotkeyManager.ToggleLock"
    let restoreWindowsKey = "HotkeyManager.RestoreWindows"
    let launcherKey = "HotkeyManager.Launcher"

    init() {
        // Load or default
        let loadedMain = Self.loadShortcut(key: mainShortcutKey)
        if let loaded = loadedMain, loaded.key == .r && loaded.modifiers == [.control] {
            // This was the problematic default introduced in some previous versions, clear it for now
            self.mainShortcut = Shortcut(key: nil, modifiers: [])
        } else {
            self.mainShortcut = loadedMain ?? Shortcut(key: nil, modifiers: [])
        }
        self.switchLeftShortcut = Self.loadShortcut(key: switchLeftKey) ?? Shortcut(key: nil, modifiers: [])
        self.switchRightShortcut = Self.loadShortcut(key: switchRightKey) ?? Shortcut(key: nil, modifiers: [])
        self.moveWindowNextShortcut = Self.loadShortcut(key: moveWindowNextKey) ?? Shortcut(key: nil, modifiers: [])
        self.moveWindowPreviousShortcut = Self.loadShortcut(key: moveWindowPreviousKey) ?? Shortcut(key: nil, modifiers: [])
        self.moveWindowNumberShortcut = Self.loadShortcut(key: moveWindowNumberKey) ?? Shortcut(key: nil, modifiers: [])
        self.switchSpaceNumberShortcut = Self.loadShortcut(key: switchSpaceNumberKey) ?? Shortcut(key: nil, modifiers: [])
        self.reloadLabelsShortcut = Self.loadShortcut(key: reloadLabelsKey) ?? Shortcut(key: nil, modifiers: [])
        self.moveWindowNextDisplayShortcut = Self.loadShortcut(key: moveWindowNextDisplayKey) ?? Shortcut(key: nil, modifiers: [])
        self.moveWindowPreviousDisplayShortcut = Self.loadShortcut(key: moveWindowPreviousDisplayKey) ?? Shortcut(key: nil, modifiers: [])
        self.toggleLockShortcut = Self.loadShortcut(key: toggleLockKey) ?? Shortcut(key: nil, modifiers: [])
        self.restoreWindowsShortcut = Self.loadShortcut(key: restoreWindowsKey) ?? Shortcut(key: nil, modifiers: [])
        self.launcherShortcut = Self.loadShortcut(key: launcherKey) ?? Shortcut(key: nil, modifiers: [])
        
        registerShortcuts()
    }
    
    // Helpers for the settings UI
    
    func description(for type: HotkeyType) -> String {
        if isListening && listeningType == type {
            return NSLocalizedString("Settings.Shortcuts.Hotkey.PressNew", comment: "Press new shortcut…")
        }
        switch type {
        case .main: return mainShortcut.description
        case .switchLeft: return switchLeftShortcut.description
        case .switchRight: return switchRightShortcut.description
        case .moveWindowNext: return moveWindowNextShortcut.description
        case .moveWindowPrevious: return moveWindowPreviousShortcut.description
        case .reloadLabels: return reloadLabelsShortcut.description
        case .moveWindowNextDisplay: return moveWindowNextDisplayShortcut.description
        case .moveWindowPreviousDisplay: return moveWindowPreviousDisplayShortcut.description
        case .toggleLock: return toggleLockShortcut.description
        case .restoreWindows: return restoreWindowsShortcut.description
        case .launcher: return launcherShortcut.description
        case .moveWindowNumber:
            if moveWindowNumberShortcut.modifiers.isEmpty {
                 return NSLocalizedString("Settings.Shortcuts.Unassgined", comment: "Unassigned")
            }
            // Manually construct description: Modifiers + Number
            var parts: [String] = []
            if moveWindowNumberShortcut.modifiers.contains(.command) { parts.append("⌘") }
            if moveWindowNumberShortcut.modifiers.contains(.option) { parts.append("⌥") }
            if moveWindowNumberShortcut.modifiers.contains(.control) { parts.append("^") }
            if moveWindowNumberShortcut.modifiers.contains(.shift) { parts.append("⇧") }
            parts.append(NSLocalizedString(" + Number", comment: ""))
            return parts.joined()
        case .switchSpaceNumber:
            if switchSpaceNumberShortcut.modifiers.isEmpty {
                 return NSLocalizedString("Settings.Shortcuts.Unassgined", comment: "Unassigned")
            }
            // Manually construct description: Modifiers + Number
            var parts: [String] = []
            if switchSpaceNumberShortcut.modifiers.contains(.command) { parts.append("⌘") }
            if switchSpaceNumberShortcut.modifiers.contains(.option) { parts.append("⌥") }
            if switchSpaceNumberShortcut.modifiers.contains(.control) { parts.append("^") }
            if switchSpaceNumberShortcut.modifiers.contains(.shift) { parts.append("⇧") }
            parts.append(NSLocalizedString(" + Number", comment: ""))
            return parts.joined()
        }
    }

    deinit {
        mainHotKey = nil
        switchLeftHotKey = nil
        switchRightHotKey = nil
        toggleLockHotKey = nil
        restoreWindowsHotKey = nil
        launcherHotKey = nil
        moveWindowNumberHotKeys.removeAll()
        switchSpaceNumberHotKeys.removeAll()
        removeKeyListener()
    }
}
