import AppKit
import AulaCore
import SwiftUI
import UniformTypeIdentifiers

struct ScreenPage: View {
    @ObservedObject var app: AppModel
    @State private var animation: ScreenEncoder.Animation?
    @State private var sourceFrames = 0
    @State private var loadError: String?
    @State private var confirmUpload = false

    private var screen: Binding<ScreenConfig> {
        Binding(get: { app.profile.screen }, set: { var p = app.profile; p.screen = $0; app.profile = p })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Screen").font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.text)
            HStack(alignment: .top, spacing: 18) {
                Card(title: "Preview", subtitle: "135 × 240, as the keyboard shows it") {
                    preview.frame(maxWidth: .infinity)
                }
                .frame(width: 330)
                VStack(spacing: 18) {
                    Card(title: "Animation", subtitle: "Import a GIF or picture. Up to \(ScreenEncoder.maxFrames) frames, \(ScreenEncoder.minDelayMs)-\(ScreenEncoder.maxDelayMs) ms each.") {
                        HStack {
                            Button("Import GIF or image…") { pick() }.buttonStyle(AccentButtonStyle())
                            if let path = screen.wrappedValue.sourcePath {
                                Text(URL(fileURLWithPath: path).lastPathComponent).foregroundStyle(Theme.secondary).lineLimit(1)
                            }
                        }
                        Picker("Fit", selection: screen.fit) { ForEach(ScreenFit.allCases) { Text($0.title).tag($0) } }
                            .pickerStyle(.segmented).frame(width: 360)
                            .onChange(of: screen.wrappedValue.fit) { _ in reload() }
                        if let loadError { Banner(kind: .error, text: loadError) }
                        if let animation {
                            if sourceFrames > animation.frames.count {
                                Banner(kind: .info, text: "The GIF has \(sourceFrames) frames; the keyboard holds \(ScreenEncoder.maxFrames). Frames were dropped evenly and their time added to the rest, so it plays at the same speed.")
                            }
                            frameStrip(animation)
                            HStack {
                                Text("Set every frame to")
                                ForEach([50, 100, 200], id: \.self) { ms in
                                    Button("\(ms) ms") { setAllDelays(ms) }.buttonStyle(SoftButtonStyle())
                                }
                            }
                        }
                    }
                    Card(title: "Keyboard") {
                        HStack(spacing: 12) {
                            Button("Upload to keyboard") { confirmUpload = true }
                                .buttonStyle(AccentButtonStyle(enabled: canUpload)).disabled(!canUpload)
                            Button("Sync time with this Mac") { app.syncClock() }
                                .buttonStyle(SoftButtonStyle()).disabled(!app.currentStatus.isUsable || app.isBusy)
                        }
                        Text("Uploading replaces the screen animation on the keyboard and takes about a minute for a long GIF. Keep the cable connected until it finishes. "
                             + "Switching between the screen's clock, battery and animation pages is done on the keyboard itself (see its manual).")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
        .onAppear { if animation == nil { reload() } }
        .alert("Upload to the S75 Pro's screen?", isPresented: $confirmUpload) {
            Button("Upload") { if let a = currentAnimation() { app.uploadScreen(a) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This writes \(animation?.frames.count ?? 0) frame(s) to the keyboard's flash memory. S75 Pro support is experimental and hasn't been tested on this keyboard yet. "
                 + "AULA Studio checks the size so the upload can never pass the \(ScreenEncoder.maxFrames)-frame limit.")
        }
    }

    private var canUpload: Bool { animation != nil && app.currentStatus.isUsable && !app.isBusy }

    private func currentAnimation() -> ScreenEncoder.Animation? {
        guard var a = animation else { return nil }
        let delays = screen.wrappedValue.delays
        if delays.count == a.frames.count { a.delays = delays }
        return a
    }

    // MARK: Preview

    private var preview: some View {
        TimelineView(.animation) { context in
            let frame = currentFrame(at: context.date)
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.black)
                if let frame {
                    Image(decorative: frame, scale: 1).resizable().interpolation(.none).aspectRatio(contentMode: .fit).padding(6)
                } else {
                    Text("No animation").foregroundStyle(Theme.secondary)
                }
            }
            .frame(width: 135 * 1.8 + 12, height: 240 * 1.8 + 12)
        }
    }

    private func currentFrame(at date: Date) -> CGImage? {
        guard let a = animation, !a.frames.isEmpty else { return nil }
        let delays = screen.wrappedValue.delays.count == a.frames.count ? screen.wrappedValue.delays : a.delays
        let total = max(1, delays.reduce(0, +))
        var t = Int(date.timeIntervalSinceReferenceDate * 1000) % total
        for (i, d) in delays.enumerated() {
            if t < d { return a.frames[i] }
            t -= d
        }
        return a.frames.last
    }

    private func frameStrip(_ a: ScreenEncoder.Animation) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(Array(a.frames.enumerated()), id: \.offset) { i, frame in
                    VStack(spacing: 4) {
                        Image(decorative: frame, scale: 1).resizable().aspectRatio(contentMode: .fit).frame(height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        TextField("", value: delayBinding(i), format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 56).font(.system(size: 11))
                        Text("#\(i + 1)").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                }
            }
            .padding(.bottom, 6)
        }
        .frame(height: 140)
    }

    private func delayBinding(_ i: Int) -> Binding<Int> {
        Binding(get: { screen.wrappedValue.delays.indices.contains(i) ? screen.wrappedValue.delays[i] : 100 },
                set: { v in
                    var s = screen.wrappedValue
                    guard s.delays.indices.contains(i) else { return }
                    s.delays[i] = min(ScreenEncoder.maxDelayMs, max(ScreenEncoder.minDelayMs, v))
                    screen.wrappedValue = s
                })
    }

    private func setAllDelays(_ ms: Int) {
        guard let a = animation else { return }
        var s = screen.wrappedValue
        s.delays = Array(repeating: ms, count: a.frames.count)
        screen.wrappedValue = s
    }

    // MARK: Loading

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.gif, .png, .jpeg, .heic, .webP, .bmp, .tiff]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var s = screen.wrappedValue
        s.sourcePath = url.path
        s.delays = []
        screen.wrappedValue = s
        reload()
    }

    private func reload() {
        loadError = nil
        guard let path = screen.wrappedValue.sourcePath else { animation = nil; return }
        do {
            let full = try ScreenEncoder.load(url: URL(fileURLWithPath: path), fit: screen.wrappedValue.fit)
            sourceFrames = full.frames.count
            let (frames, delays) = ScreenEncoder.trim(full.frames, full.delays)
            let clamped = delays.map { min(ScreenEncoder.maxDelayMs, max(ScreenEncoder.minDelayMs, $0)) }
            animation = ScreenEncoder.Animation(frames: frames, delays: clamped)
            if screen.wrappedValue.delays.count != frames.count {
                var s = screen.wrappedValue
                s.delays = clamped
                screen.wrappedValue = s
            }
        } catch {
            animation = nil
            loadError = error.localizedDescription
        }
    }
}
