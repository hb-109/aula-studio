import Foundation

/// Wired protocol for the AULA S75 Pro (SONiX 0c45:800a).
///
/// The S75 Pro's vendor config (reference/s75-pro/device.xml) is identical to the
/// AULA EA75MAX's: the same 80 keys, LED and remap slots, 135x240 screen and
/// 141-frame limit. Byte formats and transaction order therefore follow
/// thibaultmiclo/aula-driver (MIT), which was cross-checked against the EA75MAX
/// vendor driver and tested on that keyboard. See THIRD_PARTY_NOTICES.md.
///
/// Channels (wired mode only):
/// - configuration: 64-byte feature reports, report ID 0, vendor usage page 0xFF13
/// - screen data: 4096-byte output reports, vendor usage page 0xFF68; the keyboard
///   acknowledges each page with a 64-byte input report
///
/// The keyboard is write-only: it never reports its configuration back.
public enum S75Protocol {
    public static let reportSize = 64
    public static let tableSize = 0x240            // 144 four-byte slots, sent as 9 reports
    public static let trailer: [UInt8] = [0xAA, 0x55]
    public static let commandDelay = 0.035          // <cmd_delaytime value="35"/>
    public static let configUsagePage = 0xFF13
    public static let screenUsagePage = 0xFF68

    public static let macroBufferMax = 0xE00
    public static let macroSlots = 100
    public static let macroBudget = 2700            // vendor check: (macros + events) * 8 <= 2700

    // MARK: Encoders

    static func packet(_ head: [UInt8], _ fields: [Int: UInt8] = [:]) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: reportSize)
        p.replaceSubrange(0..<head.count, with: head)
        for (i, v) in fields { p[i] = v }
        return p
    }

    public static func lightingPacket(effect: HardwareEffect, colour: RGB, rainbow: Bool,
                                      brightness: Int, speed: Int, direction: Int) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: reportSize)
        p[0] = UInt8(effect.rawValue)
        if effect != .off {
            p[1] = colour.r; p[2] = colour.g; p[3] = colour.b
            p[8] = rainbow ? 1 : 0
            p[9] = UInt8(clamping: min(max(brightness, 0), 5))
            p[10] = UInt8(clamping: min(max(speed, 0), 5))
            p[11] = UInt8(direction & 1)
        }
        p[14] = trailer[0]; p[15] = trailer[1]
        return p
    }

    /// Custom-mode preamble: effect 0x80 with brightness.
    public static func customModePacket(brightness: Int) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: reportSize)
        p[0] = 0x80
        p[9] = UInt8(clamping: min(max(brightness, 0), 5))
        p[14] = trailer[0]; p[15] = trailer[1]
        return p
    }

    /// Per-key colours: slot = light index, bytes (index, r, g, b). Missing keys are off.
    public static func colourTable(_ colours: [Int: RGB]) throws -> [UInt8] {
        var t = [UInt8](repeating: 0, count: tableSize)
        for (index, c) in colours {
            guard index >= 1, index < (tableSize - 2) / 4 else { throw ProtocolError.outOfRange("light index \(index)") }
            t.replaceSubrange(index * 4..<index * 4 + 4, with: [UInt8(index), c.r, c.g, c.b])
        }
        t[tableSize - 2] = trailer[0]; t[tableSize - 1] = trailer[1]
        return t
    }

    public static func slot(_ a: KeyAction) -> [UInt8] {
        switch a.kind {
        case .default: return [0, 0, 0, 0]
        case .disable: return [0x05, 0x03, 0, 0]
        case .key:
            if let bit = HIDKeys.modifierBits[a.key] { return [0x02, UInt8((bit | a.mods) & 0xFF), 0, 0] }
            return [0x02, UInt8(a.mods & 0xFF), UInt8(a.key & 0xFF), 0]
        case .consumer: return [0x03, UInt8(a.code & 0xFF), 0, 0]
        case .mouse: return [0x07] + (a.mouse + [0, 0, 0]).prefix(3)
        case .macro: return [0x06, UInt8(a.macro & 0xFF), UInt8(a.macroMode.rawValue), UInt8(a.repeatCount & 0xFF)]
        case .special: return [0x01, UInt8((a.code >> 8) & 0xFF), UInt8(a.code & 0xFF), 0]
        }
    }

    public static func remapTable(_ slots: [Int: KeyAction]) throws -> [UInt8] {
        var t = [UInt8](repeating: 0, count: tableSize)
        for (index, action) in slots {
            guard index >= 1, index < (tableSize - 2) / 4 else { throw ProtocolError.outOfRange("key index \(index)") }
            t.replaceSubrange(index * 4..<index * 4 + 4, with: slot(action))
        }
        t[tableSize - 2] = trailer[0]; t[tableSize - 1] = trailer[1]
        return t
    }

    public static func functionPacket(_ s: DeviceSettings) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: reportSize)
        p[0] = 0x00; p[1] = 0x01
        p[2] = s.disableWin ? 1 : 0
        p[3] = s.disableAltF4 ? 1 : 0
        p[4] = s.disableAltTab ? 1 : 0
        p[5] = s.fnToggle ? 1 : 0
        p[6] = UInt8(clamping: min(max(s.sleep, 0), DeviceSettings.sleepOptions.count - 1))
        p[8] = UInt8(clamping: min(max(s.response, 0), DeviceSettings.responseLevels.count - 1))
        p[62] = trailer[0]; p[63] = trailer[1]
        return p
    }

    public static func macroBudgetUsed(_ macros: [Macro]) -> Int {
        (macros.count + macros.reduce(0) { $0 + $1.events.count }) * 8
    }

    /// Serialises all macros the way the vendor app does: a 100-slot index of
    /// offsets (FF FF FF FF for an empty macro), then for each macro an 8-byte
    /// header holding its record count, followed by an action record and a delay
    /// record per event. The result is padded to whole reports plus one spare.
    public static func macroBuffer(_ macros: [Macro]) throws -> [UInt8] {
        guard macros.count <= macroSlots else { throw ProtocolError.tooLarge("at most \(macroSlots) macros") }
        guard macroBudgetUsed(macros) <= macroBudget else { throw ProtocolError.tooLarge("macros too large for keyboard memory") }
        var buf = [UInt8](repeating: 0, count: macroBufferMax)
        var off = macroSlots * 4
        for (i, m) in macros.enumerated() {
            if m.events.isEmpty {
                buf.replaceSubrange(i * 4..<i * 4 + 4, with: [0xFF, 0xFF, 0xFF, 0xFF])
                continue
            }
            buf[i * 4] = UInt8(off & 0xFF); buf[i * 4 + 1] = UInt8(off >> 8)
            var records: [UInt8] = []
            for ev in m.events {
                let flag: UInt8 = [.keyDown: 0xB0, .keyUp: 0x30, .mouseDown: 0x90, .mouseUp: 0x10][ev.kind]!
                records += [0, 0, UInt8(ev.code & 0xFF), flag]
                let delay = min(max(ev.delay, 10), 0xFFFF)
                records += [UInt8(delay & 0xFF), UInt8(delay >> 8), 0, 0x50]
            }
            let count = records.count / 4
            buf[off] = UInt8(count & 0xFF); buf[off + 1] = UInt8(count >> 8)
            guard off + 8 + records.count <= macroBufferMax else { throw ProtocolError.tooLarge("macros too large for keyboard memory") }
            buf.replaceSubrange(off + 8..<off + 8 + records.count, with: records)
            off += 8 + records.count
        }
        let reports = off / reportSize + (off % reportSize == 0 ? 1 : 2)
        let size = reports * reportSize
        guard size <= macroBufferMax else { throw ProtocolError.tooLarge("macros too large for keyboard memory") }
        var out = Array(buf.prefix(size))
        out[size - 2] = trailer[0]; out[size - 1] = trailer[1]
        return out
    }

    public static func clockPacket(_ date: Date, calendar: Calendar = .current) -> [UInt8] {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        var p = [UInt8](repeating: 0, count: reportSize)
        p[1] = 0x01; p[2] = 0x5A
        p[3] = UInt8(c.year! % 100); p[4] = UInt8(c.month!); p[5] = UInt8(c.day!)
        p[6] = UInt8(c.hour!); p[7] = UInt8(c.minute!); p[8] = UInt8(c.second!)
        p[10] = UInt8(c.weekday! - 1)   // Calendar: Sunday = 1. Keyboard: Sunday = 0.
        p[62] = trailer[0]; p[63] = trailer[1]
        return p
    }

    // MARK: Transactions

    /// One step of a transaction on the configuration channel.
    public enum Step: Equatable {
        /// `04 <code>` command; the reply must echo the code and set the ACK flag.
        case command(UInt8, fields: [Int: UInt8])
        /// Data report with no reply read.
        case send([UInt8])
        /// Data report followed by a reply read (not checked for an ACK).
        case sendRead([UInt8])
        /// `04 F0` finalize, optionally reading the reply.
        case finalize(read: Bool)
        case pause(Double)
    }

    static let begin = Step.command(0x18, fields: [:])
    static let apply = Step.command(0x02, fields: [:])

    static func bulk(_ data: [UInt8], readLast: Bool) -> [Step] {
        stride(from: 0, to: data.count, by: reportSize).map { off in
            let chunk = Array(data[off..<min(off + reportSize, data.count)])
            return (readLast && off + reportSize >= data.count) ? .sendRead(chunk) : .send(chunk)
        }
    }

    public static func setLighting(effect: HardwareEffect, colour: RGB, rainbow: Bool, brightness: Int,
                                   speed: Int, direction: Int) -> [Step] {
        [begin, .command(0x13, fields: [8: 1]),
         .send(lightingPacket(effect: effect, colour: colour, rainbow: rainbow, brightness: brightness, speed: speed, direction: direction)),
         apply, .finalize(read: false)]
    }

    public static func setPerKey(_ colours: [Int: RGB], brightness: Int) throws -> [Step] {
        [begin, .command(0x13, fields: [8: 1]), .send(customModePacket(brightness: brightness)), apply, .finalize(read: false),
         begin, .command(0x23, fields: [8: 0x09])]
            + bulk(try colourTable(colours), readLast: true)
            + [apply, .finalize(read: true)]
    }

    public static func setRemap(_ slots: [Int: KeyAction], fnLayer: Bool) throws -> [Step] {
        [begin, .command(fnLayer ? 0x27 : 0x11, fields: [8: 0x09])]
            + bulk(try remapTable(slots), readLast: true)
            + [apply, .finalize(read: true)]
    }

    public static func setFunction(_ s: DeviceSettings) -> [Step] {
        [begin, .command(0x17, fields: [2: 1, 8: 1]), .send(functionPacket(s)), apply]
    }

    public static func setMacros(_ macros: [Macro]) throws -> [Step] {
        let data = try macroBuffer(macros)
        return [.command(0x19, fields: [:]), .command(0x15, fields: [8: UInt8(data.count / reportSize)]), .pause(0.03)]
            + bulk(data, readLast: true)
            + [.pause(0.03), apply]
    }

    public static func syncClock(_ date: Date) -> [Step] {
        [begin, .command(0x28, fields: [8: 1]), .sendRead(clockPacket(date)), apply]
    }

    /// Opens a screen upload of `pages` 4096-byte pages into `slot`. The pages
    /// themselves go over the screen channel, then `apply` closes the transaction.
    public static func screenUploadBegin(pages: Int, slot: Int = 1) -> [Step] {
        [begin, .command(0x72, fields: [2: UInt8(slot), 8: UInt8(pages & 0xFF), 9: UInt8((pages >> 8) & 0xFF)])]
    }

    public static let screenUploadEnd: [Step] = [apply]

    /// The bytes a command step sends.
    public static func bytes(of step: Step) -> [UInt8]? {
        switch step {
        case .command(let code, let fields): return packet([0x04, code], fields)
        case .send(let b), .sendRead(let b): return b
        case .finalize: return packet([0x04, 0xF0])
        case .pause: return nil
        }
    }

    public static func isAcknowledged(_ reply: [UInt8], code: UInt8) -> Bool {
        reply.count >= 4 && reply[1] == code && reply[3] == 0x01
    }
}

public enum ProtocolError: Error, LocalizedError, Equatable {
    case outOfRange(String)
    case tooLarge(String)
    case screenLimit(String)
    case notAcknowledged(String)
    case notConnected
    case ioFailure(String)

    public var errorDescription: String? {
        switch self {
        case .outOfRange(let s): return "Out of range: \(s)"
        case .tooLarge(let s): return s
        case .screenLimit(let s): return s
        case .notAcknowledged(let s): return "The keyboard did not acknowledge \(s)."
        case .notConnected: return "The keyboard isn't connected by USB cable."
        case .ioFailure(let s): return s
        }
    }
}
