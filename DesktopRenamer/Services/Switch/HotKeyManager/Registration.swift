import AppKit
import Combine
import Foundation
import HotKey

extension HotkeyManager {

    func registerShortcuts() {
        // Main Hotkey.
        mainHotKey = nil // Clear existing
        if let key = mainShortcut.hotkeyKey, let mods = mainShortcut.hotkeyModifiers {
            mainHotKey = HotKey(key: key, modifiers: mods)
            mainHotKey?.keyDownHandler = { [weak self] in
                DiagnosticEventLog.shared.record(subsystem: "Hotkey", level: "info", "Hotkey triggered: Main")
                self?.mainShortcutTriggered.send()
                // Legacy notification support if needed
                NotificationCenter.default.post(name: .hotkeyTriggered, object: nil)
            }
        }
        
        // Switch Left.
        switchLeftHotKey = nil
        if let key = switchLeftShortcut.hotkeyKey, let mods = switchLeftShortcut.hotkeyModifiers {
            switchLeftHotKey = HotKey(key: key, modifiers: mods)
            switchLeftHotKey?.keyDownHandler = { [weak self] in
                DiagnosticEventLog.shared.record(subsystem: "Hotkey", level: "info", "Hotkey triggered: Switch Left")
                self?.switchLeftTriggered.send()
            }
        }
        
        // Switch Right.
        switchRightHotKey = nil
        if let key = switchRightShortcut.hotkeyKey, let mods = switchRightShortcut.hotkeyModifiers {
            switchRightHotKey = HotKey(key: key, modifiers: mods)
            switchRightHotKey?.keyDownHandler = { [weak self] in
                DiagnosticEventLog.shared.record(subsystem: "Hotkey", level: "info", "Hotkey triggered: Switch Right")
                self?.switchRightTriggered.send()
            }
        }
        
        // Move Window Next.
        moveWindowNextHotKey = nil
        if let key = moveWindowNextShortcut.hotkeyKey, let mods = moveWindowNextShortcut.hotkeyModifiers {
            moveWindowNextHotKey = HotKey(key: key, modifiers: mods)
            moveWindowNextHotKey?.keyDownHandler = { [weak self] in
                DiagnosticEventLog.shared.record(subsystem: "Hotkey", level: "info", "Hotkey triggered: Move Window Next")
                self?.moveWindowNextTriggered.send()
            }
        }
        
        // Move Window Previous.
        moveWindowPreviousHotKey = nil
        if let key = moveWindowPreviousShortcut.hotkeyKey, let mods = moveWindowPreviousShortcut.hotkeyModifiers {
            moveWindowPreviousHotKey = HotKey(key: key, modifiers: mods)
            moveWindowPreviousHotKey?.keyDownHandler = { [weak self] in
                DiagnosticEventLog.shared.record(subsystem: "Hotkey", level: "info", "Hotkey triggered: Move Window Previous")
                self?.moveWindowPreviousTriggered.send()
            }
        }
        
        // Reload Space Labels.
        reloadLabelsHotKey = nil
        if let key = reloadLabelsShortcut.hotkeyKey, let mods = reloadLabelsShortcut.hotkeyModifiers {
            reloadLabelsHotKey = HotKey(key: key, modifiers: mods)
            reloadLabelsHotKey?.keyDownHandler = { [weak self] in
                DiagnosticEventLog.shared.record(subsystem: "Hotkey", level: "info", "Hotkey triggered: Reload Space Labels")
                self?.reloadLabelsTriggered.send()
            }
        }
        
        // Move Window to Next Display.
        moveWindowNextDisplayHotKey = nil
        if let key = moveWindowNextDisplayShortcut.hotkeyKey, let mods = moveWindowNextDisplayShortcut.hotkeyModifiers {
            moveWindowNextDisplayHotKey = HotKey(key: key, modifiers: mods)
            moveWindowNextDisplayHotKey?.keyDownHandler = { [weak self] in
                DiagnosticEventLog.shared.record(subsystem: "Hotkey", level: "info", "Hotkey triggered: Move Window Next Display")
                self?.moveWindowNextDisplayTriggered.send()
            }
        }
        
        // Move Window to Previous Display.
        moveWindowPreviousDisplayHotKey = nil
        if let key = moveWindowPreviousDisplayShortcut.hotkeyKey, let mods = moveWindowPreviousDisplayShortcut.hotkeyModifiers {
            moveWindowPreviousDisplayHotKey = HotKey(key: key, modifiers: mods)
            moveWindowPreviousDisplayHotKey?.keyDownHandler = { [weak self] in
                DiagnosticEventLog.shared.record(subsystem: "Hotkey", level: "info", "Hotkey triggered: Move Window Previous Display")
                self?.moveWindowPreviousDisplayTriggered.send()
            }
        }
        
        // Toggle Lock.
        toggleLockHotKey = nil
        if let key = toggleLockShortcut.hotkeyKey, let mods = toggleLockShortcut.hotkeyModifiers {
            toggleLockHotKey = HotKey(key: key, modifiers: mods)
            toggleLockHotKey?.keyDownHandler = { [weak self] in
                DiagnosticEventLog.shared.record(subsystem: "Hotkey", level: "info", "Hotkey triggered: Toggle Lock")
                self?.toggleLockTriggered.send()
            }
        }
        
        // Restore Windows.
        restoreWindowsHotKey = nil
        if let key = restoreWindowsShortcut.hotkeyKey, let mods = restoreWindowsShortcut.hotkeyModifiers {
            restoreWindowsHotKey = HotKey(key: key, modifiers: mods)
            restoreWindowsHotKey?.keyDownHandler = { [weak self] in
                DiagnosticEventLog.shared.record(subsystem: "Hotkey", level: "info", "Hotkey triggered: Restore Windows")
                self?.restoreWindowsTriggered.send()
            }
        }
        
        // Launcher.
        launcherHotKey = nil
        if let key = launcherShortcut.hotkeyKey, let mods = launcherShortcut.hotkeyModifiers {
            launcherHotKey = HotKey(key: key, modifiers: mods)
            launcherHotKey?.keyDownHandler = { [weak self] in
                DiagnosticEventLog.shared.record(subsystem: "Hotkey", level: "info", "Hotkey triggered: Launcher")
                self?.launcherTriggered.send()
            }
        }
        
        // Move Window Number (1-9).
        // We register hotkeys for Modifiers + 1...9
        let modSet = moveWindowNumberShortcut.modifiers.intersection([.command, .option, .control, .shift])
        if !modSet.isEmpty {
            let numberKeys: [(Key, Int)] = [
                (.one, 1), (.two, 2), (.three, 3), (.four, 4), (.five, 5),
                (.six, 6), (.seven, 7), (.eight, 8), (.nine, 9)
            ]
            
            for (key, number) in numberKeys {
                let hk = HotKey(key: key, modifiers: modSet)
                hk.keyDownHandler = { [weak self] in
                    DiagnosticEventLog.shared.record(subsystem: "Hotkey", level: "info", "Hotkey triggered: Move Window to Space Number \(number)")
                    self?.moveWindowNumberTriggered.send(number)
                }
                moveWindowNumberHotKeys.append(hk)
            }
        }
        
        // Switch Space Number (1-9).
        switchSpaceNumberHotKeys.removeAll()
        let switchModSet = switchSpaceNumberShortcut.modifiers.intersection([.command, .option, .control, .shift])
        if !switchModSet.isEmpty {
            let numberKeys: [(Key, Int)] = [
                (.one, 1), (.two, 2), (.three, 3), (.four, 4), (.five, 5),
                (.six, 6), (.seven, 7), (.eight, 8), (.nine, 9)
            ]
            
            for (key, number) in numberKeys {
                let hk = HotKey(key: key, modifiers: switchModSet)
                hk.keyDownHandler = { [weak self] in
                    DiagnosticEventLog.shared.record(subsystem: "Hotkey", level: "info", "Hotkey triggered: Switch to Space Number \(number)")
                    self?.switchSpaceNumberTriggered.send(number)
                }
                switchSpaceNumberHotKeys.append(hk)
            }
        }
    }

}
