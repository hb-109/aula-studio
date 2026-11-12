import AppKit
import AulaCore
import SwiftUI

enum Theme {
    static let window = Color(red: 0.067, green: 0.067, blue: 0.075)
    static let rail = Color(red: 0.086, green: 0.086, blue: 0.098)
    static let sidebar = Color(red: 0.11, green: 0.11, blue: 0.125)
    static let card = Color(red: 0.125, green: 0.125, blue: 0.14)
    static let cardRaised = Color(red: 0.16, green: 0.16, blue: 0.18)
    static let stroke = Color.white.opacity(0.07)
    static let text = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.55)
    static let accent = Color(red: 1.0, green: 0.82, blue: 0.29)
    static let accentText = Color(red: 0.12, green: 0.1, blue: 0.02)
    static let good = Color(red: 0.35, green: 0.85, blue: 0.5)
    static let warn = Color(red: 1.0, green: 0.62, blue: 0.25)
    static let bad = Color(red: 1.0, green: 0.38, blue: 0.38)
}

extension RGB {
    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(r: UInt8(max(0, min(1, c.redComponent)) * 255),
                  g: UInt8(max(0, min(1, c.greenComponent)) * 255),
                  b: UInt8(max(0, min(1, c.blueComponent)) * 255))
    }

    var color: Color { Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
    var hex: String { String(format: "%02X%02X%02X", r, g, b) }

    init?(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(r: UInt8(v >> 16), g: UInt8((v >> 8) & 0xFF), b: UInt8(v & 0xFF))
    }
}

/// A rounded panel like Wootility's cards.
struct Card<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.text)
                    if let subtitle { Text(subtitle).font(.callout).foregroundStyle(Theme.secondary) }
                }
            }
            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.secondary)
    }
}

struct AccentButtonStyle: ButtonStyle {
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .foregroundStyle(enabled ? Theme.accentText : Theme.secondary)
            .background(RoundedRectangle(cornerRadius: 9).fill(enabled ? Theme.accent : Theme.cardRaised))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SoftButtonStyle: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 8)
            .foregroundStyle(destructive ? Theme.bad : Theme.text)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cardRaised.opacity(configuration.isPressed ? 0.6 : 1)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke))
    }
}

/// A selectable tile, used for effects and action types.
struct Tile: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 18)
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 11)
            .foregroundStyle(selected ? Theme.accentText : Theme.text)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.accent : Theme.cardRaised))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct Chip: View {
    let text: String
    var color: Color = Theme.secondary
    var body: some View {
        Text(text).font(.system(size: 11, weight: .bold)).tracking(0.4)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

/// A slider with a label and a value readout.
struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var steps: Int? = nil
    var format: (Double) -> String = { "\(Int(($0 * 100).rounded())) %" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(text: title)
                Spacer()
                Text(format(value)).font(.system(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(Theme.text)
            }
            if let steps {
                Slider(value: $value, in: range, step: (range.upperBound - range.lowerBound) / Double(steps))
            } else {
                Slider(value: $value, in: range)
            }
        }
        .tint(Theme.accent)
    }
}

/// Colour picker plus a hex field.
struct ColourField: View {
    let title: String
    @Binding var colour: RGB
    @State private var hexText = ""

    var body: some View {
        HStack(spacing: 10) {
            ColorPicker("", selection: Binding(get: { colour.color }, set: { colour = RGB($0) }), supportsOpacity: false)
                .labelsHidden()
            Text(title).foregroundStyle(Theme.text)
            Spacer()
            TextField("RRGGBB", text: $hexText)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 74)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if let c = RGB(hex: hexText) { colour = c } else { hexText = colour.hex } }
        }
        .onAppear { hexText = colour.hex }
        .onChange(of: colour) { hexText = $0.hex }
    }
}

struct Banner: View {
    enum Kind { case info, warning, error, success }
    let kind: Kind
    let text: String
    var buttonTitle: String?
    var button: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.callout).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let buttonTitle, let button { Button(buttonTitle, action: button).buttonStyle(SoftButtonStyle()) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.35)))
    }

    private var icon: String {
        switch kind {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .success: return "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch kind {
        case .info: return Color(red: 0.4, green: 0.65, blue: 1)
        case .warning: return Theme.warn
        case .error: return Theme.bad
        case .success: return Theme.good
        }
    }
}

enum SystemLinks {
    static func open(_ string: String) { if let url = URL(string: string) { NSWorkspace.shared.open(url) } }
    static let inputMonitoring = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    static let screenRecording = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    static let microphone = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
}
