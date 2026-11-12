// Draws the app icon ("Mixer": red, green and blue sliders) into Resources/AppIcon.icns.
// Usage: swift tools/make-icon.swift   (run from the project folder)
//
// Follows Apple's macOS icon template: a 1024 canvas with an 824-point tile inset
// 100 points, continuous corners, and a soft drop shadow.

import AppKit

/// A rounded square with continuous (squircle-like) corners.
func tilePath(_ r: NSRect) -> NSBezierPath {
    let c = r.width * 0.256
    let p = NSBezierPath()
    p.move(to: NSPoint(x: r.minX + c, y: r.maxY))
    p.line(to: NSPoint(x: r.maxX - c, y: r.maxY))
    p.curve(to: NSPoint(x: r.maxX, y: r.maxY - c), controlPoint1: NSPoint(x: r.maxX - c * 0.33, y: r.maxY), controlPoint2: NSPoint(x: r.maxX, y: r.maxY - c * 0.33))
    p.line(to: NSPoint(x: r.maxX, y: r.minY + c))
    p.curve(to: NSPoint(x: r.maxX - c, y: r.minY), controlPoint1: NSPoint(x: r.maxX, y: r.minY + c * 0.33), controlPoint2: NSPoint(x: r.maxX - c * 0.33, y: r.minY))
    p.line(to: NSPoint(x: r.minX + c, y: r.minY))
    p.curve(to: NSPoint(x: r.minX, y: r.minY + c), controlPoint1: NSPoint(x: r.minX + c * 0.33, y: r.minY), controlPoint2: NSPoint(x: r.minX, y: r.minY + c * 0.33))
    p.line(to: NSPoint(x: r.minX, y: r.maxY - c))
    p.curve(to: NSPoint(x: r.minX + c, y: r.maxY), controlPoint1: NSPoint(x: r.minX, y: r.maxY - c * 0.33), controlPoint2: NSPoint(x: r.minX + c * 0.33, y: r.maxY))
    p.close()
    return p
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1) }

func draw(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let k = size / 1024
        let tile = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
        let path = tilePath(tile)

        // Drop shadow under the tile, as on Apple's own icons.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -10 * k)
        shadow.shadowBlurRadius = 28 * k
        shadow.set()
        rgb(38, 38, 44).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Tile: dark graphite, lit from the top.
        NSGradient(colors: [rgb(54, 54, 62), rgb(30, 30, 35)])!.draw(in: path, angle: -90)
        NSColor.white.withAlphaComponent(0.08).setStroke()
        path.lineWidth = 3 * k
        path.stroke()

        // Three sliders: track, coloured fill up to the knob, white knob.
        let sliders: [(y: CGFloat, value: CGFloat, colour: NSColor)] = [
            (650, 0.68, rgb(226, 75, 74)),
            (512, 0.32, rgb(151, 196, 89)),
            (374, 0.86, rgb(55, 138, 221)),
        ]
        let left: CGFloat = 250, right: CGFloat = 774, thickness: CGFloat = 44, knob: CGFloat = 104
        for s in sliders {
            let y = s.y * k
            let track = NSRect(x: left * k, y: y - thickness / 2 * k, width: (right - left) * k, height: thickness * k)
            let trackPath = NSBezierPath(roundedRect: track, xRadius: thickness / 2 * k, yRadius: thickness / 2 * k)
            rgb(70, 70, 80).setFill()
            trackPath.fill()

            let knobX = (left + (right - left) * s.value) * k
            let fill = NSRect(x: track.minX, y: track.minY, width: knobX - track.minX, height: track.height)
            NSGradient(colors: [s.colour.blended(withFraction: 0.18, of: .white)!, s.colour])!
                .draw(in: NSBezierPath(roundedRect: fill, xRadius: thickness / 2 * k, yRadius: thickness / 2 * k), angle: -90)

            NSGraphicsContext.saveGraphicsState()
            let knobShadow = NSShadow()
            knobShadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
            knobShadow.shadowOffset = NSSize(width: 0, height: -6 * k)
            knobShadow.shadowBlurRadius = 14 * k
            knobShadow.set()
            let knobRect = NSRect(x: knobX - knob / 2 * k, y: y - knob / 2 * k, width: knob * k, height: knob * k)
            NSGradient(colors: [.white, rgb(226, 226, 232)])!.draw(in: NSBezierPath(ovalIn: knobRect), angle: -90)
            NSGraphicsContext.restoreGraphicsState()
        }
        return true
    }
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(size: px).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
try! fm.createDirectory(at: URL(fileURLWithPath: "Resources"), withIntermediateDirectories: true)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
