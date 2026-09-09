import AppKit
import Combine
import Foundation
import HotKey

extension HotkeyManager {

    func isDefault(for type: HotkeyType) -> Bool {
        switch type {
        case .main: return mainShortcut == defaultMain
        case .switchLeft: return switchLeftShortcut == defaultNone
        case .switchRight: return switchRightShortcut == defaultNone
        case .moveWindowNext: return moveWindowNextShortcut == defaultNone
        case .moveWindowPrevious: return moveWindowPreviousShortcut == defaultNone
        case .moveWindowNumber: return moveWindowNumberShortcut == defaultNone
        case .switchSpaceNumber: return switchSpaceNumberShortcut == defaultNone
        case .reloadLabels: return reloadLabelsShortcut == defaultNone
        case .moveWindowNextDisplay: return moveWindowNextDisplayShortcut == defaultNone
        case .moveWindowPreviousDisplay: return moveWindowPreviousDisplayShortcut == defaultNone
        case .toggleLock: return toggleLockShortcut == defaultNone
        case .restoreWindows: return restoreWindowsShortcut == defaultNone
        case .launcher: return launcherShortcut == defaultNone
        }
    }
    
    func resetToDefault(for type: HotkeyType) {
        switch type {
        case .main: mainShortcut = defaultMain
        case .switchLeft: switchLeftShortcut = defaultNone
        case .switchRight: switchRightShortcut = defaultNone
        case .moveWindowNext: moveWindowNextShortcut = defaultNone
        case .moveWindowPrevious: moveWindowPreviousShortcut = defaultNone
        case .moveWindowNumber: moveWindowNumberShortcut = defaultNone
        case .switchSpaceNumber: switchSpaceNumberShortcut = defaultNone
        case .reloadLabels: reloadLabelsShortcut = defaultNone
        case .moveWindowNextDisplay: moveWindowNextDisplayShortcut = defaultNone
        case .moveWindowPreviousDisplay: moveWindowPreviousDisplayShortcut = defaultNone
        case .toggleLock: toggleLockShortcut = defaultNone
        case .restoreWindows: restoreWindowsShortcut = defaultNone
        case .launcher: launcherShortcut = defaultNone
        }
    }
    
    // Saving and loading from UserDefaults
    
    func saveShortcut(_ shortcut: Shortcut, key: String) {
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func loadShortcut(key: String) -> Shortcut? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) else {
            return nil
        }
        return shortcut
    }
    
    func convertToHotkeyModifiers(_ modifiers: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        var result = NSEvent.ModifierFlags()
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        return result
    }
    
    static let functionKeys: Set<Key> = [
        Key.f1, Key.f2, Key.f3, Key.f4, Key.f5, Key.f6,
        Key.f7, Key.f8, Key.f9, Key.f10, Key.f11, Key.f12
    ]
    
}
