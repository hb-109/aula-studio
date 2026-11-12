import Accelerate
import AulaCore
import AVFoundation
import Foundation
import ScreenCaptureKit

/// Listens to the Mac's sound output (ScreenCaptureKit) or the microphone and
/// reports smoothed levels for 16 log-spaced frequency bands, bass first.
final class AudioAnalyzer: NSObject, SCStreamOutput, SCStreamDelegate {
    static let bandCount = 16

    struct Levels {
        var bands = [Float](repeating: 0, count: AudioAnalyzer.bandCount)
        var overall: Float = 0
        /// True for the frame a bass hit is detected.
        var beat = false
    }

    /// Called on the main thread with fresh levels, about 40 times a second.
    var onLevels: ((Levels) -> Void)?
    /// Called on the main thread when capture can't start (usually a permission).
    var onError: ((String) -> Void)?
    var sensitivity: Float = 0.6

    private(set) var source: AudioSource?
    private var stream: SCStream?
    private var engine: AVAudioEngine?
    private let queue = DispatchQueue(label: "aula.audio")

    private let fftSize = 1024
    private let log2n = vDSP_Length(10)
    private lazy var fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    private lazy var window: [Float] = {
        var w = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&w, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        return w
    }()
    private var ring = [Float]()
    private var sampleRate: Float = 48_000
    private var smoothed = [Float](repeating: 0, count: AudioAnalyzer.bandCount)
    private var peak: Float = 1e-4
    private var bassAverage: Float = 0
    private var lastBeat = Date.distantPast

    func start(_ source: AudioSource) {
        guard self.source != source else { return }
        stop()
        self.source = source
        switch source {
        case .system: startSystemCapture()
        case .microphone: startMicrophone()
        }
    }

    func stop() {
        stream?.stopCapture { _ in }
        stream = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        source = nil
        queue.async { self.ring.removeAll() }
    }

    // MARK: Capture

    private func startSystemCapture() {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, error in
            guard let self else { return }
            guard let display = content?.displays.first else {
                self.fail("AULA Studio needs Screen & System Audio Recording permission to hear the Mac's sound. "
                          + "Allow it in System Settings → Privacy & Security, then reopen the app."
                          + (error.map { " (\($0.localizedDescription))" } ?? ""))
                return
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48_000
            config.channelCount = 1
            // Audio is all we want; keep the video side as small and slow as possible.
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            do {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.queue)
            } catch {
                self.fail("Couldn't listen to the Mac's sound: \(error.localizedDescription)")
                return
            }
            stream.startCapture { error in
                if let error { self.fail("Couldn't listen to the Mac's sound: \(error.localizedDescription)") }
            }
            self.stream = stream
        }
    }

    private func startMicrophone() {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { fail("No microphone is available."); return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let data = buffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
            let rate = Float(format.sampleRate)
            self.queue.async { self.sampleRate = rate; self.process(samples) }
        }
        do {
            try engine.start()
            self.engine = engine
        } catch {
            fail("Couldn't use the microphone: \(error.localizedDescription). Check Privacy & Security → Microphone.")
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let format = sampleBuffer.formatDescription?.audioStreamBasicDescription else { return }
        sampleRate = Float(format.mSampleRate)
        var samples = [Float]()
        try? sampleBuffer.withAudioBufferList { list, _ in
            guard let first = list.first, let data = first.mData else { return }
            let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            let channels = max(1, Int(first.mNumberChannels))
            let floats = data.bindMemory(to: Float.self, capacity: count)
            samples = stride(from: 0, to: count, by: channels).map { floats[$0] }
        }
        process(samples)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        fail("Listening stopped: \(error.localizedDescription)")
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async { self.onError?(message) }
    }

    // MARK: Analysis (on `queue`)

    private func process(_ samples: [Float]) {
        ring += samples
        while ring.count >= fftSize {
            analyse(Array(ring.prefix(fftSize)))
            ring.removeFirst(fftSize / 2)
        }
    }

    private func analyse(_ frame: [Float]) {
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)
        var power = [Float](repeating: 0, count: fftSize / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(fftSize / 2))
            }
        }

        // 16 log-spaced bands from 40 Hz to 16 kHz.
        let binHz = sampleRate / Float(fftSize)
        var bands = [Float](repeating: 0, count: Self.bandCount)
        for b in 0..<Self.bandCount {
            let lo = 40 * pow(400, Float(b) / Float(Self.bandCount))
            let hi = 40 * pow(400, Float(b + 1) / Float(Self.bandCount))
            let i0 = max(1, Int(lo / binHz)), i1 = min(fftSize / 2 - 1, max(i0 + 1, Int(hi / binHz)))
            var sum: Float = 0
            for i in i0..<i1 { sum += power[i] }
            bands[b] = sqrt(sum / Float(i1 - i0))
        }

        // Automatic gain: follow the loudest recent band, decaying slowly.
        peak = max(peak * 0.995, bands.max() ?? 0, 1e-4)
        let gain = 0.4 + sensitivity * 1.6
        for b in 0..<Self.bandCount {
            let level = min(1, pow(bands[b] / peak, 0.6) * gain)
            smoothed[b] = level > smoothed[b] ? level : smoothed[b] * 0.82 + level * 0.18
        }

        let bass = (smoothed[0] + smoothed[1] + smoothed[2]) / 3
        bassAverage = bassAverage * 0.95 + bass * 0.05
        let now = Date()
        let beat = bass > 0.25 && bass > bassAverage * 1.35 && now.timeIntervalSince(lastBeat) > 0.18
        if beat { lastBeat = now }

        let levels = Levels(bands: smoothed, overall: smoothed.reduce(0, +) / Float(Self.bandCount), beat: beat)
        DispatchQueue.main.async { self.onLevels?(levels) }
    }
}
