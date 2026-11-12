import AulaCore
import SwiftUI

struct RootView: View {
    @ObservedObject var app: AppModel

    var body: some View {
        HStack(spacing: 0) {
            Rail(app: app)
            if app.page != .appSettings && app.page != .help {
                Sidebar(app: app).frame(width: 290)
            }
            VStack(spacing: 0) {
                TopBar(app: app)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        StatusBanners(app: app)
                        page
                    }
                    .padding(.horizontal, 28).padding(.bottom, 28).padding(.top, 6)
                    .frame(maxWidth: 1180, alignment: .topLeading)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Theme.window)
        }
        .background(Theme.window)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1180, minHeight: 760)
    }

    @ViewBuilder private var page: some View {
        switch app.page.availability(for: app.model) {
        case .notOnThisKeyboard:
            LightingPage(app: app)
        case .available:
            switch app.page {
            case .profiles: ProfilesPage(app: app)
            case .lighting: LightingPage(app: app)
            case .remap: RemapPage(app: app)
            case .macros: MacrosPage(app: app)
            case .screen: ScreenPage(app: app)
            case .device: DeviceSettingsPage(app: app)
            case .appSettings: AppSettingsPage(app: app)
            case .help: HelpPage(app: app)
            }
        }
    }
}

// MARK: - Left rail

struct Rail: View {
    @ObservedObject var app: AppModel

    var body: some View {
        VStack(spacing: 6) {
            AppGlyph().frame(width: 40, height: 40).padding(.top, 14).padding(.bottom, 14)
            railButton("Keyboard", "keyboard", active: app.page != .appSettings && app.page != .help) {
                if app.page == .appSettings || app.page == .help { app.page = .lighting }
            }
            railButton("Settings", "gearshape", active: app.page == .appSettings) { app.page = .appSettings }
            railButton("Help", "questionmark.circle", active: app.page == .help) { app.page = .help }
            Spacer()
        }
        .frame(width: 80)
        .background(Theme.rail)
    }

    private func railButton(_ title: String, _ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 17))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .frame(width: 66, height: 54)
            .foregroundStyle(active ? Theme.text : Theme.secondary)
            .background(RoundedRectangle(cornerRadius: 10).fill(active ? Theme.cardRaised : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The app's mark ("Mixer"): red, green and blue sliders on a graphite tile,
/// matching the app icon drawn by tools/make-icon.swift.
struct AppGlyph: View {
    private let sliders: [(value: CGFloat, colour: Color)] = [
        (0.68, Color(red: 0.886, green: 0.294, blue: 0.29)),
        (0.32, Color(red: 0.592, green: 0.769, blue: 0.349)),
        (0.86, Color(red: 0.216, green: 0.541, blue: 0.867)),
    ]

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            let trackWidth = s * 0.64, thickness = s * 0.055, knob = s * 0.13
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.24, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
                VStack(spacing: s * 0.115) {
                    ForEach(0..<3, id: \.self) { i in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(white: 0.3)).frame(width: trackWidth, height: thickness)
                            Capsule().fill(sliders[i].colour).frame(width: trackWidth * sliders[i].value, height: thickness)
                            Circle().fill(.white).frame(width: knob, height: knob)
                                .offset(x: trackWidth * sliders[i].value - knob / 2)
                        }
                        .frame(width: trackWidth, height: knob)
                    }
                }
            }
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @ObservedObject var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Keyboard Configuration").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 16)
            DevicePicker(app: app).padding(.horizontal, 14)

            group("Profiles") { item(.profiles) }
            group("Keyboard Configuration") {
                ForEach([Page.lighting, .remap, .macros, .screen, .device].filter { $0.availability(for: app.model) == .available }) { item($0) }
            }
            Spacer()
            Text("AULA Studio v\(AppInfo.version)").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity).padding(.bottom, 18)
        }
        .background(Theme.sidebar)
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondary)
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 6)
            content()
        }
    }

    private func item(_ page: Page) -> some View {
        let selected = app.page == page
        return Button { app.page = page } label: {
            HStack(spacing: 12) {
                Image(systemName: page.symbol).frame(width: 20)
                Text(page.title)
                Spacer()
            }
            .font(.system(size: 15, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Theme.text : Theme.text.opacity(0.8))
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.cardRaised : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
}

/// Keyboard chooser card at the top of the sidebar.
struct DevicePicker: View {
    @ObservedObject var app: AppModel
    @State private var open = false

    var body: some View {
        // A button with a popover: macOS menus flatten custom labels to plain text.
        Button { open.toggle() } label: {
            card(app.model, chevron: true)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardRaised))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Choose keyboard").padding(.horizontal, 6)
                ForEach(KeyboardModel.allCases) { model in
                    Button {
                        app.model = model
                        open = false
                    } label: {
                        card(model, chevron: false)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(model == app.model ? Theme.cardRaised : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(model == app.model ? Theme.accent : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(width: 300)
            .background(Theme.sidebar)
        }
    }

    private func card(_ model: KeyboardModel, chevron: Bool) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)).frame(width: 58, height: 58)
                .overlay(MiniKeyboard(model: model).padding(7))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(StatusText.colour(app.status(of: model))).frame(width: 7, height: 7)
                    Text(StatusText.short(app.status(of: model))).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Text(model.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                if model.isExperimental { Chip(text: "EXPERIMENTAL", color: Theme.warn) }
            }
            Spacer()
            if chevron { Image(systemName: "chevron.down").foregroundStyle(Theme.secondary) }
        }
    }
}

struct MiniKeyboard: View {
    let model: KeyboardModel
    var body: some View {
        Canvas { ctx, size in
            let b = model.layout.bounds
            let s = min(size.width / b.width, size.height / b.height)
            let ox = (size.width - b.width * s) / 2, oy = (size.height - b.height * s) / 2
            for (i, k) in model.layout.keys(for: .ansi).enumerated() {
                let r = CGRect(x: ox + (k.rect.minX - b.minX) * s, y: oy + (k.rect.minY - b.minY) * s, width: k.rect.width * s, height: k.rect.height * s)
                ctx.fill(Path(roundedRect: r.insetBy(dx: 0.4, dy: 0.4), cornerRadius: 1),
                         with: .color(Color(hue: Double(i % 24) / 24, saturation: 0.7, brightness: 0.9)))
            }
        }
    }
}

enum StatusText {
    static func short(_ s: ConnectionStatus) -> String {
        switch s {
        case .noPermission: return "Needs permission"
        case .disconnected: return "Not connected"
        case .wirelessOnly: return "Wireless (use cable)"
        case .connected: return "Connected"
        case .simulated: return "Simulated"
        }
    }

    static func colour(_ s: ConnectionStatus) -> Color {
        switch s {
        case .connected: return Theme.good
        case .simulated: return Color(red: 0.4, green: 0.65, blue: 1)
        case .noPermission: return Theme.bad
        default: return Theme.warn
        }
    }
}

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
}

// MARK: - Top bar

struct ProfileAvatar: View {
    var highlighted: Bool
    var body: some View {
        Circle().fill(Theme.cardRaised).frame(width: 42, height: 42)
            .overlay(Circle().stroke(highlighted ? Theme.accent : Color(red: 0.25, green: 0.35, blue: 1), lineWidth: 2.5))
            .overlay(Image(systemName: "keyboard").foregroundStyle(Theme.text))
            .shadow(color: Color(red: 0.25, green: 0.35, blue: 1).opacity(0.6), radius: 8)
    }
}

struct TopBar: View {
    @ObservedObject var app: AppModel
    @State private var profilesOpen = false

    var body: some View {
        HStack(spacing: 14) {
            if app.page == .appSettings || app.page == .help {
                Text(app.page.title).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
            } else {
                profileMenu
                Spacer()
                Button { app.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.plain).foregroundStyle(app.canUndo ? Theme.text : Theme.secondary.opacity(0.5))
                    .disabled(!app.canUndo).keyboardShortcut("z", modifiers: .command).help("Undo")
                Button { app.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .buttonStyle(.plain).foregroundStyle(app.canRedo ? Theme.text : Theme.secondary.opacity(0.5))
                    .disabled(!app.canRedo).keyboardShortcut("z", modifiers: [.command, .shift]).help("Redo")
                    .padding(.trailing, 8)
                trailing
            }
        }
        .font(.system(size: 16))
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(LinearGradient(colors: [Color(red: 0.13, green: 0.13, blue: 0.2), Theme.card], startPoint: .leading, endPoint: .trailing))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 10)
    }

    private var profileMenu: some View {
        // A button with a popover: macOS menus flatten custom labels to plain text.
        Button { profilesOpen.toggle() } label: {
            HStack(spacing: 12) {
                ProfileAvatar(highlighted: false)
                Text(app.profile.name).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text)
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $profilesOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: "\(app.model.name) profiles").padding(.horizontal, 8).padding(.bottom, 4)
                ForEach(app.profiles(for: app.model)) { p in
                    popoverRow(p.name, symbol: p.id == app.profile.id ? "checkmark" : nil) { app.activate(p.id) }
                }
                Divider().padding(.vertical, 4)
                popoverRow("New profile", symbol: "plus") { app.newProfile() }
                popoverRow("Manage profiles…", symbol: "square.grid.2x2") { app.page = .profiles }
            }
            .padding(10)
            .frame(width: 260)
            .background(Theme.sidebar)
        }
    }

    private func popoverRow(_ title: String, symbol: String?, action: @escaping () -> Void) -> some View {
        Button {
            action()
            profilesOpen = false
        } label: {
            HStack {
                Image(systemName: symbol ?? "circle").opacity(symbol == nil ? 0 : 1).frame(width: 18)
                Text(title)
                Spacer()
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var trailing: some View {
        let changes = app.unsavedChanges
        let enabled = !changes.isEmpty && app.currentStatus.isUsable && !app.isBusy
        HStack(spacing: 10) {
            if app.model.capabilities.contains(.liveEffects) {
                let live = app.currentStatus.isUsable && app.profile.lighting.appEffect != .keyboardOwn
                HStack(spacing: 8) {
                    Circle().fill(live ? Theme.good : Theme.secondary).frame(width: 8, height: 8)
                    Text(!app.currentStatus.isUsable ? "Keyboard not connected" : (live ? "Live effect" : "Keyboard's own lighting"))
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.cardRaised))
            }
            if !changes.isEmpty {
                Text("Unsaved: " + changes.joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Button(app.model == .s75Pro && app.store.simulateS75 ? "Save (simulated)" : "Save to Keyboard") { app.saveToKeyboard() }
                .buttonStyle(AccentButtonStyle(enabled: enabled))
                .disabled(!enabled)
                .keyboardShortcut("s", modifiers: .command)
        }
    }
}

// MARK: - Banners

struct StatusBanners: View {
    @ObservedObject var app: AppModel

    var body: some View {
        VStack(spacing: 10) {
            switch app.currentStatus {
            case .noPermission:
                Banner(kind: .error, text: "AULA Studio needs Input Monitoring permission to talk to your keyboard. Turn it on for AULA Studio; the app connects by itself once it is allowed.",
                       buttonTitle: "Open Settings") { SystemLinks.open(SystemLinks.inputMonitoring) }
            case .disconnected where app.page != .appSettings && app.page != .help:
                Banner(kind: .warning, text: "Connect your \(app.model.name) with a USB cable and switch it to wired mode. You can still edit profiles meanwhile."
                       + (app.model == .s75Pro ? " To try the app without the keyboard, turn on the simulator in App Settings." : ""))
            case .wirelessOnly:
                Banner(kind: .warning, text: "The S75 Pro is connected wirelessly. Settings can only be written over a USB cable, so plug it in and switch to wired mode.")
            case .simulated where app.page != .appSettings && app.page != .help:
                Banner(kind: .info, text: "Simulated S75 Pro: saves run through the real protocol code, but nothing is sent to a keyboard. The packets are listed in App Settings.",
                       buttonTitle: "Packet log") { app.page = .appSettings }
            default:
                EmptyView()
            }
            if app.model.isExperimental, app.page != .appSettings, app.page != .help, app.currentStatus != .simulated {
                Banner(kind: .info, text: "S75 Pro support is experimental: it's built from Aula's driver files and an open-source driver for its twin (the EA75MAX), but hasn't been tested on an S75 Pro yet.")
            }
            switch app.activity {
            case .idle: EmptyView()
            case .working(let message, let progress):
                HStack(spacing: 12) {
                    if let progress { ProgressView(value: progress).frame(width: 160).tint(Theme.accent) } else { ProgressView().controlSize(.small) }
                    Text(message).foregroundStyle(Theme.text)
                    Spacer()
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardRaised))
            case .done(let message):
                Banner(kind: .success, text: message, buttonTitle: "OK") { app.dismissActivity() }
            case .failed(let message):
                Banner(kind: .error, text: message, buttonTitle: "OK") { app.dismissActivity() }
            }
        }
    }
}
