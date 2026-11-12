import AppKit
import AulaCore
import Foundation
import QuartzCore

enum Page: String, CaseIterable, Identifiable {
    case profiles, lighting, remap, macros, screen, device, appSettings, help
    var id: String { rawValue }

    var title: String {
        switch self {
        case .profiles: return "My Profiles"
        case .lighting: return "RGB Settings"
        case .remap: return "Remap"
        case .macros: return "Macros"
        case .screen: return "Screen"
        case .device: return "Keyboard Settings"
        case .appSettings: return "App Settings"
        case .help: return "Help"
        }
    }

    var symbol: String {
        switch self {
        case .profiles: return "square.grid.2x2"
        case .lighting: return "light.max"
        case .remap: return "keyboard.badge.ellipsis"
        case .macros: return "record.circle"
        case .screen: return "photo.on.rectangle"
        case .device: return "slider.horizontal.3"
        case .appSettings: return "gearshape"
        case .help: return "questionmark.circle"
        }
    }

    /// Whether the page applies to a keyboard.
    func availability(for model: KeyboardModel) -> Availability {
        let caps = model.capabilities
        switch self {
        case .profiles, .lighting, .appSettings, .help: return .available
        case .remap: return caps.contains(.remap) ? .available : .notOnThisKeyboard
        case .macros: return caps.contains(.macros) ? .available : .notOnThisKeyboard
        case .device: return caps.contains(.deviceSettings) ? .available : .notOnThisKeyboard
        case .screen: return caps.contains(.screen) ? .available : .notOnThisKeyboard
        }
    }

    enum Availability { case available, notOnThisKeyboard }
}

enum RemapLayer: String, CaseIterable, Identifiable {
    case base, fn
    var id: String { rawValue }
    var title: String { self == .base ? "Main Layer" : "Fn Layer" }
}

enum Activity: Equatable {
    case idle
    case working(String, progress: Double?)
    case done(String)
    case failed(String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var store: StoreData
    @Published private(set) var status: [KeyboardModel: ConnectionStatus] = [:]
    @Published var page: Page = .lighting
    @Published var selectedKeys: Set<Int> = []
    @Published var remapLayer: RemapLayer = .base
    /// Colours shown on the on-screen keyboard, indexed by LED slot.
    @Published private(set) var preview: [Int: RGB] = [:]
    @Published private(set) var activity: Activity = .idle
    @Published private(set) var packetLog: [String] = []
    @Published var audioError: String?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    let hub = HIDHub()
    private let engine = LiveEngine()
    private let audio = AudioAnalyzer()
    private var timer: Timer?
    private var lastF75Frame: [RGB]?
    private var lastF75Send: CFTimeInterval = 0
    private var undoStack: [Profile] = []
    private var redoStack: [Profile] = []
    private var lastUndoPush: CFTimeInterval = 0
    private var saveWork: DispatchWorkItem?
    private let deviceQueue = DispatchQueue(label: "aula.s75.ops")
    private lazy var simulator = SimulatedS75()

    init() {
        store = ProfileStore.load()
        for m in KeyboardModel.allCases { status[m] = .disconnected }
        hub.onStatusChange = { [weak self] model, status in
            Task { @MainActor in self?.statusChanged(model, status) }
        }
        hub.onKeyDown = { [weak self] usage in
            Task { @MainActor in
                guard let self else { return }
                self.engine.keyDown(usage, lighting: self.profile(for: .f75Pro).lighting)
            }
        }
        audio.onLevels = { [weak self] levels in
            guard let self else { return }
            self.engine.audio = levels
            if levels.beat { self.engine.audioBeat() }
        }
        audio.onError = { [weak self] message in self?.audioError = message }
        hub.start()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        updateAudio()
    }

    // MARK: Keyboard selection and profiles

    var model: KeyboardModel {
        get { store.selectedModel }
        set {
            guard newValue != store.selectedModel else { return }
            store.selectedModel = newValue
            selectedKeys = []
            resetUndo()
            if page.availability(for: newValue) == .notOnThisKeyboard { page = .lighting }
            persist()
        }
    }

    func status(of model: KeyboardModel) -> ConnectionStatus {
        if model == .s75Pro, store.simulateS75 { return .simulated }
        return status[model] ?? .disconnected
    }

    var currentStatus: ConnectionStatus { status(of: model) }

    func profiles(for model: KeyboardModel) -> [Profile] { store.profiles.filter { $0.model == model } }

    func profile(for model: KeyboardModel) -> Profile {
        let id = store.active[model.rawValue]
        return store.profiles.first { $0.id == id } ?? store.profiles.first { $0.model == model }!
    }

    /// The active profile of the selected keyboard. Setting it records undo history.
    var profile: Profile {
        get { profile(for: model) }
        set { update(newValue) }
    }

    private func update(_ newValue: Profile, recordUndo: Bool = true) {
        guard let i = store.profiles.firstIndex(where: { $0.id == newValue.id }) else { return }
        let old = store.profiles[i]
        guard old != newValue else { return }
        if recordUndo {
            // Coalesce rapid edits (slider drags, paint strokes) into one undo step.
            let now = CACurrentMediaTime()
            if now - lastUndoPush > 0.6 { undoStack.append(old); if undoStack.count > 100 { undoStack.removeFirst() } }
            lastUndoPush = now
            redoStack.removeAll()
        }
        store.profiles[i] = newValue
        refreshUndoFlags()
        if newValue.model == .f75Pro { updateAudio() }
        persistSoon()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(profile)
        update(previous, recordUndo: false)
        lastUndoPush = 0
        refreshUndoFlags()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(profile)
        update(next, recordUndo: false)
        refreshUndoFlags()
    }

    private func resetUndo() { undoStack.removeAll(); redoStack.removeAll(); refreshUndoFlags() }
    private func refreshUndoFlags() { canUndo = !undoStack.isEmpty; canRedo = !redoStack.isEmpty }

    func activate(_ id: UUID) {
        guard let p = store.profiles.first(where: { $0.id == id }) else { return }
        store.active[p.model.rawValue] = id
        resetUndo()
        selectedKeys = []
        updateAudio()
        persist()
    }

    func newProfile() {
        var p = Profile(name: uniqueName("New Profile"), model: model)
        p.lighting.layout = profile.lighting.layout
        store.profiles.append(p)
        activate(p.id)
    }

    func duplicate(_ id: UUID) {
        guard var p = store.profiles.first(where: { $0.id == id }) else { return }
        p.id = UUID()
        p.name = uniqueName(p.name + " copy")
        store.profiles.append(p)
        activate(p.id)
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = store.profiles.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.profiles[i].name = trimmed
        persist()
    }

    func delete(_ id: UUID) {
        guard let p = store.profiles.first(where: { $0.id == id }), profiles(for: p.model).count > 1 else { return }
        store.profiles.removeAll { $0.id == id }
        store.lastApplied[id] = nil
        if store.active[p.model.rawValue] == id { store.active[p.model.rawValue] = profiles(for: p.model)[0].id }
        resetUndo()
        persist()
    }

    func exportProfile(_ id: UUID, to url: URL) {
        guard let p = store.profiles.first(where: { $0.id == id }) else { return }
        do { try ProfileStore.export(p, to: url); activity = .done("Exported “\(p.name)”.") }
        catch { activity = .failed("Couldn't export: \(error.localizedDescription)") }
    }

    func importProfile(from url: URL) {
        do {
            var p = try ProfileStore.importProfile(from: url)
            p.name = uniqueName(p.name, model: p.model)
            store.profiles.append(p)
            if p.model != model { model = p.model }
            activate(p.id)
            activity = .done("Imported “\(p.name)” for the \(p.model.name).")
        } catch {
            activity = .failed("That file isn't an AULA Studio profile (\(error.localizedDescription)).")
        }
    }

    private func uniqueName(_ base: String, model: KeyboardModel? = nil) -> String {
        let names = Set(profiles(for: model ?? self.model).map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    var simulateS75: Bool {
        get { store.simulateS75 }
        set { store.simulateS75 = newValue; persist() }
    }

    /// Menu-bar shortcut: change the F75 Pro's live effect whichever keyboard is selected.
    func setF75Effect(_ effect: AppEffect) {
        var p = profile(for: .f75Pro)
        p.lighting.appEffect = effect
        update(p, recordUndo: model == .f75Pro)
    }

    // MARK: Editing helpers

    func paint(keys: [KeyDef], colour: RGB) {
        var p = profile
        for k in keys { p.lighting.paint[k.led] = colour }
        if model == .f75Pro { p.lighting.appEffect = .custom } else { p.lighting.useCustomColours = true }
        profile = p
    }

    func fillAll(_ colour: RGB) {
        var p = profile
        p.lighting.paint = Dictionary(uniqueKeysWithValues: currentKeys.map { ($0.led, colour) })
        if model == .f75Pro { p.lighting.appEffect = .custom } else { p.lighting.useCustomColours = true }
        profile = p
    }

    var currentKeys: [KeyDef] {
        model == .f75Pro ? model.layout.keys(for: profile.lighting.layout) : model.layout.keys
    }

    func remap(_ action: KeyAction, keys: [KeyDef]) {
        var p = profile
        for k in keys where !k.fnLocked && k.remapIndex >= 0 {
            if remapLayer == .base { p.remapBase[k.remapIndex] = action.kind == .default ? nil : action }
            else { p.remapFn[k.remapIndex] = action.kind == .default ? nil : action }
        }
        profile = p
    }

    func action(for key: KeyDef) -> KeyAction {
        (remapLayer == .base ? profile.remapBase : profile.remapFn)[key.remapIndex] ?? .default
    }

    /// Removes a macro and fixes remaps that point at macros after it.
    func deleteMacro(at index: Int) {
        var p = profile
        guard p.macros.indices.contains(index) else { return }
        p.macros.remove(at: index)
        func fix(_ table: [Int: KeyAction]) -> [Int: KeyAction] {
            table.compactMapValues { a in
                guard a.kind == .macro else { return a }
                if a.macro == index { return nil }
                var b = a
                if a.macro > index { b.macro -= 1 }
                return b
            }
        }
        p.remapBase = fix(p.remapBase)
        p.remapFn = fix(p.remapFn)
        profile = p
    }

    // MARK: Live lighting (F75 Pro) and previews

    private func statusChanged(_ model: KeyboardModel, _ s: ConnectionStatus) {
        status[model] = s
        if model == .f75Pro { lastF75Frame = nil }
    }

    private func updateAudio() {
        let lighting = profile(for: .f75Pro).lighting
        audio.sensitivity = Float(lighting.sensitivity)
        if lighting.appEffect == .music {
            audioError = nil
            if audio.source != lighting.audioSource { audio.start(lighting.audioSource) }
        } else if audio.source != nil {
            audio.stop()
        }
    }

    private func tick() {
        let f75 = profile(for: .f75Pro).lighting
        engine.onboard = profile(for: .f75Pro).f75Onboard
        // The onboard preview carries its own brightness; don't dim it twice.
        let frame = engine.frame(f75, applyBrightness: f75.appEffect != .keyboardOwn)
        if case .connected = status(of: .f75Pro), f75.appEffect != .keyboardOwn {
            // Animated effects send every tick; static ones on change plus a keepalive,
            // because the keyboard reverts to its own effect after about a second.
            let now = CACurrentMediaTime()
            if frame != lastF75Frame || now - lastF75Send > 0.5 {
                hub.sendF75Frame(frame)
                lastF75Frame = frame
                lastF75Send = now
            }
        } else {
            lastF75Frame = nil
        }

        var next: [Int: RGB] = [:]
        if model == .f75Pro {
            for k in currentKeys { next[k.led] = frame[k.led] }
        } else {
            next = s75Preview(profile.lighting)
        }
        if next != preview { preview = next }
    }

    /// An approximation of the S75 Pro's lighting for the on-screen keyboard.
    private func s75Preview(_ l: LightingConfig) -> [Int: RGB] {
        let keys = KeyboardModel.s75Pro.layout.keys
        let bounds = KeyboardModel.s75Pro.layout.bounds
        let t = CACurrentMediaTime()
        let k = Double(l.brightnessLevel) / 5
        var out: [Int: RGB] = [:]
        for key in keys {
            let c: RGB
            if l.useCustomColours {
                c = l.paint[key.led] ?? .black
            } else if l.hardwareEffect == .off {
                c = .black
            } else if l.rainbow || !l.hardwareEffect.usesColour {
                let x = (key.rect.midX - bounds.minX) / bounds.width
                c = Colour.hsv(x - (l.hardwareEffect.usesSpeed ? t * 0.1 * Double(l.speedLevel) : 0), 1, 1)
            } else if l.hardwareEffect == .breath {
                c = Colour.scale(l.colour, 0.15 + 0.85 * (sin(t * (1 + Double(l.speedLevel))) + 1) / 2)
            } else {
                c = l.colour
            }
            out[key.led] = Colour.scale(c, k)
        }
        return out
    }

    // MARK: S75 Pro: saving to the keyboard

    /// Sections of the active S75 Pro profile that differ from what was last written.
    var s75Changes: [String] {
        let p = profile(for: .s75Pro)
        guard let last = store.lastApplied[p.id] else { return ["everything"] }
        var out: [String] = []
        if p.lighting != last.lighting { out.append("lighting") }
        if p.macros != last.macros { out.append("macros") }
        if p.remapBase != last.remapBase || p.remapFn != last.remapFn { out.append("key remaps") }
        if p.device != last.device { out.append("keyboard settings") }
        return out
    }

    /// Onboard sections of the active F75 Pro profile that differ from what was last
    /// written. Before the first save, only sections the profile actually changed.
    var f75Changes: [String] {
        let p = profile(for: .f75Pro)
        let last = store.lastApplied[p.id]
        var out: [String] = []
        if last.map({ $0.f75 != p.f75 }) ?? (p.f75 != nil) { out.append("onboard lighting and sleep") }
        let remapsChanged = last.map { $0.remapBase != p.remapBase || $0.remapFn != p.remapFn }
            ?? (!p.remapBase.isEmpty || !p.remapFn.isEmpty)
        if remapsChanged { out.append("key remaps") }
        return out
    }

    /// Unsaved onboard changes for the selected keyboard.
    var unsavedChanges: [String] { model == .f75Pro ? f75Changes : s75Changes }

    func saveToKeyboard() {
        switch model {
        case .f75Pro: saveF75()
        case .s75Pro: saveS75()
        }
    }

    var isBusy: Bool { if case .working = activity { return true } else { return false } }

    // MARK: F75 Pro: saving to the keyboard

    /// Writes the F75 Pro's onboard settings in the same order AULA's driver does:
    /// palette (0a), read settings (84), write settings (04), then the four key
    /// pages (03). Only sections that changed are written.
    func saveF75() {
        let p = profile(for: .f75Pro)
        let last = store.lastApplied[p.id]
        let cfg = p.f75Onboard
        let changes = f75Changes
        let writeSettings = changes.contains("onboard lighting and sleep")
        let pages: [[UInt8]]?
        do {
            pages = changes.contains("key remaps") ? try F75Onboard.keymapPages(base: p.remapBase, fn: p.remapFn) : nil
        } catch {
            activity = .failed(error.localizedDescription); return
        }
        guard let effect = F75Onboard.effects.first(where: { $0.id == cfg.effect }) else {
            activity = .failed("Unknown F75 effect \(cfg.effect)."); return
        }
        let hub = self.hub
        let live = p.lighting.appEffect != .keyboardOwn
        appendLog("== save F75 “\(p.name)”: \(changes.joined(separator: ", "))")
        activity = .working("Saving to keyboard…", progress: nil)

        deviceQueue.async { [weak self] in
            func log(_ dir: String, _ r: [UInt8]) {
                let line = dir + " " + r.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
                Task { @MainActor in self?.appendLog(line) }
            }
            do {
                try hub.f75Transaction { ch in
                    func send(_ r: [UInt8]) throws { log("->", r); try ch.set(r) }
                    if writeSettings {
                        self?.report("Writing lighting and sleep…")
                        let useRainbow = effect.hasRainbow && cfg.rainbow
                        var palette = F75Captured.factoryPalette
                        if effect.hasColour && !useRainbow {
                            palette = F75Onboard.setPaletteColour(palette, effect: cfg.effect, slot: 0, colour: cfg.colour)
                        }
                        try send(F75Onboard.paletteWrite(palette))
                        try send(F75Onboard.readSettingsRequest)
                        let reply = try ch.get()
                        log("<-", reply)
                        let block = try F75Onboard.settingsBlock(fromReply: reply)
                        var s = F75Onboard.decode(block)
                        s.effect = cfg.effect
                        s.brightness = min(max(cfg.brightness, 0), F75Onboard.maxBrightness)
                        s.speed = min(max(cfg.speed, 0), F75Onboard.maxSpeed)
                        s.colourSlot = useRainbow ? Int(F75Onboard.rainbowSlot)
                            : (effect.hasColour ? 0 : F75Onboard.colourSlot(in: block, effect: cfg.effect))
                        s.sleepUnits = Int(F75Onboard.sleepUnits(seconds: cfg.sleepSeconds))
                        try send(F75Onboard.settingsWrite(try F75Onboard.apply(s, to: block)))
                    }
                    if let pages {
                        for (i, page) in pages.enumerated() {
                            self?.report("Writing key layer \(i + 1) of \(pages.count)…", progress: Double(i + 1) / Double(pages.count))
                            try send(F75Onboard.keymapWrite(page: i, page))
                        }
                    }
                }
                Task { @MainActor in
                    guard let self else { return }
                    var applied = last ?? p
                    if writeSettings { applied.f75 = p.f75 }
                    if pages != nil { applied.remapBase = p.remapBase; applied.remapFn = p.remapFn }
                    self.store.lastApplied[p.id] = applied
                    self.persist()
                    self.activity = .done(live && writeSettings
                        ? "Saved to the keyboard. Choose “Keyboard's own lighting” to see the saved effect; live effects cover it while they run."
                        : "Saved to the keyboard.")
                }
            } catch {
                Task { @MainActor in self?.activity = .failed("Save stopped: \(error.localizedDescription)") }
            }
        }
    }

    private func makeExecutor() throws -> S75Executor {
        let transport: S75Transport = store.simulateS75 ? simulator : try hub.makeS75Transport()
        return S75Executor(transport: transport) { [weak self] line in
            Task { @MainActor in self?.appendLog(line) }
        }
    }

    private func appendLog(_ line: String) {
        packetLog.append(line)
        if packetLog.count > 400 { packetLog.removeFirst(packetLog.count - 400) }
    }

    func clearLog() { packetLog.removeAll() }

    func saveS75() {
        let p = profile(for: .s75Pro)
        let last = store.lastApplied[p.id]
        let executor: S75Executor
        do { executor = try makeExecutor() } catch { activity = .failed(error.localizedDescription); return }
        appendLog("== save “\(p.name)”\(store.simulateS75 ? " (simulated)" : "")")
        activity = .working("Saving to keyboard…", progress: nil)

        deviceQueue.async { [weak self] in
            do {
                let l = p.lighting
                let macrosChanged = last?.macros != p.macros
                if macrosChanged {
                    self?.report("Writing macros…")
                    try executor.run(try S75Protocol.setMacros(p.macros))
                }
                // Remaps refer to macros by position, so rewrite them when macros change.
                if macrosChanged || last?.remapBase != p.remapBase {
                    self?.report("Writing main layer…")
                    try executor.run(try S75Protocol.setRemap(p.remapBase, fnLayer: false))
                }
                if macrosChanged || last?.remapFn != p.remapFn {
                    self?.report("Writing Fn layer…")
                    try executor.run(try S75Protocol.setRemap(p.remapFn, fnLayer: true))
                }
                if last?.lighting != l {
                    self?.report("Writing lighting…")
                    if l.useCustomColours {
                        try executor.run(try S75Protocol.setPerKey(l.paint, brightness: l.brightnessLevel))
                    } else {
                        try executor.run(S75Protocol.setLighting(effect: l.hardwareEffect, colour: l.colour, rainbow: l.rainbow,
                                                                 brightness: l.brightnessLevel, speed: l.speedLevel,
                                                                 direction: l.direction))
                    }
                }
                if last?.device != p.device {
                    self?.report("Writing keyboard settings…")
                    try executor.run(S75Protocol.setFunction(p.device))
                }
                Task { @MainActor in
                    guard let self else { return }
                    self.store.lastApplied[p.id] = p
                    self.persist()
                    self.activity = .done(self.store.simulateS75 ? "Simulated save finished. See the packet log in App Settings."
                                                                  : "Saved to the keyboard.")
                }
            } catch {
                Task { @MainActor in self?.activity = .failed("Save stopped: \(error.localizedDescription)") }
            }
        }
    }

    /// Forget what was written, so the next save rewrites everything.
    func markS75Unsaved() {
        store.lastApplied[profile(for: .s75Pro).id] = nil
        persist()
    }

    nonisolated private func report(_ message: String, progress: Double? = nil) {
        Task { @MainActor in self.activity = .working(message, progress: progress) }
    }

    func syncClock() {
        let executor: S75Executor
        do { executor = try makeExecutor() } catch { activity = .failed(error.localizedDescription); return }
        activity = .working("Setting the keyboard's clock…", progress: nil)
        deviceQueue.async { [weak self] in
            do {
                try executor.run(S75Protocol.syncClock(Date()))
                Task { @MainActor in self?.activity = .done("The keyboard's clock now matches this Mac.") }
            } catch {
                Task { @MainActor in self?.activity = .failed("Clock sync failed: \(error.localizedDescription)") }
            }
        }
    }

    func uploadScreen(_ animation: ScreenEncoder.Animation) {
        let buffer: [UInt8]
        let executor: S75Executor
        do {
            buffer = try ScreenEncoder.buildBuffer(animation)
            try ScreenEncoder.validate(buffer)
            executor = try makeExecutor()
        } catch {
            activity = .failed(error.localizedDescription); return
        }
        activity = .working("Uploading to the screen…", progress: 0)
        deviceQueue.async { [weak self] in
            do {
                let acked = try executor.uploadScreen(buffer) { done, total in
                    self?.report("Uploading to the screen… \(done)/\(total)", progress: Double(done) / Double(total))
                }
                let pages = buffer.count / ScreenEncoder.pageSize
                Task { @MainActor in
                    self?.activity = acked == pages
                        ? .done("Uploaded \(animation.frames.count) frame\(animation.frames.count == 1 ? "" : "s") to the screen.")
                        : .failed("Upload finished, but the keyboard confirmed only \(acked) of \(pages) pages.")
                }
            } catch {
                Task { @MainActor in self?.activity = .failed("Upload stopped: \(error.localizedDescription)") }
            }
        }
    }

    func dismissActivity() { if !isBusy { activity = .idle } }

    // MARK: Persistence

    private func persist() { saveWork?.cancel(); ProfileStore.save(store) }

    private func persistSoon() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in if let self { ProfileStore.save(self.store) } }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
