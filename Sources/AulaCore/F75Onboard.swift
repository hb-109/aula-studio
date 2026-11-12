import Foundation

/// Settings the AULA F75 Pro (SinoWealth 258a:010c) stores on the keyboard.
///
/// Decoded from a recording of AULA's own Windows driver (OemDrv.exe) talking to an
/// F75 Pro, made with the hid.dll logger in tools/hidlogger. Every report is HID
/// feature report 0x06, 520 bytes, on the vendor interface (usage page 0xFF00):
///
///     06 <command> <page> 00 01 00 <payload length, LE> <payload…>
///
/// Commands seen:
///   82  model query (payload 06; reply byte 13 = 0xCD for the F75)
///   84  read the 128-byte settings block (reply carries the block)
///   04  write the 128-byte settings block
///   0a  write the 512-byte colour palette (AULA writes it before every 04)
///   03  write one 512-byte key-assignment page (0 Default, 1 FN1, 2 FN2, 3 Tap)
///   05  write a macro
///
/// Like AULA's driver, AULA Studio reads the settings block, changes only the
/// bytes it understands, and writes the rest back untouched. Tables that have no
/// read command (palette, key pages) start from the factory tables AULA sends,
/// copied byte for byte from the recording (F75Captured).
public enum F75Onboard {
    public static let reportID: UInt8 = 0x06
    public static let reportSize = 520
    public static let settingsLength = 128
    public static let tableLength = 512
    public static let keymapPages = 4

    public static func report(_ command: UInt8, page: UInt8 = 0, length: Int, payload: [UInt8] = []) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: reportSize)
        r[0] = reportID; r[1] = command; r[2] = page; r[4] = 0x01
        r[6] = UInt8(length & 0xFF); r[7] = UInt8(length >> 8)
        r.replaceSubrange(8..<8 + payload.count, with: payload)
        return r
    }

    public static let modelQuery: [UInt8] = { var r = report(0x82, length: 0); r[2] = 0x01; r[6] = 0x06; return r }()
    public static let readSettingsRequest = report(0x84, length: settingsLength)

    public static func settingsWrite(_ block: [UInt8]) -> [UInt8] {
        precondition(block.count == settingsLength)
        return report(0x04, length: settingsLength, payload: block)
    }

    public static func paletteWrite(_ table: [UInt8]) -> [UInt8] {
        precondition(table.count == tableLength)
        return report(0x0A, length: tableLength, payload: table)
    }

    public static func keymapWrite(page: Int, _ table: [UInt8]) -> [UInt8] {
        precondition(table.count == tableLength && (0..<keymapPages).contains(page))
        return report(0x03, page: UInt8(page), length: tableLength, payload: table)
    }

    /// The settings block from a 84 reply (payload bytes 8...135).
    public static func settingsBlock(fromReply reply: [UInt8]) throws -> [UInt8] {
        guard reply.count >= 8 + settingsLength, reply[0] == reportID, reply[1] == 0x84 else {
            throw ProtocolError.notAcknowledged("the settings read (84)")
        }
        let block = Array(reply[8..<8 + settingsLength])
        // Every block AULA's driver read ended with the 5a a5 trailer.
        guard block[126] == 0x5A, block[127] == 0xA5 else { throw ProtocolError.ioFailure("The settings block from the keyboard looks wrong (no 5a a5 trailer).") }
        return block
    }

    // MARK: Effects

    public struct Effect: Identifiable, Hashable, Sendable {
        public let id: Int
        public let name: String
        public let hasSpeed: Bool
        public let hasBrightness: Bool
        public let hasRainbow: Bool
        public let hasColour: Bool
    }

    /// The built-in effects, from the [OPT] LedOpt lines in AULA's F75 config
    /// ("hw effect speed light direct random color") and the driver's names
    /// (tc_kb_led1-18). Self-define (hw 21, per-key colours) isn't decoded yet.
    public static let effects: [Effect] = [
        Effect(id: 1, name: "Fixed On", hasSpeed: false, hasBrightness: true, hasRainbow: true, hasColour: true),
        Effect(id: 2, name: "Respire", hasSpeed: true, hasBrightness: true, hasRainbow: true, hasColour: true),
        Effect(id: 3, name: "Rainbow", hasSpeed: true, hasBrightness: true, hasRainbow: false, hasColour: false),
        Effect(id: 4, name: "Flash Away", hasSpeed: true, hasBrightness: true, hasRainbow: true, hasColour: true),
        Effect(id: 5, name: "Raindrops", hasSpeed: true, hasBrightness: true, hasRainbow: true, hasColour: true),
        Effect(id: 6, name: "Rainbow Wheel", hasSpeed: true, hasBrightness: true, hasRainbow: true, hasColour: true),
        Effect(id: 7, name: "Ripples Shining", hasSpeed: true, hasBrightness: true, hasRainbow: true, hasColour: true),
        Effect(id: 8, name: "Stars Twinkle", hasSpeed: true, hasBrightness: true, hasRainbow: true, hasColour: true),
        Effect(id: 9, name: "Shadow Disappear", hasSpeed: true, hasBrightness: true, hasRainbow: true, hasColour: true),
        Effect(id: 10, name: "Retro Snake", hasSpeed: true, hasBrightness: true, hasRainbow: true, hasColour: true),
        Effect(id: 11, name: "Neon Stream", hasSpeed: true, hasBrightness: true, hasRainbow: true, hasColour: true),
        Effect(id: 12, name: "Reaction", hasSpeed: true, hasBrightness: true, hasRainbow: true, hasColour: true),
        Effect(id: 13, name: "Sine Wave", hasSpeed: true, hasBrightness: true, hasRainbow: true, hasColour: true),
        Effect(id: 14, name: "Retinue Scanning", hasSpeed: true, hasBrightness: true, hasRainbow: true, hasColour: true),
        Effect(id: 15, name: "Rotating Windmill", hasSpeed: true, hasBrightness: true, hasRainbow: false, hasColour: false),
        Effect(id: 16, name: "Colorful Waterfall", hasSpeed: true, hasBrightness: true, hasRainbow: false, hasColour: false),
        Effect(id: 17, name: "Blossoming", hasSpeed: true, hasBrightness: true, hasRainbow: false, hasColour: false),
        Effect(id: 18, name: "Rotating Storm", hasSpeed: true, hasBrightness: true, hasRainbow: true, hasColour: true),
    ]

    public static let maxBrightness = 9   // Light=0..9 in AULA's config
    public static let maxSpeed = 4        // Speed=0..4

    /// Sleep choices AULA's driver offers (SleepUI, seconds) and what it stores (SleepHW, 30 s units).
    public static let sleepSeconds = [60, 90, 120, 180, 240, 300, 600, 900, 1200]
    public static func sleepUnits(seconds: Int) -> UInt8 { UInt8(clamping: seconds / 30) }

    // MARK: Settings block layout

    static let effectOffset = 10
    static let sleepOffset = 24
    static let effectPairsOffset = 56
    /// Low nibble value meaning "rainbow / colourful" instead of a palette colour.
    public static let rainbowSlot: UInt8 = 7

    public struct Settings: Equatable, Sendable {
        public var effect: Int
        public var brightness: Int
        public var speed: Int
        /// Palette slot 0-6, or 7 for rainbow.
        public var colourSlot: Int
        public var sleepUnits: Int
    }

    public static func decode(_ block: [UInt8]) -> Settings {
        let e = Int(block[effectOffset])
        let pair = effectPairsOffset + 2 * min(e, 35)
        return Settings(effect: e, brightness: Int(block[pair]), speed: Int(block[pair + 1] >> 4),
                        colourSlot: Int(block[pair + 1] & 0x0F), sleepUnits: Int(block[sleepOffset]))
    }

    /// The palette slot (low nibble) currently stored for an effect.
    public static func colourSlot(in block: [UInt8], effect: Int) -> Int {
        Int(block[effectPairsOffset + 2 * effect + 1] & 0x0F)
    }

    /// Returns `block` with the effect, its brightness/speed/colour slot and the
    /// sleep timer changed. Every other byte is left as the keyboard reported it.
    public static func apply(_ s: Settings, to block: [UInt8]) throws -> [UInt8] {
        guard block.count == settingsLength else { throw ProtocolError.outOfRange("settings block size \(block.count)") }
        guard effects.contains(where: { $0.id == s.effect }) else { throw ProtocolError.outOfRange("effect \(s.effect)") }
        guard (0...maxBrightness).contains(s.brightness), (0...maxSpeed).contains(s.speed),
              (0...Int(rainbowSlot)).contains(s.colourSlot), (2...40).contains(s.sleepUnits) else {
            throw ProtocolError.outOfRange("F75 settings \(s)")
        }
        var b = block
        b[effectOffset] = UInt8(s.effect)
        b[sleepOffset] = UInt8(s.sleepUnits)
        let pair = effectPairsOffset + 2 * s.effect
        b[pair] = UInt8(s.brightness)
        b[pair + 1] = UInt8(s.speed << 4 | s.colourSlot)
        return b
    }

    // MARK: Palette

    /// Each effect has 7 RGB colours (21 bytes) at 21 × effect.
    public static func setPaletteColour(_ table: [UInt8], effect: Int, slot: Int, colour: RGB) -> [UInt8] {
        var t = table
        let o = 21 * effect + 3 * slot
        t[o] = colour.r; t[o + 1] = colour.g; t[o + 2] = colour.b
        return t
    }

    // MARK: Key assignments

    /// Encodes a remap for the F75 Pro's key pages. Only the kinds recorded from
    /// AULA's driver are supported; nil means "not supported on the F75 yet".
    public static func entry(_ a: KeyAction) -> [UInt8]? {
        switch a.kind {
        case .key:
            if let bit = HIDKeys.modifierBits[a.key] { return [0x00, UInt8((bit | a.mods) & 0xFF), 0x00, 0x00] }
            return [0x00, UInt8(a.mods & 0xFF), 0x00, UInt8(a.key & 0xFF)]
        case .consumer:
            return [0x02, 0x00, UInt8((a.code >> 8) & 0xFF), UInt8(a.code & 0xFF)]
        default:
            return nil
        }
    }

    public static func supports(_ kind: KeyAction.Kind) -> Bool { [.default, .key, .consumer].contains(kind) }

    /// The four key-assignment pages: the factory tables with `base` applied to the
    /// Default layer and `fn` to FN1, keyed by key slot (the key's LED index).
    public static func keymapPages(base: [Int: KeyAction], fn: [Int: KeyAction]) throws -> [[UInt8]] {
        var pages = F75Captured.factoryKeymapPages
        for (layer, table) in [(0, base), (1, fn)] {
            for (slot, action) in table where action.kind != .default {
                // Slot 127 holds the page trailer.
                guard (0..<127).contains(slot) else { throw ProtocolError.outOfRange("key slot \(slot)") }
                guard let e = entry(action) else { throw ProtocolError.outOfRange("\(action.describe) isn't supported on the F75 Pro yet") }
                pages[layer].replaceSubrange(slot * 4..<slot * 4 + 4, with: e)
            }
        }
        return pages
    }
}
