import AulaCore
import SwiftUI

struct LightingPage: View {
    @ObservedObject var app: AppModel
    @State private var brush = RGB(r: 255, g: 40, b: 90)
    @State private var recent: [RGB] = [.black, RGB(r: 0, g: 0, b: 255), RGB(r: 0, g: 255, b: 255),
                                        RGB(r: 0, g: 255, b: 0), RGB(r: 255, g: 255, b: 0), RGB(r: 255, g: 0, b: 0)]

    private var lighting: Binding<LightingConfig> {
        Binding(get: { app.profile.lighting }, set: { var p = app.profile; p.lighting = $0; app.profile = p })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            KeyboardView(app: app, interaction: .paint(brush))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            Text("CLICK OR DRAG ACROSS KEYS TO PAINT THEM WITH THE SELECTED COLOUR")
                .font(.system(size: 12, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity)
            Text("RGB Settings").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.text)
            HStack(alignment: .top, spacing: 18) {
                coloursCard.frame(width: 340)
                effectsCard
            }
        }
    }

    // MARK: Colours

    private var coloursCard: some View {
        Card(title: "Colours") {
            ColorPicker(selection: Binding(get: { brush.color }, set: { brush = RGB($0) }), supportsOpacity: false) {
                Text("Paint colour").foregroundStyle(Theme.text)
            }
            HStack(spacing: 8) {
                rgbField("R", \.r); rgbField("G", \.g); rgbField("B", \.b)
            }
            SectionLabel(text: "Recently used")
            HStack(spacing: 10) {
                ForEach(Array(recent.enumerated()), id: \.offset) { _, c in
                    Button { brush = c } label: {
                        Circle().fill(c.color).frame(width: 30, height: 30)
                            .overlay(Circle().stroke(c == brush ? Theme.accent : Theme.stroke, lineWidth: c == brush ? 2.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Button("Fill all keys") { app.fillAll(brush); remember(brush) }.buttonStyle(SoftButtonStyle())
                Button("Clear") { app.fillAll(.black) }.buttonStyle(SoftButtonStyle())
            }
            Text(app.model == .f75Pro ? "Painting switches the effect to Custom per-key."
                                      : "Painting switches the keyboard to custom per-key colours.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
        .onChange(of: brush) { remember($0) }
    }

    private func rgbField(_ label: String, _ path: WritableKeyPath<RGB, UInt8>) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(Theme.secondary)
            TextField("", value: Binding(get: { Int(brush[keyPath: path]) },
                                         set: { brush[keyPath: path] = UInt8(clamping: $0) }), format: .number)
                .textFieldStyle(.roundedBorder).frame(width: 52)
        }
    }

    private func remember(_ c: RGB) {
        recent.removeAll { $0 == c }
        recent.insert(c, at: 0)
        if recent.count > 6 { recent.removeLast() }
    }

    // MARK: Effects

    private var effectsCard: some View {
        Card(title: "Effects") {
            if app.model.capabilities.contains(.liveEffects) { liveEffects } else { onboardEffects }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 215), spacing: 10)]

    @ViewBuilder private var liveEffects: some View {
        let l = lighting
        SectionLabel(text: "Effect selection")
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(AppEffect.allCases) { effect in
                Tile(title: effect.title, symbol: effect.symbol, selected: l.wrappedValue.appEffect == effect) {
                    l.wrappedValue.appEffect = effect
                }
            }
        }
        Text("The F75 Pro runs these effects live from this app, so keep AULA Studio running (it lives in the menu bar). "
             + "“Keyboard's own lighting” hands control back to the keyboard and lets you pick the effect saved on it.")
            .font(.caption).foregroundStyle(Theme.secondary)
        Divider().overlay(Theme.stroke)
        if l.wrappedValue.appEffect == .keyboardOwn {
            f75OnboardEffects
        } else {
            SectionLabel(text: "Effect parameters")
            LabeledSlider(title: "Global brightness", value: l.brightness, range: 0.05...1)
            if l.wrappedValue.appEffect.usesSpeed { LabeledSlider(title: "Speed", value: l.speed) }
            if l.wrappedValue.appEffect.usesColour { ColourField(title: l.wrappedValue.appEffect == .music ? "Peak colour" : "Colour", colour: l.colour) }
            if l.wrappedValue.appEffect.usesBaseColour { ColourField(title: "Background", colour: l.baseColour) }
            if l.wrappedValue.appEffect == .music { musicControls }
        }
        Divider().overlay(Theme.stroke)
        SectionLabel(text: "Layout")
        Picker("", selection: l.layout) {
            Text("ANSI (US)").tag(LayoutVariant.ansi)
            Text("ISO (UK / EU)").tag(LayoutVariant.iso)
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 260)
    }

    /// The F75 Pro's built-in effects, saved on the keyboard.
    @ViewBuilder private var f75OnboardEffects: some View {
        let cfg = Binding(get: { app.profile.f75Onboard }, set: { var p = app.profile; p.f75Onboard = $0; app.profile = p })
        let effect = F75Onboard.effects.first { $0.id == cfg.wrappedValue.effect } ?? F75Onboard.effects[0]
        SectionLabel(text: "Saved on the keyboard")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
            ForEach(F75Onboard.effects) { e in
                Tile(title: e.name, symbol: "keyboard", selected: e.id == effect.id) { cfg.wrappedValue.effect = e.id }
            }
        }
        LabeledSlider(title: "Brightness", value: Binding(get: { Double(cfg.wrappedValue.brightness) }, set: { cfg.wrappedValue.brightness = Int($0.rounded()) }),
                      range: 0...Double(F75Onboard.maxBrightness), steps: F75Onboard.maxBrightness) { $0 == 0 ? "Off" : "Level \(Int($0.rounded()))" }
        if effect.hasSpeed {
            LabeledSlider(title: "Speed", value: Binding(get: { Double(cfg.wrappedValue.speed) }, set: { cfg.wrappedValue.speed = Int($0.rounded()) }),
                          range: 0...Double(F75Onboard.maxSpeed), steps: F75Onboard.maxSpeed) { "Level \(Int($0.rounded()))" }
        }
        if effect.hasRainbow {
            Toggle("Rainbow colours", isOn: cfg.rainbow).toggleStyle(.switch).tint(Theme.accent)
        }
        if effect.hasColour && !(effect.hasRainbow && cfg.wrappedValue.rainbow) {
            ColourField(title: "Effect colour", colour: cfg.colour)
        }
        Text("These settings live in the keyboard, so they work without the app and on other computers. Press Save to Keyboard to write them.")
            .font(.caption).foregroundStyle(Theme.secondary)
    }

    @ViewBuilder private var musicControls: some View {
        let l = lighting
        Picker("Style", selection: l.musicStyle) {
            ForEach(MusicStyle.allCases) { Text($0.title).tag($0) }
        }
        Picker("Listen to", selection: l.audioSource) {
            ForEach(AudioSource.allCases) { Text($0.title).tag($0) }
        }
        LabeledSlider(title: "Sensitivity", value: l.sensitivity)
        if let error = app.audioError {
            Banner(kind: .warning, text: error, buttonTitle: "Open Settings") {
                SystemLinks.open(l.wrappedValue.audioSource == .system ? SystemLinks.screenRecording : SystemLinks.microphone)
            }
        } else {
            Text(l.wrappedValue.audioSource == .system
                 ? "Reacts to whatever your Mac is playing. macOS asks for Screen & System Audio Recording permission the first time; only sound is used."
                 : "Reacts to sound picked up by the microphone.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
    }

    @ViewBuilder private var onboardEffects: some View {
        let l = lighting
        let effect = l.wrappedValue.hardwareEffect
        let custom = l.wrappedValue.useCustomColours
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Base layer")
                Tile(title: "Custom per-key", symbol: "paintbrush.pointed", selected: custom) { l.wrappedValue.useCustomColours = true }
                    .frame(width: 200)
                SectionLabel(text: "Global brightness").padding(.top, 8)
                Slider(value: l.brightness, in: 0...1, step: 0.2).tint(Theme.accent).frame(width: 200)
                Text("Level \(l.wrappedValue.brightnessLevel) of 5").font(.caption).foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Effect selection")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(HardwareEffect.allCases) { e in
                        Tile(title: e.title, symbol: symbol(e), selected: !custom && effect == e) {
                            l.wrappedValue.hardwareEffect = e
                            l.wrappedValue.useCustomColours = false
                        }
                    }
                }
            }
        }
        if !custom {
            Divider().overlay(Theme.stroke)
            SectionLabel(text: "Effect parameters")
            if effect.usesSpeed {
                LabeledSlider(title: "Speed", value: l.speed, steps: 5) { "Level \(Int(($0 * 5).rounded()))" }
            }
            if let axis = effect.direction {
                Picker("Direction", selection: l.direction) {
                    Text(axis == .leftRight ? "Left to right" : "Up").tag(0)
                    Text(axis == .leftRight ? "Right to left" : "Down").tag(1)
                }
                .pickerStyle(.segmented).frame(width: 320)
            }
            if effect.usesColour {
                Toggle("Rainbow colours", isOn: l.rainbow).toggleStyle(.switch).tint(Theme.accent)
                if !l.wrappedValue.rainbow { ColourField(title: "Effect colour", colour: l.colour) }
            }
        }
        Text("These effects run on the keyboard itself, so they keep working without the app. Press Save to Keyboard to apply changes. "
             + "The S75 Pro's light bar is set with Fn + Shift (mode) and Fn + / (colour) on the keyboard; Aula's driver has no light-bar controls either.")
            .font(.caption).foregroundStyle(Theme.secondary)
    }

    private func symbol(_ e: HardwareEffect) -> String {
        switch e {
        case .off: return "lightbulb.slash"
        case .staticOn: return "circle.slash"
        case .breath, .pulsating: return "wind"
        case .spectrum, .colourful: return "rainbow"
        case .ripples, .outward, .explode: return "dot.radiowaves.left.and.right"
        case .scrolling, .flowing, .rolling, .shuttle: return "water.waves"
        case .rotating, .tilt: return "arrow.triangle.2.circlepath"
        case .glittering, .fluttering: return "sparkles"
        case .singleOn, .singleOff, .launch: return "hand.tap"
        }
    }
}
