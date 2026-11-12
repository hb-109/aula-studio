/// USB HID usage tables used for remapping and macros.
public enum HIDKeys {
    public struct Entry: Identifiable, Sendable { public let name: String; public let usage: Int; public var id: Int { usage } }

    /// Keyboard page (0x07), in the order the remap picker lists them.
    public static let keys: [Entry] = {
        var list: [Entry] = []
        for i in 0..<26 { list.append(Entry(name: String(UnicodeScalar(UInt8(65 + i))), usage: 0x04 + i)) }
        for n in 1...9 { list.append(Entry(name: "\(n)", usage: 0x1E + n - 1)) }
        list.append(Entry(name: "0", usage: 0x27))
        let named: [(String, Int)] = [
            ("Enter", 0x28), ("Esc", 0x29), ("Backspace", 0x2A), ("Tab", 0x2B), ("Space", 0x2C),
            ("-", 0x2D), ("=", 0x2E), ("[", 0x2F), ("]", 0x30), ("\\", 0x31), ("Non-US #", 0x32),
            (";", 0x33), ("'", 0x34), ("`", 0x35), (",", 0x36), (".", 0x37), ("/", 0x38), ("Caps Lock", 0x39),
        ]
        list += named.map { Entry(name: $0.0, usage: $0.1) }
        for n in 1...12 { list.append(Entry(name: "F\(n)", usage: 0x3A + n - 1)) }
        let more: [(String, Int)] = [
            ("Print Screen", 0x46), ("Scroll Lock", 0x47), ("Pause", 0x48), ("Insert", 0x49), ("Home", 0x4A),
            ("Page Up", 0x4B), ("Delete", 0x4C), ("End", 0x4D), ("Page Down", 0x4E), ("Right", 0x4F),
            ("Left", 0x50), ("Down", 0x51), ("Up", 0x52), ("Num Lock", 0x53), ("Keypad /", 0x54),
            ("Keypad *", 0x55), ("Keypad -", 0x56), ("Keypad +", 0x57), ("Keypad Enter", 0x58),
        ]
        list += more.map { Entry(name: $0.0, usage: $0.1) }
        for n in 1...9 { list.append(Entry(name: "Keypad \(n)", usage: 0x59 + n - 1)) }
        list += [Entry(name: "Keypad 0", usage: 0x62), Entry(name: "Keypad .", usage: 0x63),
                 Entry(name: "Non-US \\", usage: 0x64), Entry(name: "Menu", usage: 0x65)]
        for n in 13...24 { list.append(Entry(name: "F\(n)", usage: 0x68 + n - 13)) }
        let mods: [(String, Int)] = [
            ("Left Ctrl", 0xE0), ("Left Shift", 0xE1), ("Left Alt / Option", 0xE2), ("Left Win / Cmd", 0xE3),
            ("Right Ctrl", 0xE4), ("Right Shift", 0xE5), ("Right Alt / Option", 0xE6), ("Right Win / Cmd", 0xE7),
        ]
        list += mods.map { Entry(name: $0.0, usage: $0.1) }
        return list
    }()

    public static func name(for usage: Int) -> String {
        keys.first { $0.usage == usage }?.name ?? String(format: "0x%02X", usage)
    }

    /// Modifier usages and the bit each one sets in a remap slot.
    public static let modifierBits: [Int: Int] = Dictionary(uniqueKeysWithValues: (0..<8).map { (0xE0 + $0, 1 << $0) })

    public struct Consumer: Identifiable, Sendable { public let name: String; public let code: Int; public var id: Int { code } }
    /// Consumer page (0x0C) usages that fit the firmware's one-byte remap slot.
    public static let consumer: [Consumer] = [
        Consumer(name: "Play / Pause", code: 0xCD), Consumer(name: "Stop", code: 0xB7),
        Consumer(name: "Previous track", code: 0xB6), Consumer(name: "Next track", code: 0xB5),
        Consumer(name: "Volume up", code: 0xE9), Consumer(name: "Volume down", code: 0xEA),
        Consumer(name: "Mute", code: 0xE2),
    ]

    public struct Mouse: Identifiable, Sendable { public let name: String; public let bytes: [UInt8]; public var id: String { name } }
    /// Remap type 0x07: (button mask, wheel, reserved).
    public static let mouse: [Mouse] = [
        Mouse(name: "Left click", bytes: [0x01, 0x00, 0x00]), Mouse(name: "Right click", bytes: [0x02, 0x00, 0x00]),
        Mouse(name: "Middle click", bytes: [0x04, 0x00, 0x00]), Mouse(name: "Scroll up", bytes: [0x00, 0x01, 0x00]),
        Mouse(name: "Scroll down", bytes: [0x00, 0xFF, 0x00]),
    ]

    public struct Special: Identifiable, Sendable { public let name: String; public let code: Int; public var id: Int { code } }
    /// Remap type 0x01 special functions, as (param1 << 8 | param2).
    public static let special: [Special] = [
        Special(name: "Caps Lock", code: 0x0102), Special(name: "Num Lock", code: 0x0101),
        Special(name: "Scroll Lock", code: 0x0104), Special(name: "Calculator", code: 0x0301),
    ]

    /// macOS virtual key code (NSEvent.keyCode) to HID usage, for recording macros
    /// and for "press a key" capture in the remap editor.
    public static let macKeyCodeToHID: [UInt16: Int] = [
        0: 0x04, 11: 0x05, 8: 0x06, 2: 0x07, 14: 0x08, 3: 0x09, 5: 0x0A, 4: 0x0B, 34: 0x0C, 38: 0x0D,
        40: 0x0E, 37: 0x0F, 46: 0x10, 45: 0x11, 31: 0x12, 35: 0x13, 12: 0x14, 15: 0x15, 1: 0x16, 17: 0x17,
        32: 0x18, 9: 0x19, 13: 0x1A, 7: 0x1B, 16: 0x1C, 6: 0x1D,
        18: 0x1E, 19: 0x1F, 20: 0x20, 21: 0x21, 23: 0x22, 22: 0x23, 26: 0x24, 28: 0x25, 25: 0x26, 29: 0x27,
        36: 0x28, 53: 0x29, 51: 0x2A, 48: 0x2B, 49: 0x2C, 27: 0x2D, 24: 0x2E, 33: 0x2F, 30: 0x30, 42: 0x31,
        41: 0x33, 39: 0x34, 50: 0x35, 43: 0x36, 47: 0x37, 44: 0x38, 57: 0x39,
        122: 0x3A, 120: 0x3B, 99: 0x3C, 118: 0x3D, 96: 0x3E, 97: 0x3F, 98: 0x40, 100: 0x41, 101: 0x42,
        109: 0x43, 103: 0x44, 111: 0x45, 114: 0x49, 115: 0x4A, 116: 0x4B, 117: 0x4C, 119: 0x4D, 121: 0x4E,
        124: 0x4F, 123: 0x50, 125: 0x51, 126: 0x52, 10: 0x64, 110: 0x65,
        59: 0xE0, 56: 0xE1, 58: 0xE2, 55: 0xE3, 62: 0xE4, 60: 0xE5, 61: 0xE6, 54: 0xE7,
    ]
}
