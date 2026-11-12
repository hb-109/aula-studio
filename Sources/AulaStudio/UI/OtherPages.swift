import AppKit
import AulaCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Keyboard settings

struct DeviceSettingsPage: View {
    @ObservedObject var app: AppModel

    private var device: Binding<DeviceSettings> {
        Binding(get: { app.profile.device }, set: { var p = app.profile; p.device = $0; app.profile = p })
    }

    var body: some View {
        if app.model == .f75Pro { f75Body } else { s75Body }
    }

    private var f75Body: some View {
        let cfg = Binding(get: { app.profile.f75Onboard }, set: { var p = app.profile; p.f75Onboard = $0; app.profile = p })
        return VStack(alignment: .leading, spacing: 18) {
            Text("Keyboard Settings").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.text)
            Card(title: "Sleep", subtitle: "Turn the keyboard's lights off after it has been idle.") {
                Picker("", selection: cfg.sleepSeconds) {
                    ForEach(F75Onboard.sleepSeconds, id: \.self) { s in
                        Text(s < 60 ? "\(s) seconds" : (s % 60 == 0 ? "\(s / 60) minute\(s == 60 ? "" : "s")" : "\(Double(s) / 60) minutes")).tag(s)
                    }
                }
                .pickerStyle(.radioGroup).labelsHidden()
            }
            Text("Stored on the keyboard. Press Save to Keyboard to apply it.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
    }

    private var s75Body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Keyboard Settings").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.text)
            HStack(alignment: .top, spacing: 18) {
                Card(title: "Sleep", subtitle: "Turn the lights off after the keyboard has been idle.") {
                    Picker("", selection: device.sleep) {
                        ForEach(Array(DeviceSettings.sleepOptions.enumerated()), id: \.offset) { Text($0.element).tag($0.offset) }
                    }
                    .pickerStyle(.radioGroup).labelsHidden()
                }
                Card(title: "Key response time", subtitle: "Debounce: how long a key must settle before it counts.") {
                    Picker("", selection: device.response) {
                        ForEach(Array(DeviceSettings.responseLevels.enumerated()), id: \.offset) { i, level in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.0)
                                Text(level.1).font(.caption).foregroundStyle(Theme.secondary)
                            }
                            .tag(i)
                        }
                    }
                    .pickerStyle(.radioGroup).labelsHidden()
                    Text("Lower is faster. If keys start to chatter (double-type), choose a higher level.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            Card(title: "Shortcuts and Fn key") {
                Toggle("Disable the Windows / Command key", isOn: device.disableWin)
                Toggle("Block Alt + F4", isOn: device.disableAltF4)
                Toggle("Block Alt + Tab", isOn: device.disableAltTab)
                Toggle("Fn toggles the Fn layer (instead of holding it)", isOn: device.fnToggle)
            }
            .toggleStyle(.switch).tint(Theme.accent)
            Text("These settings are stored on the keyboard. Press Save to Keyboard to apply them.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
    }
}

// MARK: - Profiles

struct ProfilesPage: View {
    @ObservedObject var app: AppModel
    @State private var renaming: UUID?
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("My Profiles").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Button { importProfile() } label: { Label("Import Profile", systemImage: "square.and.arrow.down") }
                    .buttonStyle(SoftButtonStyle())
                Button { app.newProfile() } label: { Label("New Profile", systemImage: "plus") }
                    .buttonStyle(SoftButtonStyle())
            }
            Card(title: "Profiles for the \(app.model.name)",
                 subtitle: app.model == .f75Pro
                    ? "Each keyboard keeps its own profiles. The F75 Pro shows the active profile live while the app runs."
                    : "Each keyboard keeps its own profiles. The S75 Pro stores one set of settings: Save to Keyboard writes the active profile.") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 14)], spacing: 14) {
                    ForEach(app.profiles(for: app.model)) { p in row(p) }
                }
            }
        }
    }

    private func row(_ p: Profile) -> some View {
        let active = p.id == app.profile.id
        return HStack(spacing: 14) {
            Circle().fill(Theme.cardRaised).frame(width: 44, height: 44)
                .overlay(Circle().stroke(active ? Theme.accent : Color(red: 0.25, green: 0.35, blue: 1), lineWidth: 2.5))
                .overlay(Image(systemName: "keyboard").foregroundStyle(Theme.text))
            if renaming == p.id {
                TextField("Name", text: $newName, onCommit: { app.rename(p.id, to: newName); renaming = nil })
                    .textFieldStyle(.roundedBorder).frame(width: 180)
            } else {
                Text(p.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
            }
            if active { Chip(text: "ACTIVE", color: Theme.accent) }
            Spacer()
            if !active { Button("Activate") { app.activate(p.id) }.buttonStyle(SoftButtonStyle()) }
            Menu {
                Button("Rename") { newName = p.name; renaming = p.id }
                Button("Duplicate") { app.duplicate(p.id) }
                Button("Export…") { export(p) }
                Divider()
                Button("Delete", role: .destructive) { app.delete(p.id) }.disabled(app.profiles(for: p.model).count <= 1)
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardRaised.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? Theme.accent : Theme.stroke))
    }

    private func export(_ p: Profile) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(p.name) (\(p.model.name)).json"
        if panel.runModal() == .OK, let url = panel.url { app.exportProfile(p.id, to: url) }
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url { app.importProfile(from: url) }
    }
}

// MARK: - App settings

struct AppSettingsPage: View {
    @ObservedObject var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "Permissions") {
                permissionRow("Input Monitoring", "Needed to talk to both keyboards over USB.",
                              ok: app.hub.permissionGranted, link: SystemLinks.inputMonitoring)
                permissionRow("Screen & System Audio Recording", "Only for Music Rhythm listening to the Mac's sound.",
                              ok: nil, link: SystemLinks.screenRecording)
                permissionRow("Microphone", "Only for Music Rhythm using the microphone.", ok: nil, link: SystemLinks.microphone)
            }
            Card(title: "S75 Pro simulator",
                 subtitle: "Try every S75 Pro feature without the keyboard. Saves and uploads run through the real protocol code and are logged below, but nothing leaves the Mac.") {
                Toggle("Simulate an S75 Pro", isOn: Binding(get: { app.simulateS75 }, set: { app.simulateS75 = $0 }))
                    .toggleStyle(.switch).tint(Theme.accent)
                Button("Rewrite everything on next save") { app.markS75Unsaved() }.buttonStyle(SoftButtonStyle())
            }
            Card(title: "Packet log", subtitle: "The S75 Pro configuration reports sent (->) and replies received (<-), first 16 bytes of each.") {
                HStack {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(app.packetLog.joined(separator: "\n"), forType: .string)
                    }
                    Button("Clear") { app.clearLog() }
                }
                .buttonStyle(SoftButtonStyle())
                ScrollView {
                    Text(app.packetLog.isEmpty ? "Nothing sent yet." : app.packetLog.suffix(200).joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .frame(height: 220)
                .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
            }
            Card(title: "Data") {
                Text("Profiles are saved in \(ProfileStore.fileURL.path)").font(.callout).foregroundStyle(Theme.secondary).textSelection(.enabled)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([ProfileStore.fileURL]) }.buttonStyle(SoftButtonStyle())
            }
        }
    }

    private func permissionRow(_ title: String, _ detail: String, ok: Bool?, link: String) -> some View {
        HStack {
            Image(systemName: ok == nil ? "circle.dashed" : (ok! ? "checkmark.circle.fill" : "xmark.circle.fill"))
                .foregroundStyle(ok == nil ? Theme.secondary : (ok! ? Theme.good : Theme.bad))
            VStack(alignment: .leading) {
                Text(title).foregroundStyle(Theme.text)
                Text(detail).font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button("Open Settings") { SystemLinks.open(link) }.buttonStyle(SoftButtonStyle())
        }
    }
}

// MARK: - Help

struct HelpPage: View {
    @ObservedObject var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "Getting started") {
                bullet("Plug the keyboard in with a USB cable and switch it to wired mode. Wireless modes can't be configured.")
                bullet("Choose your keyboard at the top of the sidebar. Each keyboard keeps its own profiles.")
                bullet("F75 Pro: lighting runs live from the app, so leave AULA Studio running. It sits in the menu bar when the window is closed.")
                bullet("S75 Pro: changes are stored on the keyboard. Edit, then press Save to Keyboard (⌘S).")
            }
            Card(title: "What each keyboard supports") {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow { Text("").gridColumnAlignment(.leading); Text("F75 Pro").bold(); Text("S75 Pro").bold() }
                    row("Per-key colours", "Live", "Saved on keyboard")
                    row("Lighting effects", "8 live + 18 built-in", "20 built-in effects")
                    row("Music Rhythm", "Yes", "—")
                    row("Key remapping", "Default + FN1 (keys, media)", "Main + Fn layers")
                    row("Macros", "—", "Up to 100")
                    row("Sleep timer", "Yes", "Yes")
                    row("Response time, key locks", "—", "Yes")
                    row("Screen GIFs and clock", "No screen", "Yes")
                    row("Hall-effect actuation, rapid trigger", "Not hall effect", "Not hall effect")
                }
                .foregroundStyle(Theme.text)
            }
            Card(title: "Troubleshooting") {
                bullet("“Needs permission”: allow AULA Studio in System Settings → Privacy & Security → Input Monitoring, then reopen it.")
                bullet("F75 Pro lights go back to normal: the app has to keep running for live effects.")
                bullet("S75 Pro save fails: check the cable and wired mode, then try again. Use App Settings → Rewrite everything on next save to resend all settings.")
            }
            Card(title: "Credits") {
                Text("F75 Pro direct lighting from OpenRGB's SinowealthKeyboard10c work. S75 Pro protocol from thibaultmiclo/aula-driver (MIT), built for the EA75MAX, which uses the same configuration. Layout ideas from Wootility. Not affiliated with AULA, Epomaker or Wooting.")
                    .foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(Theme.accent)
            Text(s).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ a: String, _ b: String, _ c: String) -> some View {
        GridRow {
            Text(a)
            Text(b).foregroundStyle(Theme.secondary)
            Text(c).foregroundStyle(Theme.secondary)
        }
    }
}
