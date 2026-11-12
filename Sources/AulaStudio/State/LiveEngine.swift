import AulaCore
import Foundation
import QuartzCore

/// Computes the F75 Pro's colours ~30 times a second from its active profile, for
/// the keyboard (direct mode) and the on-screen preview.
@MainActor
final class LiveEngine {
    private var startTime = CACurrentMediaTime()
    private var pressTimes: [Int: CFTimeInterval] = [:]
    private var ripples: [(centre: CGPoint, start: CFTimeInterval)] = []
    private var beatFlash: CFTimeInterval = 0
    var audio = AudioAnalyzer.Levels()
    /// The F75 Pro's onboard settings, previewed when the keyboard shows its own lighting.
    var onboard = F75OnboardConfig()

    func keyDown(_ usage: Int, lighting: LightingConfig) {
        let now = CACurrentMediaTime()
        for key in KeyboardModel.f75Pro.layout.keys(for: lighting.layout) where key.hidUsages.contains(usage) {
            pressTimes[key.led] = now
            if lighting.appEffect == .ripple { ripples.append((CGPoint(x: key.rect.midX, y: key.rect.midY), now)) }
        }
    }

    func audioBeat() { beatFlash = CACurrentMediaTime() }

    /// The frame for this instant, indexed by LED slot, brightness applied.
    func frame(_ s: LightingConfig, applyBrightness: Bool = true) -> [RGB] {
        let now = CACurrentMediaTime()
        let t = now - startTime
        let layout = KeyboardModel.f75Pro.layout
        let bounds = layout.bounds
        var frame = [RGB](repeating: .black, count: F75Protocol.ledSlots)
        ripples.removeAll { now - $0.start > 1.6 / max(s.speed * 3, 0.2) }
        let speed = 0.2 + s.speed * 2.8

        for key in layout.keys(for: s.layout) {
            let c = CGPoint(x: key.rect.midX, y: key.rect.midY)
            let x = (c.x - bounds.minX) / bounds.width
            let up = (bounds.maxY - c.y) / bounds.height          // 0 at the bottom row, 1 at the top
            let colour: RGB
            switch s.appEffect {
            case .keyboardOwn:
                // An approximation of the saved effect: its colour or a rainbow, at its brightness.
                let e = F75Onboard.effects.first { $0.id == onboard.effect }
                let rainbow = e.map { !$0.hasColour || ($0.hasRainbow && onboard.rainbow) } ?? true
                let level = Double(onboard.brightness) / Double(F75Onboard.maxBrightness)
                colour = Colour.scale(rainbow ? Colour.hsv(x - t * 0.05 * Double(onboard.speed + 1), 1, 1) : onboard.colour, max(level, 0.08))
            case .solid:
                colour = s.colour
            case .custom:
                colour = s.paint[key.led] ?? .black
            case .rainbow:
                var hue = (x - t * 0.25 * speed).truncatingRemainder(dividingBy: 1)
                if hue < 0 { hue += 1 }
                colour = Colour.hsv(hue, 1, 1)
            case .breathing:
                colour = Colour.scale(s.colour, 0.08 + 0.92 * (sin(t * 1.6 * speed) + 1) / 2)
            case .reactive:
                let age = pressTimes[key.led].map { now - $0 } ?? .infinity
                colour = Colour.mix(s.baseColour, s.colour, max(0, 1 - age / (0.9 / speed)))
            case .ripple:
                var level = 0.0
                for r in ripples {
                    let age = now - r.start
                    let ring = max(0, 1 - abs(hypot(c.x - r.centre.x, c.y - r.centre.y) - age * 420 * speed) / 45)
                    level = max(level, ring * max(0, 1 - age * speed / 1.6))
                }
                colour = Colour.mix(s.baseColour, s.colour, level)
            case .music:
                colour = musicColour(s, x: x, up: up, t: now)
            }
            frame[key.led] = colour
        }
        // In ANSI, mirror backslash onto the ISO '#' LED in case this board wires it there.
        if s.layout == .ansi { frame[75] = frame[80] }
        return applyBrightness ? frame.map { Colour.scale($0, s.brightness) } : frame
    }

    private func musicColour(_ s: LightingConfig, x: Double, up: Double, t: CFTimeInterval) -> RGB {
        let bands = audio.bands.map(Double.init)
        let n = bands.count
        switch s.musicStyle {
        case .spectrum:
            // Columns are frequencies (bass on the left); each lights from the bottom up.
            let level = bands[min(n - 1, Int(x * Double(n)))]
            let lit = max(0, min(1, (level - up) * 4 + 0.5))
            let hue = 0.6 - 0.6 * up    // blue at the bottom through to red at the top
            return Colour.mix(s.baseColour, Colour.mix(s.colour, Colour.hsv(hue < 0 ? hue + 1 : hue, 1, 1), up), lit)
        case .rows:
            // Bottom row is bass, top row is treble.
            let index = min(n - 1, Int(up * Double(n)))
            return Colour.mix(s.baseColour, s.colour, bands[index])
        case .pulse:
            let bass = (bands[0] + bands[1] + bands[2]) / 3
            let flash = max(0, 1 - (t - beatFlash) / 0.25)
            return Colour.mix(Colour.mix(s.baseColour, s.colour, bass), .white, flash * 0.7)
        }
    }
}

enum Colour {
    static func scale(_ c: RGB, _ k: Double) -> RGB {
        let k = min(max(k, 0), 1)
        return RGB(r: UInt8(Double(c.r) * k), g: UInt8(Double(c.g) * k), b: UInt8(Double(c.b) * k))
    }

    static func mix(_ a: RGB, _ b: RGB, _ k: Double) -> RGB {
        let k = min(max(k, 0), 1)
        func m(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8(Double(x) + (Double(y) - Double(x)) * k) }
        return RGB(r: m(a.r, b.r), g: m(a.g, b.g), b: m(a.b, b.b))
    }

    static func hsv(_ h: Double, _ s: Double, _ v: Double) -> RGB {
        let h6 = (h - floor(h)) * 6
        let i = Int(h6) % 6, f = h6 - floor(h6)
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        let (r, g, b): (Double, Double, Double)
        switch i {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        return RGB(r: UInt8(r * 255), g: UInt8(g * 255), b: UInt8(b * 255))
    }
}
