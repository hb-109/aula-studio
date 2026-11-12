import AppKit
import AulaCore
import SwiftUI

struct RemapPage: View {
    @ObservedObject var app: AppModel
    @State private var kind: KeyAction.Kind = .key
    @State private var keyUsage = 0x04
    @State private var mods = 0
    @State private var consumer = 0xCD
    @State private var mouseIndex = 0
    @State private var specialCode = 0x0102
    @State private var macroIndex = 0
    @State private var macroMode: KeyAction.MacroMode = .once
    @State private var repeatCount = 2
    @State private var capturing = false
    @State private var monitor: Any?

    private var selected: [KeyDef] { app.currentKeys.filter { app.selectedKeys.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Layers")
                    ForEach(RemapLayer.allCases) { layer in
                        Button { app.remapLayer = layer } label: {
                            Text(layer.title).font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .frame(width: 130, alignment: .leading)
                                .foregroundStyle(Theme.text)
                                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.cardRaised))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(app.remapLayer == layer ? Theme.accent : Theme.stroke,
                                                                                   lineWidth: app.remapLayer == layer ? 1.5 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 40)
                KeyboardView(app: app, interaction: .select, sublabel: { key in
                    let a = app.action(for: key)
                    return a.kind == .default ? nil : short(a)
                }, showColours: false)
            }
            Text(selected.isEmpty ? "SELECT ONE OR MORE KEYS TO REMAP (SHIFT-CLICK OR DRAG TO SELECT SEVERAL)"
                                  : "\(selected.count) KEY\(selected.count == 1 ? "" : "S") SELECTED ON THE \(app.remapLayer.title.uppercased())")
                .font(.system(size: 12, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity)
            HStack {
                Text("Remap").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Button("Select all keys") { app.selectedKeys = Set(app.currentKeys.filter { !$0.fnLocked }.map(\.id)) }.buttonStyle(SoftButtonStyle())
                Button("Discard selection") { app.selectedKeys = [] }.buttonStyle(SoftButtonStyle()).disabled(selected.isEmpty)
            }
            HStack(alignment: .top, spacing: 18) {
                Card(title: "Assign an action", subtitle: "Pick what the selected keys do on the \(app.remapLayer.title.lowercased()).") { editor }
                Card(title: "Current bindings", subtitle: app.remapLayer == .base ? "Keys changed on the main layer." : "Keys changed on the Fn layer.") { bindings }
                    .frame(width: 340)
            }
        }
        .onDisappear { stopCapture() }
        .onAppear { if !supported(kind) { kind = .key } }
    }

    // MARK: Editor

    @ViewBuilder private var editor: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
            tile(.key, "Key", "keyboard")
            tile(.consumer, "Media", "playpause")
            tile(.mouse, "Mouse", "computermouse")
            tile(.macro, "Macro", "record.circle")
            tile(.special, "Function", "function")
            tile(.disable, "Disable", "nosign")
            tile(.default, "Default", "arrow.counterclockwise")
        }
        Divider().overlay(Theme.stroke)
        switch kind {
        case .key:
            HStack {
                Picker("Key", selection: $keyUsage) {
                    ForEach(HIDKeys.keys) { Text($0.name).tag($0.usage) }
                }
                .frame(width: 260)
                Button(capturing ? "Press a key…" : "Capture from keyboard") { capturing ? stopCapture() : startCapture() }
                    .buttonStyle(SoftButtonStyle())
            }
            HStack(spacing: 14) {
                modToggle("Ctrl", 1); modToggle("Shift", 2); modToggle("Alt / Option", 4); modToggle("Win / Cmd", 8)
            }
        case .consumer:
            Picker("Media key", selection: $consumer) { ForEach(HIDKeys.consumer) { Text($0.name).tag($0.code) } }.frame(width: 300)
        case .mouse:
            Picker("Mouse action", selection: $mouseIndex) {
                ForEach(Array(HIDKeys.mouse.enumerated()), id: \.offset) { Text($0.element.name).tag($0.offset) }
            }
            .frame(width: 300)
        case .special:
            Picker("Function", selection: $specialCode) { ForEach(HIDKeys.special) { Text($0.name).tag($0.code) } }.frame(width: 300)
        case .macro:
            if app.profile.macros.isEmpty {
                Banner(kind: .info, text: "No macros yet. Create one on the Macros page first.", buttonTitle: "Go to Macros") { app.page = .macros }
            } else {
                Picker("Macro", selection: $macroIndex) {
                    ForEach(Array(app.profile.macros.enumerated()), id: \.offset) { Text("#\($0.offset + 1) \($0.element.name)").tag($0.offset) }
                }
                .frame(width: 300)
                Picker("Playback", selection: $macroMode) { ForEach(KeyAction.MacroMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .frame(width: 300)
                if macroMode == .repeatCount {
                    Stepper("Repeat \(repeatCount) times", value: $repeatCount, in: 1...255)
                }
            }
        case .disable:
            Text("The selected keys will do nothing.").foregroundStyle(Theme.secondary)
        case .default:
            Text("The selected keys go back to what's printed on them.").foregroundStyle(Theme.secondary)
        }
        HStack {
            Button("Apply to selected keys") { app.remap(currentAction, keys: selected) }
                .buttonStyle(AccentButtonStyle(enabled: canApply)).disabled(!canApply)
            if selected.contains(where: \.fnLocked) {
                Text("Fn can't be remapped.").font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }

    private var canApply: Bool {
        !selected.filter { !$0.fnLocked }.isEmpty && (kind != .macro || app.profile.macros.indices.contains(macroIndex))
    }

    private var currentAction: KeyAction {
        switch kind {
        case .default: return .default
        case .disable: return .disable
        case .key: return .key(keyUsage, mods: mods)
        case .consumer: return .consumer(consumer)
        case .mouse: return .mouse(HIDKeys.mouse[mouseIndex].bytes)
        case .special: return .special(specialCode)
        case .macro: return .macro(macroIndex, mode: macroMode, repeatCount: macroMode == .repeatCount ? repeatCount : 1)
        }
    }

    @ViewBuilder private func tile(_ k: KeyAction.Kind, _ title: String, _ symbol: String) -> some View {
        if supported(k) { Tile(title: title, symbol: symbol, selected: kind == k) { kind = k } }
    }

    /// The F75 Pro only offers the action types decoded from AULA's driver so far.
    private func supported(_ k: KeyAction.Kind) -> Bool {
        app.model == .f75Pro ? F75Onboard.supports(k) : true
    }

    private func modToggle(_ title: String, _ bit: Int) -> some View {
        Toggle(title, isOn: Binding(get: { mods & bit != 0 }, set: { mods = $0 ? mods | bit : mods & ~bit }))
            .toggleStyle(.checkbox)
    }

    private func startCapture() {
        capturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if let usage = HIDKeys.macKeyCodeToHID[event.keyCode] {
                keyUsage = usage
                var m = 0
                if event.modifierFlags.contains(.control) { m |= 1 }
                if event.modifierFlags.contains(.shift) { m |= 2 }
                if event.modifierFlags.contains(.option) { m |= 4 }
                if event.modifierFlags.contains(.command) { m |= 8 }
                mods = m
            }
            stopCapture()
            return nil
        }
    }

    private func stopCapture() {
        capturing = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    // MARK: Bindings list

    @ViewBuilder private var bindings: some View {
        let table = app.remapLayer == .base ? app.profile.remapBase : app.profile.remapFn
        let rows = app.currentKeys.filter { table[$0.remapIndex] != nil }
        if rows.isEmpty {
            Text("No changes. Every key does what's printed on it.").foregroundStyle(Theme.secondary)
        } else {
            ForEach(rows) { key in
                HStack {
                    Text(key.label.isEmpty ? "Space" : key.label).frame(width: 60, alignment: .leading).foregroundStyle(Theme.text)
                    Image(systemName: "arrow.right").foregroundStyle(Theme.secondary)
                    Text(table[key.remapIndex]!.describe).foregroundStyle(Theme.text)
                    Spacer()
                    Button { app.remap(.default, keys: [key]) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.secondary).help("Reset to default")
                }
            }
            Button("Reset this layer", role: .destructive) {
                var p = app.profile
                if app.remapLayer == .base { p.remapBase = [:] } else { p.remapFn = [:] }
                app.profile = p
            }
            .buttonStyle(SoftButtonStyle(destructive: true))
        }
    }

    private func short(_ a: KeyAction) -> String {
        switch a.kind {
        case .disable: return "OFF"
        case .macro: return "M\(a.macro + 1)"
        case .consumer: return "MEDIA"
        case .mouse: return "MOUSE"
        case .special: return "FN"
        case .key:
            let name = HIDKeys.name(for: a.key)
            return (a.mods != 0 ? "+" : "") + String(name.prefix(5)).uppercased()
        case .default: return ""
        }
    }
}
