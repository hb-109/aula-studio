// Hardware-free checks for AulaCore: `swift run SelfCheck`.
//
// The S75 Pro can't be tested here, so these checks pin its protocol encoders to
// the expected bytes in thibaultmiclo/aula-driver's test suite (tests/test_protocol.py,
// written against the EA75MAX, the S75 Pro's identical twin), and check the
// transaction order, layouts and the screen-flash safety limits.

import AulaCore
import CoreGraphics
import Foundation

var failures = 0
var passes = 0

func check(_ condition: @autoclosure () throws -> Bool, _ name: String) {
    do {
        if try condition() { passes += 1 } else { failures += 1; print("FAIL  \(name)") }
    } catch {
        failures += 1; print("FAIL  \(name): threw \(error)")
    }
}

func expectThrows(_ name: String, _ body: () throws -> Void) {
    do { try body(); failures += 1; print("FAIL  \(name): did not throw") } catch { passes += 1 }
}

func hex(_ b: some Sequence<UInt8>) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }

func bytes(_ s: String) -> [UInt8] { s.split(separator: " ").map { UInt8($0, radix: 16)! } }

func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
    var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
    return Calendar.current.date(from: c)!
}

// MARK: Lighting (reference: LightingTest)

let red = S75Protocol.lightingPacket(effect: .staticOn, colour: RGB(r: 255, g: 0, b: 0), rainbow: false,
                                     brightness: 5, speed: 3, direction: 0)
check(hex(red.prefix(16)) == "01 ff 00 00 00 00 00 00 00 05 03 00 00 00 aa 55", "static red packet")
check(red.count == 64, "lighting packet is 64 bytes")
let off = S75Protocol.lightingPacket(effect: .off, colour: RGB(r: 1, g: 2, b: 3), rainbow: true,
                                     brightness: 5, speed: 3, direction: 1)
check(off.prefix(14) == [UInt8](repeating: 0, count: 14)[...], "off ignores parameters")
check(Array(off[14...15]) == [0xAA, 0x55], "off keeps trailer")
check(S75Protocol.lightingPacket(effect: .rolling, colour: .white, rainbow: false, brightness: 9, speed: -2, direction: 3)[9...11]
      == [5, 0, 1], "brightness/speed clamp to 0-5, direction is one bit")
check(HardwareEffect.allCases.count == 20 && HardwareEffect.shuttle.rawValue == 19, "20 firmware effects numbered 0-19")

do {
    let t = try S75Protocol.colourTable([1: RGB(r: 255, g: 0, b: 0), 56: RGB(r: 0, g: 255, b: 0)])
    check(t.count == 576, "colour table is 576 bytes")
    check(Array(t[4..<8]) == [1, 255, 0, 0], "colour slot 1")
    check(Array(t[224..<228]) == [56, 0, 255, 0], "colour slot 56")
    check(Array(t.suffix(2)) == [0xAA, 0x55], "colour table trailer")
} catch { check(false, "colour table threw \(error)") }
expectThrows("colour index 0 rejected") { _ = try S75Protocol.colourTable([0: .white]) }
expectThrows("colour index 143 rejected") { _ = try S75Protocol.colourTable([143: .white]) }

// MARK: Remap (reference: RemapTest)

check(S75Protocol.slot(.key(0xE0)) == [2, 1, 0, 0], "remap to LCtrl")
check(S75Protocol.slot(.key(0x06, mods: 1)) == [2, 1, 6, 0], "remap to Ctrl+C")
check(S75Protocol.slot(.disable) == [5, 3, 0, 0], "disable")
check(S75Protocol.slot(.consumer(0xCD)) == [3, 0xCD, 0, 0], "media play/pause")
check(S75Protocol.slot(.special(0x0102)) == [1, 1, 2, 0], "special caps lock")
check(S75Protocol.slot(.macro(2, mode: .repeatCount, repeatCount: 5)) == [6, 2, 1, 5], "macro slot")
check(S75Protocol.slot(.mouse([0, 0xFF, 0])) == [7, 0, 0xFF, 0], "mouse scroll down")
check(S75Protocol.slot(.default) == [0, 0, 0, 0], "default")
do {
    let t = try S75Protocol.remapTable([55: .key(0xE0)])
    check(Array(t[220..<224]) == [2, 1, 0, 0], "remap table slot 55")
    check(Array(t.suffix(2)) == [0xAA, 0x55] && t.count == 576, "remap table trailer and size")
} catch { check(false, "remap table threw \(error)") }

// MARK: Function settings (reference: FunctionTest)

var fs = DeviceSettings()
fs.disableWin = true; fs.fnToggle = true; fs.sleep = 2; fs.response = 4
let fp = S75Protocol.functionPacket(fs)
check(hex(fp.prefix(9)) == "00 01 01 00 00 01 02 00 04", "function packet layout")
check(Array(fp[62...63]) == [0xAA, 0x55], "function packet trailer")

// MARK: Macros (reference: MacroTest)

do {
    let m = Macro(name: "a", events: [MacroEvent(kind: .keyDown, code: 0x04, delay: 5),
                                      MacroEvent(kind: .keyUp, code: 0x04, delay: 300)])
    let buf = try S75Protocol.macroBuffer([m, Macro(name: "empty")])
    check(Array(buf[0..<4]) == [0x90, 0x01, 0, 0], "macro 1 offset 400")
    check(Array(buf[4..<8]) == [0xFF, 0xFF, 0xFF, 0xFF], "empty macro marker")
    check(Array(buf[400..<402]) == [4, 0], "record count 4")
    check(hex(buf[408..<424]) == "00 00 04 b0 0a 00 00 50 00 00 04 30 2c 01 00 50", "macro records (delay clamped to 10)")
    check(buf.count == 8 * 64, "macro buffer is 8 reports")
    check(Array(buf.suffix(2)) == [0xAA, 0x55], "macro buffer trailer")

    let five = Macro(name: "x", events: Array(repeating: MacroEvent(kind: .keyDown, code: 4), count: 5))
    check(try S75Protocol.macroBuffer([five]).count == (448 / 64 + 1) * 64, "exact multiple gets one spare report")
} catch { check(false, "macro buffer threw \(error)") }
expectThrows("macro budget enforced") {
    _ = try S75Protocol.macroBuffer([Macro(name: "big", events: Array(repeating: MacroEvent(kind: .keyDown, code: 4), count: 400))])
}
expectThrows("101 macros rejected") {
    _ = try S75Protocol.macroBuffer(Array(repeating: Macro(name: "m"), count: 101))
}

// MARK: Clock (reference: ClockTest)

check(hex(S75Protocol.clockPacket(date(2026, 9, 19, 16, 49, 38)).prefix(11)) == "00 01 5a 1a 09 13 10 31 26 00 06",
      "clock packet (Saturday = 6)")
check(S75Protocol.clockPacket(date(2031, 1, 5, 0, 0, 59))[10] == 0, "clock Sunday = 0")

// MARK: Transaction order (reference: protocol.Keyboard)

func commands(_ steps: [S75Protocol.Step]) -> [String] {
    steps.compactMap { step in
        switch step {
        case .command(let c, _): return String(format: "04 %02x", c)
        case .finalize(let read): return read ? "f0r" : "f0"
        case .send: return "data"
        case .sendRead: return "data+read"
        case .pause: return nil
        }
    }
}

check(commands(S75Protocol.setLighting(effect: .breath, colour: .white, rainbow: false, brightness: 5, speed: 3, direction: 0))
      == ["04 18", "04 13", "data", "04 02", "f0"], "lighting transaction")
check(S75Protocol.bytes(of: S75Protocol.setLighting(effect: .breath, colour: .white, rainbow: false, brightness: 5, speed: 3, direction: 0)[1])!.prefix(9)
      == [4, 0x13, 0, 0, 0, 0, 0, 0, 1], "lighting command 04 13 with [8]=1")
do {
    let perKey = commands(try S75Protocol.setPerKey([1: .white], brightness: 4))
    check(perKey == ["04 18", "04 13", "data", "04 02", "f0", "04 18", "04 23"]
          + Array(repeating: "data", count: 8) + ["data+read", "04 02", "f0r"], "per-key transaction (9 pages)")
    let remap = try S75Protocol.setRemap([:], fnLayer: true)
    check(commands(remap).prefix(2) == ["04 18", "04 27"], "Fn-layer remap uses 04 27")
    check(commands(try S75Protocol.setRemap([:], fnLayer: false))[1] == "04 11", "base-layer remap uses 04 11")
    check(S75Protocol.bytes(of: remap[1])![8] == 9, "remap announces 9 pages")
    let macros = try S75Protocol.setMacros([Macro(name: "a", events: [MacroEvent(kind: .keyDown, code: 4)])])
    check(commands(macros).prefix(2) == ["04 19", "04 15"] && commands(macros).last == "04 02", "macro transaction")
    check(S75Protocol.bytes(of: macros[1])![8] == UInt8(try S75Protocol.macroBuffer([Macro(name: "a", events: [MacroEvent(kind: .keyDown, code: 4)])]).count / 64),
          "macro command announces its report count")
} catch { check(false, "transactions threw \(error)") }
check(commands(S75Protocol.setFunction(DeviceSettings())) == ["04 18", "04 17", "data", "04 02"], "settings transaction")
check(S75Protocol.bytes(of: S75Protocol.setFunction(DeviceSettings())[1])!.prefix(9) == [4, 0x17, 1, 0, 0, 0, 0, 0, 1],
      "settings command 04 17 with [2]=1 [8]=1")
check(commands(S75Protocol.syncClock(Date())) == ["04 18", "04 28", "data+read", "04 02"], "clock transaction")
let screenBegin = S75Protocol.screenUploadBegin(pages: 0x0123)
check(S75Protocol.bytes(of: screenBegin[1])!.prefix(10) == [4, 0x72, 1, 0, 0, 0, 0, 0, 0x23, 0x01], "screen begin 04 72, slot 1, page count LE")
check(S75Protocol.isAcknowledged([0x04, 0x13, 0x00, 0x01], code: 0x13), "ACK accepted")
check(!S75Protocol.isAcknowledged([0x04, 0x13, 0x00, 0x00], code: 0x13), "missing ACK flag rejected")
check(!S75Protocol.isAcknowledged([0x04, 0x02, 0x00, 0x01], code: 0x13), "ACK for another command rejected")

// MARK: Screen (reference: LcdTest)

func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, w: Int = ScreenEncoder.width, h: Int = ScreenEncoder.height) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

do {
    check(Array(try ScreenEncoder.rgb565(solid(1, 0, 0)).prefix(2)) == [0x00, 0xF8], "RGB565 red little-endian")
    check(Array(try ScreenEncoder.rgb565(solid(0, 0, 1)).prefix(2)) == [0x1F, 0x00], "RGB565 blue little-endian")
    let buf = try ScreenEncoder.buildBuffer(ScreenEncoder.Animation(frames: [solid(1, 0, 0)], delays: [40]))
    check(buf.count == 16 * 4096, "single frame is 16 pages")
    check(buf[0] == 1 && buf[1] == 2, "header: 1 frame, 40 ms = 2 units")
    check(Array(buf[2..<256]) == [UInt8](repeating: 0xFF, count: 254), "header padding")
    check(try ScreenEncoder.validate(buf) == 16, "validate single frame")
    check(ScreenEncoder.maxPages == 2231, "hard limit is 2231 pages")

    // A frame whose top-left pixel is red and the rest blue checks row order.
    let ctx = CGContext(data: nil, width: 135, height: 240, bitsPerComponent: 8, bytesPerRow: 540,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 135, height: 240))
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 239, width: 1, height: 1))
    let px = try ScreenEncoder.rgb565(ctx.makeImage()!)
    check(Array(px.prefix(2)) == [0x00, 0xF8] && Array(px[2...3]) == [0x1F, 0x00], "first bytes are the top-left pixel")

    let fittedWide = try ScreenEncoder.fitted(solid(1, 1, 1, w: 400, h: 100), .contain)
    check(fittedWide.width == 135 && fittedWide.height == 240, "fit produces 135x240")
} catch { check(false, "screen encoding threw \(error)") }

let tooMany = [[UInt8]](repeating: [UInt8](repeating: 0, count: ScreenEncoder.frameBytes), count: ScreenEncoder.maxFrames + 1)
expectThrows("142 frames rejected") { _ = try ScreenEncoder.buildBuffer(frames: tooMany, delays: Array(repeating: 40, count: tooMany.count)) }
expectThrows("extra page rejected") {
    var buf = try ScreenEncoder.buildBuffer(frames: [[UInt8](repeating: 0, count: ScreenEncoder.frameBytes)], delays: [40])
    buf += [UInt8](repeating: 0xFF, count: 4096)
    try ScreenEncoder.validate(buf)
}
expectThrows("forged oversized buffer rejected") {
    var forged = [UInt8](repeating: 0, count: (ScreenEncoder.maxPages + 1) * 4096)
    forged[0] = UInt8(ScreenEncoder.maxFrames)
    try ScreenEncoder.validate(forged)
}
expectThrows("zero frames rejected") { try ScreenEncoder.validate([UInt8](repeating: 0, count: 4096)) }
let (tf, td) = ScreenEncoder.trim(Array(0..<300), Array(repeating: 40, count: 300), limit: 141)
check(tf.count == 141 && td.reduce(0, +) == 300 * 40, "trim keeps 141 frames and total duration")

// MARK: Layouts

let s75 = KeyboardModel.s75Pro.layout.keys
check(s75.count == 80, "S75 Pro has 80 keys")
check(Set(s75.map(\.remapIndex)).count == 80 && s75.allSatisfy { (1..<143).contains($0.remapIndex) }, "S75 remap slots unique and in range")
check(Set(s75.map(\.led)).count == 80 && s75.allSatisfy { (1..<143).contains($0.led) }, "S75 LED slots unique and in range")
check(s75.first { $0.label == "Esc" }?.remapIndex == 1 && s75.first { $0.label == "Fn" }?.fnLocked == true, "S75 Esc slot 1, Fn locked")
for variant in LayoutVariant.allCases {
    let f75 = KeyboardModel.f75Pro.layout.keys(for: variant)
    check(Set(f75.map(\.led)).count == f75.count && f75.allSatisfy { (0..<128).contains($0.led) }, "F75 \(variant) LEDs unique, under 128")
}

// MARK: Profiles round-trip

var profile = Profile(name: "Test", model: .s75Pro)
profile.remapBase[5] = .macro(0, mode: .toggle)
profile.macros = [Macro(name: "m", events: [MacroEvent(kind: .keyDown, code: 4, delay: 50)])]
profile.lighting.paint = [3: RGB(r: 1, g: 2, b: 3)]
do {
    let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
    check(decoded == profile, "profile JSON round-trip")
} catch { check(false, "profile round-trip threw \(error)") }


// MARK: Executor against a simulated keyboard

do {
    let sim = SimulatedS75()
    let exec = S75Executor(transport: sim)
    exec.delayScale = 0
    try exec.run(try S75Protocol.setPerKey([1: .white, 94: RGB(r: 1, g: 2, b: 3)], brightness: 5))
    check(sim.sent.count == 5 + 2 + 9 + 2, "per-key sends 18 reports")
    check(sim.sent.allSatisfy { $0.count == 64 }, "every config report is 64 bytes")
    check(Array(sim.sent[7][4..<8]) == [1, 255, 255, 255], "first table page carries slot 1")
    let shot = try ScreenEncoder.buildBuffer(frames: [[UInt8](repeating: 0, count: ScreenEncoder.frameBytes)], delays: [100])
    check(try exec.uploadScreen(shot) == 16 && sim.screenPages == 16, "screen upload sends and counts 16 pages")
    expectThrows("executor refuses an invalid screen buffer") { try exec.uploadScreen([UInt8](repeating: 0xFF, count: 4096)) }
    check(sim.screenPages == 16, "no page written for an invalid buffer")
} catch { check(false, "executor threw \(error)") }

final class NoAck: S75Transport {
    func setFeature(_ report: [UInt8]) throws {}
    func getFeature() throws -> [UInt8] { [UInt8](repeating: 0, count: 64) }
    func writeScreenPage(_ page: [UInt8]) throws {}
    func waitScreenAck(timeout: TimeInterval) -> Bool { false }
}
let strict = S75Executor(transport: NoAck())
strict.delayScale = 0
expectThrows("executor stops when the keyboard doesn't acknowledge") {
    try strict.run(S75Protocol.setFunction(DeviceSettings()))
}


// MARK: F75 Pro onboard protocol (reference: recording of AULA's own driver)

check(F75Onboard.modelQuery.prefix(8) == [0x06, 0x82, 0x01, 0x00, 0x01, 0x00, 0x06, 0x00] && F75Onboard.modelQuery.count == 520,
      "F75 model query matches AULA's")
check(F75Onboard.readSettingsRequest.prefix(8) == [0x06, 0x84, 0x00, 0x00, 0x01, 0x00, 0x80, 0x00]
      && F75Onboard.readSettingsRequest.dropFirst(8).allSatisfy { $0 == 0 }, "F75 settings read matches AULA's")
// Every recorded save after the first (which normalised the whole profile) changed
// only effect, brightness, speed, colour slot or sleep: rebuilding the written
// block from the read block and the decoded settings must give AULA's exact bytes.
let trips = F75Captured.settingsRoundTrips
check(trips.count == 16, "16 recorded settings saves")
for trip in trips.dropFirst() {
    let s = F75Onboard.decode(trip.written)
    check((try? F75Onboard.apply(s, to: trip.read)) == trip.written, "F75 settings save at \(trip.time) reproduced")
}
let first = F75Onboard.decode(trips[0].written)
check(first.effect == 5 && first.brightness == 9 && first.speed == 4 && first.colourSlot == 7 && first.sleepUnits == 10,
      "decode: Raindrops, brightness 9, speed 4, rainbow, sleep 5 min")
check(F75Onboard.decode(trips[9].written).colourSlot == 0, "colour change selects palette slot 0")
check(F75Onboard.settingsWrite(trips[1].written).prefix(8) == [0x06, 0x04, 0x00, 0x00, 0x01, 0x00, 0x80, 0x00], "settings write header")
check(F75Captured.factoryPalette == F75Captured.recordedPalettes[0].table, "factory palette is the first recorded palette")
check(F75Onboard.setPaletteColour(F75Captured.factoryPalette, effect: 1, slot: 0, colour: RGB(r: 0xFE, g: 0, b: 0))
      == F75Captured.recordedPalettes[10].table, "palette: Fixed On slot 0 = red reproduced")
check(F75Onboard.setPaletteColour(F75Captured.factoryPalette, effect: 1, slot: 0, colour: RGB(r: 0, g: 0, b: 0xFF))
      == F75Captured.recordedPalettes[11].table, "palette: Fixed On slot 0 = blue reproduced")
check(F75Onboard.paletteWrite(F75Captured.factoryPalette).prefix(8) == [0x06, 0x0A, 0x00, 0x00, 0x01, 0x00, 0x00, 0x02], "palette write header")
expectThrows("F75 rejects unknown effect 0") {
    var s = F75Onboard.decode(trips[1].written); s.effect = 0; _ = try F75Onboard.apply(s, to: trips[1].read)
}
expectThrows("F75 rejects brightness 10") {
    var s = F75Onboard.decode(trips[1].written); s.brightness = 10; _ = try F75Onboard.apply(s, to: trips[1].read)
}
do {
    let factory = try F75Onboard.keymapPages(base: [:], fn: [:])
    check(factory == F75Captured.factoryKeymapPages, "no remaps gives the factory key pages")
    let recorded = F75Captured.recordedKeymapPages
    check(Array(factory[1...3]) == Array(recorded[1...3]), "FN1, FN2 and Tap pages match the recording")
    let diff = (0..<512).filter { factory[0][$0] != recorded[0][$0] }
    check(diff.allSatisfy { (48..<52).contains($0) }, "Default page differs from the recording only at F1 (the macro)")
    check(Array(factory[0][36..<40]) == [0, 0, 0, 0x04], "slot 9 is A")
    check(Array(factory[0][300..<304]) == [0, 0, 0, 0x31], "slot 75 is backslash")
    check(F75Onboard.entry(.consumer(0xB6)) == Array(recorded[1][48 * 4..<48 * 4 + 4]), "media key matches AULA's FN1 entry")
    check(F75Onboard.entry(.key(0x2B, mods: 4)) == Array(recorded[1][24 * 4..<24 * 4 + 4]), "Alt+Tab matches AULA's FN1 entry")
    check(F75Onboard.entry(.key(0xE1)) == Array(factory[0][16..<20]), "Left Shift matches AULA's entry")
    let remapped = try F75Onboard.keymapPages(base: [9: .key(0x05)], fn: [8: .consumer(0xE9)])
    check(Array(remapped[0][36..<40]) == [0, 0, 0, 0x05] && Array(remapped[1][32..<36]) == [2, 0, 0, 0xE9], "A to B and FN1+Q to Volume Up encode")
    check(remapped.allSatisfy { Array($0.suffix(4)) == [0, 0, 0x5A, 0xA5] }, "every key page keeps its trailer")
    check(F75Onboard.keymapWrite(page: 1, remapped[1]).prefix(8) == [0x06, 0x03, 0x01, 0x00, 0x01, 0x00, 0x00, 0x02], "key page write header")
} catch { check(false, "F75 key pages threw \(error)") }
expectThrows("F75 refuses macros until they're decoded") { _ = try F75Onboard.keymapPages(base: [12: .macro(0)], fn: [:]) }
expectThrows("F75 refuses the trailer slot") { _ = try F75Onboard.keymapPages(base: [127: .key(4)], fn: [:]) }
let f75Keys = KeyboardModel.f75Pro.layout.keys
check(f75Keys.first { $0.label == "Esc" }?.remapIndex == 0 && f75Keys.first { $0.label == "A" }?.remapIndex == 9, "F75 key slots follow LED indexes")
check(f75Keys.filter { $0.label == "\\" }.allSatisfy { $0.remapIndex == 75 }, "F75 backslash is slot 75 on both layouts")

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
