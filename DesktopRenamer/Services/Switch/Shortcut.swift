import AppKit
import Foundation
import HotKey

struct Shortcut: Equatable, Codable {
    let key: Key?
    let modifiers: NSEvent.ModifierFlags
    
    // UI-compatible string representation.
    var keyString: String {
        key?.description ?? ""
    }
    
    enum CodingKeys: String, CodingKey {
        case key
        case modifiers
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Serialize key as a string for storage compatibility.
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

