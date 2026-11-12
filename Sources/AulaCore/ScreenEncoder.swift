import CoreGraphics
import Foundation
import ImageIO

/// Builds the S75 Pro's screen buffer from an image or GIF.
///
/// Buffer layout (from the EA75MAX vendor driver, via thibaultmiclo/aula-driver):
///     [0]        frame count
///     [1...N]    per-frame delay in 20 ms units (minimum 1)
///     [...255]   0xFF
///     [256...]   frames, RGB565 little-endian, row-major, 135 x 240
///     padding    0xFF up to a whole number of 4096-byte pages
///
/// SAFETY: the firmware writes what it receives straight to flash with no bounds
/// check. Past 141 frames the data overwrites the keyboard's built-in screen
/// graphics permanently (seen on the sister F108 Pro). The limit is enforced in
/// `buildBuffer` and again in `validate`, and there is deliberately no override.
public enum ScreenEncoder {
    public static let width = 135
    public static let height = 240
    public static let headerLength = 256
    public static let maxFrames = 141
    public static let pageSize = 4096
    public static let frameBytes = width * height * 2
    public static let maxPages = (headerLength + maxFrames * frameBytes + pageSize - 1) / pageSize
    public static let minDelayMs = 30
    public static let maxDelayMs = 500

    public struct Animation: @unchecked Sendable {
        public var frames: [CGImage]
        public var delays: [Int]
        public init(frames: [CGImage], delays: [Int]) { self.frames = frames; self.delays = delays }
    }

    /// Decodes an image or animated GIF, fitted to the screen. May contain more
    /// than `maxFrames` frames; use `trim` before building a buffer.
    public static func load(url: URL, fit: ScreenFit) throws -> Animation {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ProtocolError.ioFailure("Couldn't read \(url.lastPathComponent).")
        }
        var frames: [CGImage] = [], delays: [Int] = []
        for i in 0..<CGImageSourceGetCount(source) {
            guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(try fitted(image, fit))
            delays.append(delayMs(source, i))
        }
        guard !frames.isEmpty else { throw ProtocolError.ioFailure("\(url.lastPathComponent) has no frames.") }
        return Animation(frames: frames, delays: delays)
    }

    static func delayMs(_ source: CGImageSource, _ index: Int) -> Int {
        let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let seconds = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        return Int((seconds > 0 ? seconds : 0.1) * 1000)
    }

    public static func fitted(_ image: CGImage, _ fit: ScreenFit) throws -> CGImage {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ProtocolError.ioFailure("Couldn't create an image buffer.")
        }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let sx = CGFloat(width) / iw, sy = CGFloat(height) / ih
        let rect: CGRect
        switch fit {
        case .stretch:
            rect = CGRect(x: 0, y: 0, width: width, height: height)
        case .cover, .contain:
            let s = fit == .cover ? max(sx, sy) : min(sx, sy)
            let w = iw * s, h = ih * s
            rect = CGRect(x: (CGFloat(width) - w) / 2, y: (CGFloat(height) - h) / 2, width: w, height: h)
        }
        ctx.draw(image, in: rect)
        guard let out = ctx.makeImage() else { throw ProtocolError.ioFailure("Couldn't scale the image.") }
        return out
    }

    /// Little-endian RGB565, row-major from the top-left pixel.
    public static func rgb565(_ image: CGImage) throws -> [UInt8] {
        guard image.width == width, image.height == height else {
            throw ProtocolError.screenLimit("Frame is \(image.width)x\(image.height), expected \(width)x\(height).")
        }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ProtocolError.ioFailure("Couldn't read the frame's pixels.")
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var out = [UInt8](repeating: 0, count: width * height * 2)
        for i in 0..<(width * height) {
            let r = UInt16(rgba[i * 4]), g = UInt16(rgba[i * 4 + 1]), b = UInt16(rgba[i * 4 + 2])
            let v = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
            out[i * 2] = UInt8(v & 0xFF)
            out[i * 2 + 1] = UInt8(v >> 8)
        }
        return out
    }

    public static func buildBuffer(frames: [[UInt8]], delays: [Int]) throws -> [UInt8] {
        guard !frames.isEmpty else { throw ProtocolError.screenLimit("No frames to upload.") }
        guard frames.count <= maxFrames else {
            throw ProtocolError.screenLimit("\(frames.count) frames is over the keyboard's limit of \(maxFrames).")
        }
        guard delays.count == frames.count else { throw ProtocolError.screenLimit("Each frame needs one delay.") }
        var data = [UInt8](repeating: 0xFF, count: headerLength)
        data[0] = UInt8(frames.count)
        for (i, ms) in delays.enumerated() {
            // Round half to even, matching the reference driver.
            data[1 + i] = UInt8(min(255, max(1, Int((Double(ms) / 20).rounded(.toNearestOrEven)))))
        }
        for f in frames {
            guard f.count == frameBytes else { throw ProtocolError.screenLimit("Frame data has the wrong size.") }
            data += f
        }
        let pages = (data.count + pageSize - 1) / pageSize
        data += [UInt8](repeating: 0xFF, count: pages * pageSize - data.count)
        return data
    }

    public static func buildBuffer(_ animation: Animation) throws -> [UInt8] {
        try buildBuffer(frames: animation.frames.map(rgb565), delays: animation.delays)
    }

    /// Last check before bytes reach the keyboard's flash. Returns the page count.
    @discardableResult
    public static func validate(_ buffer: [UInt8]) throws -> Int {
        guard !buffer.isEmpty, buffer.count % pageSize == 0 else {
            throw ProtocolError.screenLimit("Screen data must be a whole number of 4096-byte pages.")
        }
        let frames = Int(buffer[0])
        let pages = buffer.count / pageSize
        guard (1...maxFrames).contains(frames) else {
            throw ProtocolError.screenLimit("Header declares \(frames) frames (limit \(maxFrames)).")
        }
        let expected = (headerLength + frames * frameBytes + pageSize - 1) / pageSize
        guard pages == expected, pages <= maxPages else {
            throw ProtocolError.screenLimit("Screen data is \(pages) pages, expected \(expected) (hard limit \(maxPages)).")
        }
        return pages
    }

    /// Reduces an animation to `limit` frames by dropping frames evenly and adding
    /// their time to the kept ones, so the total playback time stays the same.
    public static func trim<T>(_ frames: [T], _ delays: [Int], limit: Int = maxFrames) -> ([T], [Int]) {
        let n = frames.count
        guard n > limit else { return (frames, delays) }
        let keep = (0..<limit).map { $0 * n / limit }
        var outF: [T] = [], outD: [Int] = []
        for (k, start) in keep.enumerated() {
            let end = k + 1 < keep.count ? keep[k + 1] : n
            outF.append(frames[start])
            outD.append(delays[start..<end].reduce(0, +))
        }
        return (outF, outD)
    }
}
