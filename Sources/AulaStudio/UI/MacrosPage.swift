import AppKit
import AulaCore
import QuartzCore
import SwiftUI

struct MacrosPage: View {
    @ObservedObject var app: AppModel
    @State private var selection: UUID?
    @State private var recording = false
    @State private var recordRecordInterval = true
    @State private var monitor: Any?
    @State private var lastEventTime: CFTimeInterval = 0

    private var macros: [Macro] { app.profile.macros }
    private var index: Int? { macros.firstIndex { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Macros").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                budget
            }
            HStack(alignment: .top, spacing: 18) {
                Card(title: "Macro list") {
                    if macros.isEmpty {
                        Text("No macros yet.").foregroundStyle(Theme.secondary)
                    }
                    ForEach(Array(macros.enumerated()), id: \.element.id) { i, m in
                        Button { selection = m.id } label: {
                            HStack {
                                Text("#\(i + 1)").foregroundStyle(Theme.secondary).frame(width: 30, alignment: .leading)
                                Text(m.name).foregroundStyle(Theme.text)
                                Spacer()
                                Text("\(m.events.count)").foregroundStyle(Theme.secondary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 8).fill(selection == m.id ? Theme.cardRaised : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Button("New macro") {
                        var p = app.profile
                        let m = Macro(name: "Macro \(p.macros.count + 1)")
                        p.macros.append(m)
                        app.profile = p
                        selection = m.id
                    }
                    .buttonStyle(SoftButtonStyle()).disabled(macros.count >= S75Protocol.macroSlots)
                }
                .frame(width: 300)

                if let i = index { editor(i) } else {
                    Card(title: "Edit macro") {
                        Text("Select a macro, or create one. Then bind it to a key on the Remap page.").foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
        .onAppear { if selection == nil { selection = macros.first?.id } }
        .onDisappear { stopRecording() }
    }

    private var budget: some View {
        let used = S75Protocol.macroBudgetUsed(macros)
        return VStack(alignment: .trailing, spacing: 4) {
            Text("Keyboard memory: \(used) / \(S75Protocol.macroBudget) bytes").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            ProgressView(value: Double(min(used, S75Protocol.macroBudget)), total: Double(S75Protocol.macroBudget))
                .tint(used > S75Protocol.macroBudget ? Theme.bad : Theme.accent).frame(width: 220)
        }
    }

    private func binding(_ i: Int) -> Binding<Macro> {
        Binding(get: { app.profile.macros.indices.contains(i) ? app.profile.macros[i] : Macro(name: "") },
                set: { m in var p = app.profile; if p.macros.indices.contains(i) { p.macros[i] = m; app.profile = p } })
    }

    private func editor(_ i: Int) -> some View {
        let macro = binding(i)
        return Card(title: "Edit macro") {
            HStack {
                TextField("Name", text: macro.name).textFieldStyle(.roundedBorder).frame(width: 260)
                Spacer()
                Button(recording ? "Stop recording" : "Record") { recording ? stopRecording() : startRecording(i) }
                    .buttonStyle(AccentButtonStyle(enabled: true))
                Toggle("Record delays", isOn: $recordRecordInterval).toggleStyle(.checkbox)
            }
            if recording {
                Banner(kind: .info, text: "Recording: type on any keyboard while this window is in front. Press Stop recording when you're done.")
            }
            HStack {
                SectionLabel(text: "Action").frame(width: 130, alignment: .leading)
                SectionLabel(text: "Key or button").frame(width: 190, alignment: .leading)
                SectionLabel(text: "Then wait (ms)")
            }
            if macro.wrappedValue.events.isEmpty {
                Text("No events. Record, or add them one by one.").foregroundStyle(Theme.secondary)
            }
            ForEach(Array(macro.wrappedValue.events.enumerated()), id: \.element.id) { j, _ in
                eventRow(macro, j)
            }
            HStack {
                Button("Add key press") {
                    macro.wrappedValue.events += [MacroEvent(kind: .keyDown, code: 0x04, delay: 30),
                                                  MacroEvent(kind: .keyUp, code: 0x04, delay: 30)]
                }
                Button("Add mouse click") {
                    macro.wrappedValue.events += [MacroEvent(kind: .mouseDown, code: 1, delay: 30),
                                                  MacroEvent(kind: .mouseUp, code: 1, delay: 30)]
                }
                Button("Clear events") { macro.wrappedValue.events = [] }
                Spacer()
                Button("Delete macro", role: .destructive) {
                    stopRecording()
                    app.deleteMacro(at: i)
                    selection = app.profile.macros.first?.id
                }
                .buttonStyle(SoftButtonStyle(destructive: true))
            }
            .buttonStyle(SoftButtonStyle())
            Text("Each event waits at least 10 ms. Deleting a macro also clears the keys bound to it.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
    }

    private func eventRow(_ macro: Binding<Macro>, _ j: Int) -> some View {
        let ev = Binding(get: { macro.wrappedValue.events.indices.contains(j) ? macro.wrappedValue.events[j] : MacroEvent(kind: .keyDown, code: 4) },
                         set: { if macro.wrappedValue.events.indices.contains(j) { macro.wrappedValue.events[j] = $0 } })
        let isMouse = ev.wrappedValue.kind == .mouseDown || ev.wrappedValue.kind == .mouseUp
        return HStack {
            Picker("", selection: ev.kind) { ForEach(MacroEvent.Kind.allCases, id: \.self) { Text($0.title).tag($0) } }
                .labelsHidden().frame(width: 130)
            if isMouse {
                Picker("", selection: ev.code) { Text("Left").tag(1); Text("Right").tag(2); Text("Middle").tag(4) }
                    .labelsHidden().frame(width: 190)
            } else {
                Picker("", selection: ev.code) { ForEach(HIDKeys.keys) { Text($0.name).tag($0.usage) } }
                    .labelsHidden().frame(width: 190)
            }
            TextField("", value: ev.delay, format: .number).textFieldStyle(.roundedBorder).frame(width: 80)
            Spacer()
            Button { macro.wrappedValue.events.remove(at: j) } label: { Image(systemName: "minus.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(Theme.secondary)
        }
    }

    // MARK: Recording

    private func startRecording(_ i: Int) {
        stopRecording()
        recording = true
        lastEventTime = 0
        var held = Set<Int>()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            guard let usage = HIDKeys.macKeyCodeToHID[event.keyCode] else { return nil }
            let kind: MacroEvent.Kind
            switch event.type {
            case .keyDown:
                if event.isARepeat { return nil }
                kind = .keyDown
            case .keyUp: kind = .keyUp
            default:
                // Modifier keys arrive as flag changes: pressed if not already held.
                kind = held.contains(usage) ? .keyUp : .keyDown
            }
            if kind == .keyDown { held.insert(usage) } else { held.remove(usage) }
            let now = CACurrentMediaTime()
            var p = app.profile
            guard p.macros.indices.contains(i) else { return nil }
            // The wait belongs to the previous event: it's the time until this one.
            if let last = p.macros[i].events.indices.last, lastEventTime > 0 {
                p.macros[i].events[last].delay = recordRecordInterval ? max(10, Int((now - lastEventTime) * 1000)) : 10
            }
            p.macros[i].events.append(MacroEvent(kind: kind, code: usage, delay: 10))
            app.profile = p
            lastEventTime = now
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
