import AulaCore
import SwiftUI

/// The on-screen keyboard. Shows live colours and lets you paint or select keys.
struct KeyboardView: View {
    enum Interaction { case paint(RGB), select, none }

    @ObservedObject var app: AppModel
    var interaction: Interaction
    /// Small text under a key's legend, such as its remap.
    var sublabel: ((KeyDef) -> String?)? = nil
    /// Whether key colours show the live preview (true) or a neutral keycap (false).
    var showColours = true

    var body: some View {
        let keys = app.currentKeys
        let bounds = app.model.layout.bounds
        GeometryReader { geo in
            let scale = min(geo.size.width / bounds.width, geo.size.height / bounds.height)
            let offset = CGPoint(x: (geo.size.width - bounds.width * scale) / 2, y: (geo.size.height - bounds.height * scale) / 2)
            let toView = { (r: CGRect) -> CGRect in
                CGRect(x: offset.x + (r.minX - bounds.minX) * scale, y: offset.y + (r.minY - bounds.minY) * scale,
                       width: r.width * scale, height: r.height * scale)
            }
            Canvas { ctx, _ in
                // Layouts are on a 40-point key grid, so one key unit is 40 * scale.
                let unit = 40 * scale
                let plate = toView(bounds)
                ctx.fill(Path(roundedRect: plate.offsetBy(dx: 0, dy: 0.12 * unit), cornerRadius: 0.32 * unit), with: .color(.black.opacity(0.55)))
                ctx.fill(Path(roundedRect: plate, cornerRadius: 0.32 * unit), with: .color(Color(red: 0.1, green: 0.1, blue: 0.11)))
                ctx.stroke(Path(roundedRect: plate, cornerRadius: 0.32 * unit), with: .color(.white.opacity(0.09)), lineWidth: 1)
                for key in keys {
                    // Keys sit flush on the grid; a thin seam separates them.
                    let rect = toView(key.rect).insetBy(dx: 0.035 * unit, dy: 0.035 * unit)
                    // Show the LED colour laid over a dark keycap, so it reads as light on the
                    // key rather than solid paint, like Wootility's preview.
                    let keycap = RGB(r: 40, g: 40, b: 46)
                    let lit = showColours ? Colour.mix(keycap, app.preview[key.led] ?? .black, 0.62) : keycap
                    let path = Path(roundedRect: rect, cornerRadius: 0.1 * unit)
                    ctx.fill(path, with: .color(lit.color))
                    // A soft top highlight gives the keycap some depth.
                    ctx.fill(path, with: .linearGradient(Gradient(colors: [.white.opacity(0.1), .clear, .black.opacity(0.14)]),
                                                         startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                                         endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                    let selected = app.selectedKeys.contains(key.id)
                    ctx.stroke(path, with: .color(selected ? Theme.accent : .black.opacity(0.35)), lineWidth: selected ? 3 : 1)
                    let luminance = 0.3 * Double(lit.r) + 0.59 * Double(lit.g) + 0.11 * Double(lit.b)
                    let ink: Color = luminance > 170 ? .black.opacity(0.8) : .white.opacity(0.92)
                    let sub = sublabel?(key)
                    if !key.label.isEmpty {
                        ctx.draw(Text(key.label).font(.system(size: max(9, 0.3 * unit), weight: .semibold)).foregroundColor(ink),
                                 at: CGPoint(x: rect.midX, y: rect.midY - (sub == nil ? 0 : 0.14 * unit)))
                    }
                    if let sub {
                        ctx.draw(Text(sub).font(.system(size: max(8, 0.22 * unit), weight: .bold)).foregroundColor(Theme.accent),
                                 at: CGPoint(x: rect.midX, y: rect.midY + (key.label.isEmpty ? 0 : 0.2 * unit)))
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard let key = keys.first(where: { toView($0.rect).contains(drag.location) }) else { return }
                    switch interaction {
                    case .paint(let colour):
                        if app.preview[key.led] != colour || app.profile.lighting.paint[key.led] != colour {
                            app.paint(keys: [key], colour: colour)
                        }
                    case .select:
                        // A drag sweeps keys into the selection; a plain click selects one key.
                        if drag.translation == .zero {
                            let additive = NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.command)
                            if additive {
                                if app.selectedKeys.contains(key.id) { app.selectedKeys.remove(key.id) } else { app.selectedKeys.insert(key.id) }
                            } else {
                                app.selectedKeys = [key.id]
                            }
                        } else {
                            app.selectedKeys.insert(key.id)
                        }
                    case .none:
                        break
                    }
                })
        }
        .aspectRatio(bounds.width / bounds.height, contentMode: .fit)
        .frame(maxWidth: 1060)
    }
}
