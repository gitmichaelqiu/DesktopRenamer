import Foundation
import AppKit
import Combine
import HotKey

enum HotkeyType {
    case main
    case switchLeft
    case switchRight
}

class HotkeyManager: ObservableObject {
    // These let the rest of the app know when a hotkey was pressed
    // We use PassthroughSubject so the App/AppDelegate can listen and act
    let mainShortcutTriggered = PassthroughSubject<Void, Never>()
    let switchLeftTriggered = PassthroughSubject<Void, Never>()
    let switchRightTriggered = PassthroughSubject<Void, Never>()

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

    @Published var isListening: Bool = false
    @Published var listeningType: HotkeyType? = nil

    // Internal hotkey objects from the library
    private var mainHotKey: HotKey?
    private var switchLeftHotKey: HotKey?
    private var switchRightHotKey: HotKey?
    
    private var monitor: Any?
    
    // Default: Main (Ctrl+R), Others (None)
    private let defaultMain = Shortcut(key: Key.r, modifiers: [.control])
    private let defaultNone = Shortcut(key: nil, modifiers: [])
    
    private let mainShortcutKey = "HotkeyManager.Shortcut"
    private let switchLeftKey = "HotkeyManager.SwitchLeft"
    private let switchRightKey = "HotkeyManager.SwitchRight"

    init() {
        // Load or default
        self.mainShortcut = Self.loadShortcut(key: mainShortcutKey) ?? Shortcut(key: Key.r, modifiers: [.control])
        self.switchLeftShortcut = Self.loadShortcut(key: switchLeftKey) ?? Shortcut(key: nil, modifiers: [])
        self.switchRightShortcut = Self.loadShortcut(key: switchRightKey) ?? Shortcut(key: nil, modifiers: [])
        
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
        }
    }

    // Hooking up the actual shortcuts to the system
    
    private func registerShortcuts() {
        // 1. Main
        mainHotKey = nil // Clear existing
        if let key = mainShortcut.hotkeyKey, let mods = mainShortcut.hotkeyModifiers {
            mainHotKey = HotKey(key: key, modifiers: mods)
            mainHotKey?.keyDownHandler = { [weak self] in
                self?.mainShortcutTriggered.send()
                // Legacy notification support if needed
                NotificationCenter.default.post(name: .hotkeyTriggered, object: nil)
            }
        }
        
        // 2. Switch Left
        switchLeftHotKey = nil
        if let key = switchLeftShortcut.hotkeyKey, let mods = switchLeftShortcut.hotkeyModifiers {
            switchLeftHotKey = HotKey(key: key, modifiers: mods)
            switchLeftHotKey?.keyDownHandler = { [weak self] in
                self?.switchLeftTriggered.send()
            }
        }
        
        // 3. Switch Right
        switchRightHotKey = nil
        if let key = switchRightShortcut.hotkeyKey, let mods = switchRightShortcut.hotkeyModifiers {
            switchRightHotKey = HotKey(key: key, modifiers: mods)
            switchRightHotKey?.keyDownHandler = { [weak self] in
                self?.switchRightTriggered.send()
            }
        }
    }

    // Logic for "Press a key" recording mode

    func startListening(for type: HotkeyType) {
        isListening = true
        listeningType = type

        // Temporarily disable hotkeys while recording
        mainHotKey = nil
        switchLeftHotKey = nil
        switchRightHotKey = nil

        removeKeyListener()

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // Check for Escape to cancel/clear
            if Shortcut.keyName(from: event) == "Escape" {
                self.updateShortcut(Shortcut(key: nil, modifiers: []), for: type)
                self.finishListening()
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
        }
    }
    
    private func finishListening() {
        isListening = false
        listeningType = nil
        removeKeyListener()
        registerShortcuts()
    }
    
    private func removeKeyListener() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
    
    func resetToDefault(for type: HotkeyType) {
        switch type {
        case .main: mainShortcut = defaultMain
        case .switchLeft: switchLeftShortcut = defaultNone
        case .switchRight: switchRightShortcut = defaultNone
        }
    }
    
    // Saving and loading from UserDefaults
    
    private func saveShortcut(_ shortcut: Shortcut, key: String) {
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadShortcut(key: String) -> Shortcut? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) else {
            return nil
        }
        return shortcut
    }
    
    private func convertToHotkeyModifiers(_ modifiers: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        var result = NSEvent.ModifierFlags()
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        return result
    }
    
    private static let functionKeys: Set<Key> = [
        Key.f1, Key.f2, Key.f3, Key.f4, Key.f5, Key.f6,
        Key.f7, Key.f8, Key.f9, Key.f10, Key.f11, Key.f12
    ]
    
    deinit {
        mainHotKey = nil
        switchLeftHotKey = nil
        switchRightHotKey = nil
        removeKeyListener()
    }
}

// Just a simple wrapper for a key + modifiers combo
struct Shortcut: Equatable, Codable {
    let key: Key?
    let modifiers: NSEvent.ModifierFlags
    
    // For backward compatibility with the UI
    var keyString: String {
        key?.description ?? ""
    }
    
    enum CodingKeys: String, CodingKey {
        case key
        case modifiers
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Store key as its description string
        try container.encode(key?.description, forKey: .key)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let keyString = try container.decodeIfPresent(String.self, forKey: .key) {
            self.key = Shortcut.keyFromDescription(keyString)
        } else {
            self.key = nil
        }

        let modRaw = try container.decode(UInt.self, forKey: .modifiers)
        self.modifiers = NSEvent.ModifierFlags(rawValue: modRaw)
    }

    init(key: Key?, modifiers: NSEvent.ModifierFlags) {
        self.key = key
        self.modifiers = modifiers.intersection([.command, .option, .control, .shift])
    }

    static func == (lhs: Shortcut, rhs: Shortcut) -> Bool {
        lhs.key == rhs.key && lhs.modifiers == rhs.modifiers
    }

    var description: String {
        if key == nil { return NSLocalizedString("Settings.Shortcuts.Unassgined", comment: "Unassigned") }

        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.control) { parts.append("^") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if let key = key {
            parts.append(keyDisplayName(for: key))
        }
        return parts.joined()
    }
    
    // Convert to HotKey library Key type
    var hotkeyKey: Key? {
        return key
    }
    
    // Convert to HotKey library modifiers
    var hotkeyModifiers: NSEvent.ModifierFlags? {
        return modifiers
    }
    
    // Helper to get display name for Key
    private func keyDisplayName(for key: Key) -> String {
        switch key {
        case Key.a: return "A"
        case Key.b: return "B"
        case Key.c: return "C"
        case Key.d: return "D"
        case Key.e: return "E"
        case Key.f: return "F"
        case Key.g: return "G"
        case Key.h: return "H"
        case Key.i: return "I"
        case Key.j: return "J"
        case Key.k: return "K"
        case Key.l: return "L"
        case Key.m: return "M"
        case Key.n: return "N"
        case Key.o: return "O"
        case Key.p: return "P"
        case Key.q: return "Q"
        case Key.r: return "R"
        case Key.s: return "S"
        case Key.t: return "T"
        case Key.u: return "U"
        case Key.v: return "V"
        case Key.w: return "W"
        case Key.x: return "X"
        case Key.y: return "Y"
        case Key.z: return "Z"
        case Key.zero: return "0"
        case Key.one: return "1"
        case Key.two: return "2"
        case Key.three: return "3"
        case Key.four: return "4"
        case Key.five: return "5"
        case Key.six: return "6"
        case Key.seven: return "7"
        case Key.eight: return "8"
        case Key.nine: return "9"
        case Key.f1: return "F1"
        case Key.f2: return "F2"
        case Key.f3: return "F3"
        case Key.f4: return "F4"
        case Key.f5: return "F5"
        case Key.f6: return "F6"
        case Key.f7: return "F7"
        case Key.f8: return "F8"
        case Key.f9: return "F9"
        case Key.f10: return "F10"
        case Key.f11: return "F11"
        case Key.f12: return "F12"
        case Key.leftArrow: return "←"
        case Key.rightArrow: return "→"
        case Key.downArrow: return "↓"
        case Key.upArrow: return "↑"
        case Key.escape: return "Escape"
        case Key.space: return "␣"
        case Key.delete: return "⌫"
        case Key.forwardDelete: return "⌦"
        case Key.return: return "⏎"
        case Key.tab: return "⇥"
        default: return key.description
        }
    }

    // Convert NSEvent keyCode to HotKey Key type
    static func keyFromEvent(_ event: NSEvent) -> Key? {
        switch event.keyCode {
        case 0x00: return Key.a
        case 0x0B: return Key.b
        case 0x08: return Key.c
        case 0x02: return Key.d
        case 0x0E: return Key.e
        case 0x03: return Key.f
        case 0x05: return Key.g
        case 0x04: return Key.h
        case 0x22: return Key.i
        case 0x26: return Key.j
        case 0x28: return Key.k
        case 0x25: return Key.l
        case 0x2E: return Key.m
        case 0x2D: return Key.n
        case 0x1F: return Key.o
        case 0x23: return Key.p
        case 0x0C: return Key.q
        case 0x0F: return Key.r
        case 0x01: return Key.s
        case 0x11: return Key.t
        case 0x20: return Key.u
        case 0x09: return Key.v
        case 0x0D: return Key.w
        case 0x07: return Key.x
        case 0x10: return Key.y
        case 0x06: return Key.z
        case 0x1D: return Key.zero
        case 0x12: return Key.one
        case 0x13: return Key.two
        case 0x14: return Key.three
        case 0x15: return Key.four
        case 0x17: return Key.five
        case 0x16: return Key.six
        case 0x1A: return Key.seven
        case 0x1C: return Key.eight
        case 0x19: return Key.nine
        case 0x35: return Key.escape
        case 0x7A: return Key.f1
        case 0x78: return Key.f2
        case 0x63: return Key.f3
        case 0x76: return Key.f4
        case 0x60: return Key.f5
        case 0x61: return Key.f6
        case 0x62: return Key.f7
        case 0x64: return Key.f8
        case 0x65: return Key.f9
        case 0x6D: return Key.f10
        case 0x67: return Key.f11
        case 0x6F: return Key.f12
        case 0x7B: return Key.leftArrow
        case 0x7C: return Key.rightArrow
        case 0x7D: return Key.downArrow
        case 0x7E: return Key.upArrow
        case 0x31: return Key.space
        case 0x33: return Key.delete
        case 0x75: return Key.forwardDelete
        case 0x24: return Key.return
        case 0x30: return Key.tab
        default: return nil
        }
    }
    
    // Convert NSEvent to readable key name (for UI display)
    static func keyName(from event: NSEvent) -> String {
        switch event.keyCode {
        case 0x35: return "Escape"
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        case 0x7B: return "←"
        case 0x7C: return "→"
        case 0x7D: return "↓"
        case 0x7E: return "↑"
        case 0x31: return " "
        case 0x33: return "⌫"
        case 0x75: return "⌦"
        case 0x24: return "⏎"
        case 0x30: return "⇥"
        default:
            // For normal keys, use charactersIgnoringModifiers
            return event.charactersIgnoringModifiers?.uppercased() ?? ""
        }
    }

    // Helper to convert a key description string back to a Key
    static func keyFromDescription(_ description: String) -> Key? {
        // Try to match by description
        let allKeys: [Key] = [
            .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m, .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z,
            .zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine,
            .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12,
            .leftArrow, .rightArrow, .downArrow, .upArrow, .escape, .space, .delete, .forwardDelete, .return, .tab
        ]
        return allKeys.first(where: { $0.description == description })
    }
}

// Notification
extension Notification.Name {
    static let hotkeyTriggered = Notification.Name("HotkeyTriggered")
}
