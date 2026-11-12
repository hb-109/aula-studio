import CoreGraphics
import Foundation

// MARK: - Colours and layouts

public struct RGB: Equatable, Hashable, Codable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }
    public static let black = RGB(r: 0, g: 0, b: 0)
    public static let white = RGB(r: 255, g: 255, b: 255)
}

public enum LayoutVariant: String, CaseIterable, Codable, Sendable { case ansi, iso }

public struct KeyDef: Identifiable, Sendable {
    public let id: Int
    public let label: String
    /// Position in the vendor driver's own UI coordinates.
    public let rect: CGRect
    /// LED slot (F75 Pro: direct-mode index; S75 Pro: light_index in the per-key table).
    public let led: Int
    /// Remap-table slot (S75 Pro key_index). 0 when unknown (F75 Pro).
    public let remapIndex: Int
    public let hidUsages: [Int]
    public let variants: Set<LayoutVariant>
    /// Keys the vendor driver never lets you remap (Fn).
    public let fnLocked: Bool

    public init(id: Int, label: String, rect: CGRect, led: Int, remapIndex: Int, hidUsages: [Int],
                variants: Set<LayoutVariant>, fnLocked: Bool) {
        self.id = id; self.label = label; self.rect = rect; self.led = led; self.remapIndex = remapIndex
        self.hidUsages = hidUsages; self.variants = variants; self.fnLocked = fnLocked
    }
}

public struct KeyboardLayout: Sendable {
    public let bounds: CGRect
    public let keys: [KeyDef]
    public func keys(for variant: LayoutVariant) -> [KeyDef] { keys.filter { $0.variants.contains(variant) } }
}

// MARK: - Keyboard models

public struct Capabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// Effects computed by the app and streamed live (needs the app running).
    public static let liveEffects = Capabilities(rawValue: 1 << 0)
    /// Effects built into the keyboard's firmware, saved on the keyboard.
    public static let hardwareEffects = Capabilities(rawValue: 1 << 1)
    /// Per-key colours saved on the keyboard.
    public static let onboardPerKey = Capabilities(rawValue: 1 << 2)
    public static let remap = Capabilities(rawValue: 1 << 3)
    public static let macros = Capabilities(rawValue: 1 << 4)
    public static let deviceSettings = Capabilities(rawValue: 1 << 5)
    public static let screen = Capabilities(rawValue: 1 << 6)
    public static let clock = Capabilities(rawValue: 1 << 7)
    public static let musicRhythm = Capabilities(rawValue: 1 << 8)
    public static let layoutChoice = Capabilities(rawValue: 1 << 9)
}

public enum KeyboardModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case f75Pro, s75Pro
    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .f75Pro: return "AULA F75 Pro"
        case .s75Pro: return "AULA S75 Pro"
        }
    }

    /// Supported without having been tested on real hardware.
    public var isExperimental: Bool { self == .s75Pro }

    public var layout: KeyboardLayout {
        switch self {
        case .f75Pro: return Layouts.f75Pro
        case .s75Pro: return Layouts.s75Pro
        }
    }

    public var capabilities: Capabilities {
        switch self {
        case .f75Pro: return [.liveEffects, .musicRhythm, .layoutChoice, .remap, .deviceSettings, .hardwareEffects]
        case .s75Pro: return [.hardwareEffects, .onboardPerKey, .remap, .macros, .deviceSettings, .screen, .clock]
        }
    }

    public var usbID: (vendor: Int, product: Int) {
        switch self {
        case .f75Pro: return (0x258A, 0x010C)
        case .s75Pro: return (0x0C45, 0x800A)
        }
    }
}

// MARK: - Lighting

/// Effects the app computes and streams to keyboards with `.liveEffects`.
public enum AppEffect: String, CaseIterable, Codable, Identifiable, Sendable {
    case keyboardOwn, solid, custom, rainbow, breathing, reactive, ripple, music
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .keyboardOwn: return "Keyboard's own lighting"
        case .solid: return "Static"
        case .custom: return "Custom per-key"
        case .rainbow: return "Rainbow wave"
        case .breathing: return "Breathing"
        case .reactive: return "Reactive typing"
        case .ripple: return "Ripple"
        case .music: return "Music Rhythm"
        }
    }

    public var symbol: String {
        switch self {
        case .keyboardOwn: return "keyboard"
        case .solid: return "circle.slash"
        case .custom: return "paintbrush.pointed"
        case .rainbow: return "water.waves"
        case .breathing: return "wind"
        case .reactive: return "hand.tap"
        case .ripple: return "dot.radiowaves.left.and.right"
        case .music: return "waveform"
        }
    }

    public var usesSpeed: Bool { [.rainbow, .breathing, .reactive, .ripple].contains(self) }
    public var usesColour: Bool { [.solid, .breathing, .reactive, .ripple, .music].contains(self) }
    public var usesBaseColour: Bool { [.reactive, .ripple, .music].contains(self) }
}

/// The S75 Pro's built-in effects, numbered as its firmware expects (0-19).
public enum HardwareEffect: Int, CaseIterable, Codable, Identifiable, Sendable {
    case off = 0, staticOn, singleOn, singleOff, glittering, fluttering, colourful, breath, spectrum,
         outward, scrolling, rolling, rotating, explode, launch, ripples, flowing, pulsating, tilt, shuttle
    public var id: Int { rawValue }

    public var title: String {
        ["LED Off", "Static", "Single On", "Single Off", "Glittering", "Fluttering", "Colourful", "Breath",
         "Spectrum", "Outward", "Scrolling", "Rolling", "Rotating", "Explode", "Launch", "Ripples",
         "Flowing", "Pulsating", "Tilt", "Shuttle"][rawValue]
    }

    /// Which controls the vendor app shows for each effect (its config_func bitmask).
    public var usesBrightness: Bool { self != .off }
    public var usesSpeed: Bool { ![.off, .staticOn].contains(self) }
    public var usesColour: Bool { ![.off, .colourful, .spectrum].contains(self) }
    public var direction: DirectionAxis? {
        switch self {
        case .scrolling: return .leftRight
        case .rolling, .rotating, .flowing, .tilt: return .upDown
        default: return nil
        }
    }

    public enum DirectionAxis: Sendable { case leftRight, upDown }
}

public enum MusicStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case spectrum, rows, pulse
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .spectrum: return "Spectrum bars"
        case .rows: return "Rows by frequency"
        case .pulse: return "Beat pulse"
        }
    }
}

public enum AudioSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case system, microphone
    public var id: String { rawValue }
    public var title: String { self == .system ? "Mac sound output" : "Microphone" }
}

public struct LightingConfig: Codable, Equatable, Sendable {
    // Live (F75 Pro)
    public var appEffect: AppEffect = .rainbow
    public var layout: LayoutVariant = .ansi
    public var musicStyle: MusicStyle = .spectrum
    public var audioSource: AudioSource = .system
    public var sensitivity: Double = 0.6
    // Onboard (S75 Pro)
    public var hardwareEffect: HardwareEffect = .rolling
    /// Use the per-key colour table instead of a built-in effect.
    public var useCustomColours = false
    public var direction = 0
    public var rainbow = false
    // Shared
    public var colour = RGB(r: 0, g: 170, b: 255)
    public var baseColour = RGB(r: 10, g: 0, b: 40)
    /// 0...1. Onboard effects map this to the firmware's 0-5 levels.
    public var brightness = 1.0
    /// 0...1. Onboard effects map this to the firmware's 0-5 levels.
    public var speed = 0.6
    /// Custom colours keyed by LED slot.
    public var paint: [Int: RGB] = [:]

    public init() {}

    public var brightnessLevel: Int { Int((brightness * 5).rounded()) }
    public var speedLevel: Int { Int((speed * 5).rounded()) }
}

// MARK: - Remapping

public struct KeyAction: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case `default`, disable, key, consumer, mouse, macro, special
    }
    public enum MacroMode: Int, Codable, CaseIterable, Sendable {
        case once = 0, repeatCount, toggle, whileHeld, click
        public var title: String {
            ["Play once", "Repeat N times", "Toggle on/off", "Repeat while held", "Click"][rawValue]
        }
    }

    public var kind: Kind
    public var key = 0
    public var mods = 0
    public var code = 0
    public var mouse: [UInt8] = [0, 0, 0]
    public var macro = 0
    public var macroMode: MacroMode = .once
    public var repeatCount = 1

    public init(kind: Kind) { self.kind = kind }
    public static let `default` = KeyAction(kind: .default)
    public static let disable = KeyAction(kind: .disable)
    public static func key(_ usage: Int, mods: Int = 0) -> KeyAction {
        var a = KeyAction(kind: .key); a.key = usage; a.mods = mods; return a
    }
    public static func consumer(_ code: Int) -> KeyAction { var a = KeyAction(kind: .consumer); a.code = code; return a }
    public static func mouse(_ m: [UInt8]) -> KeyAction { var a = KeyAction(kind: .mouse); a.mouse = m; return a }
    public static func special(_ code: Int) -> KeyAction { var a = KeyAction(kind: .special); a.code = code; return a }
    public static func macro(_ index: Int, mode: MacroMode = .once, repeatCount: Int = 1) -> KeyAction {
        var a = KeyAction(kind: .macro); a.macro = index; a.macroMode = mode; a.repeatCount = repeatCount; return a
    }

    public var describe: String {
        switch kind {
        case .default: return "Default"
        case .disable: return "Disabled"
        case .key:
            let names = [(1, "Ctrl"), (2, "Shift"), (4, "Alt"), (8, "Win")].filter { mods & $0.0 != 0 }.map { $0.1 + "+" }
            return names.joined() + HIDKeys.name(for: key)
        case .consumer: return HIDKeys.consumer.first { $0.code == code }?.name ?? String(format: "Media 0x%02X", code)
        case .mouse: return HIDKeys.mouse.first { $0.bytes == mouse }?.name ?? "Mouse"
        case .macro: return "Macro #\(macro + 1)"
        case .special: return HIDKeys.special.first { $0.code == code }?.name ?? "Special"
        }
    }
}

public struct MacroEvent: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case keyDown, keyUp, mouseDown, mouseUp
        public var title: String { ["Key down", "Key up", "Mouse down", "Mouse up"][Self.allCases.firstIndex(of: self)!] }
    }
    public var id = UUID()
    public var kind: Kind
    /// HID usage for keys, button mask (1 left, 2 right, 4 middle) for the mouse.
    public var code: Int
    /// Milliseconds to wait after this event. The firmware's minimum is 10.
    public var delay: Int

    public init(kind: Kind, code: Int, delay: Int = 10) { self.kind = kind; self.code = code; self.delay = delay }
}

public struct Macro: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var events: [MacroEvent]
    public init(name: String, events: [MacroEvent] = []) { self.name = name; self.events = events }
}

// MARK: - Device settings

public struct DeviceSettings: Codable, Equatable, Sendable {
    public var disableWin = false
    public var disableAltF4 = false
    public var disableAltTab = false
    /// false: the Fn layer is active while Fn is held. true: Fn toggles it.
    public var fnToggle = false
    /// Index into `sleepOptions`.
    public var sleep = 2
    /// Index into `responseLevels`.
    public var response = 1

    public init() {}

    public static let sleepOptions = ["Never", "1 minute", "5 minutes", "30 minutes"]
    public static let responseLevels = [
        ("Level 1", "Wired about 2-3 ms, 2.4 GHz about 5-6 ms, Bluetooth about 12-13 ms"),
        ("Level 2", "Wired about 5-6 ms, 2.4 GHz about 7-9 ms, Bluetooth about 15-16 ms"),
        ("Level 3", "Wired about 8-9 ms, 2.4 GHz about 10-12 ms, Bluetooth about 18-19 ms"),
        ("Level 4", "Wired about 13-14 ms, 2.4 GHz about 15-17 ms, Bluetooth about 23-24 ms"),
        ("Level 5", "Wired about 17-18 ms, 2.4 GHz about 19-21 ms, Bluetooth about 27-28 ms"),
    ]
}

// MARK: - Screen

public struct ScreenConfig: Codable, Equatable, Sendable {
    /// Path of the source image or GIF the user picked.
    public var sourcePath: String?
    public var fit: ScreenFit = .cover
    /// Per-frame delays in ms, after trimming to the frame limit.
    public var delays: [Int] = []
    public init() {}
}

public enum ScreenFit: String, CaseIterable, Codable, Identifiable, Sendable {
    case cover, contain, stretch
    public var id: String { rawValue }
    public var title: String { ["cover": "Fill (crop)", "contain": "Fit (letterbox)", "stretch": "Stretch"][rawValue]! }
}

// MARK: - F75 Pro onboard settings

/// What AULA Studio writes to the F75 Pro's own memory (see F75Onboard).
public struct F75OnboardConfig: Codable, Equatable, Sendable {
    /// Built-in effect number (F75Onboard.effects).
    public var effect = 3
    /// 0-9
    public var brightness = 9
    /// 0-4
    public var speed = 3
    public var rainbow = true
    public var colour = RGB(r: 255, g: 0, b: 0)
    /// One of F75Onboard.sleepSeconds.
    public var sleepSeconds = 300

    public init() {}
}

// MARK: - Profiles

public struct Profile: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var model: KeyboardModel
    public var lighting = LightingConfig()
    /// Remaps keyed by remap slot.
    public var remapBase: [Int: KeyAction] = [:]
    public var remapFn: [Int: KeyAction] = [:]
    public var macros: [Macro] = []
    public var device = DeviceSettings()
    public var screen = ScreenConfig()
    /// F75 Pro settings stored on the keyboard. Optional so older profiles still load.
    public var f75: F75OnboardConfig?

    /// The F75 Pro's onboard settings, with defaults if this profile has none yet.
    public var f75Onboard: F75OnboardConfig {
        get { f75 ?? F75OnboardConfig() }
        set { f75 = newValue }
    }

    public init(name: String, model: KeyboardModel) {
        self.name = name
        self.model = model
        if model == .s75Pro { lighting.speed = 0.6; lighting.brightness = 1 }
    }
}
