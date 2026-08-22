import AppKit
import Combine
import Foundation
import HotKey

extension HotkeyManager {

    // Hotkey recording/listening logic.
    func startListening(for type: HotkeyType) {
        isListening = true
        listeningType = type

        // Unregister existing hotkeys during recording sessions.
        mainHotKey = nil
        switchLeftHotKey = nil
        switchRightHotKey = nil
        moveWindowNextHotKey = nil
        moveWindowPreviousHotKey = nil
        reloadLabelsHotKey = nil
        moveWindowNextDisplayHotKey = nil
        moveWindowPreviousDisplayHotKey = nil
        toggleLockHotKey = nil
        restoreWindowsHotKey = nil
        launcherHotKey = nil
        moveWindowNumberHotKeys.removeAll()
        switchSpaceNumberHotKeys.removeAll()

        removeKeyListener()

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // Check for Escape to cancel/clear
            if Shortcut.keyName(from: event) == "Escape" {
                self.updateShortcut(Shortcut(key: nil, modifiers: []), for: type)
                self.finishListening()
                return nil
            }
            
            if type == .moveWindowNumber || type == .switchSpaceNumber {
                guard Shortcut.keyFromEvent(event) != nil else { return event }
                let rawModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
                let cleanedModifiers = self.convertToHotkeyModifiers(rawModifiers)
                
                if !cleanedModifiers.isEmpty {
                    self.updateShortcut(Shortcut(key: nil, modifiers: cleanedModifiers), for: type)
                    self.finishListening()
                    return nil
                }
                return nil
            }
            
            guard let key = Shortcut.keyFromEvent(event) else { return event }
            
            let rawModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let cleanedModifiers = self.convertToHotkeyModifiers(rawModifiers)
            
            let isFunctionKey = HotkeyManager.functionKeys.contains(key)
            let hasModifiers = !cleanedModifiers.isEmpty
            
            // Accept if it has modifiers OR is a function key
            if hasModifiers || isFunctionKey {
                self.updateShortcut(Shortcut(key: key, modifiers: cleanedModifiers), for: type)
                self.finishListening()
                return nil
            }
            
            // Allow typing if not a valid shortcut
            return nil
        }
    }
    
    private func updateShortcut(_ shortcut: Shortcut, for type: HotkeyType) {
        switch type {
        case .main: mainShortcut = shortcut
        case .switchLeft: switchLeftShortcut = shortcut
        case .switchRight: switchRightShortcut = shortcut
        case .moveWindowNext: moveWindowNextShortcut = shortcut
        case .moveWindowPrevious: moveWindowPreviousShortcut = shortcut
        case .moveWindowNumber: moveWindowNumberShortcut = shortcut
        case .switchSpaceNumber: switchSpaceNumberShortcut = shortcut
        case .reloadLabels: reloadLabelsShortcut = shortcut
        case .moveWindowNextDisplay: moveWindowNextDisplayShortcut = shortcut
        case .moveWindowPreviousDisplay: moveWindowPreviousDisplayShortcut = shortcut
        case .toggleLock: toggleLockShortcut = shortcut
        case .restoreWindows: restoreWindowsShortcut = shortcut
        case .launcher: launcherShortcut = shortcut
        }
    }
    
    private func finishListening() {
        isListening = false
        listeningType = nil
        removeKeyListener()
        registerShortcuts()
    }
    
    func removeKeyListener() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
