import Foundation

/// The wire underneath an S75 Pro: real USB in the app, a fake keyboard in SelfCheck
/// and in the app's simulator.
public protocol S75Transport: AnyObject {
    func setFeature(_ report: [UInt8]) throws
    func getFeature() throws -> [UInt8]
    func writeScreenPage(_ page: [UInt8]) throws
    /// Waits for the keyboard's acknowledgement of a screen page.
    func waitScreenAck(timeout: TimeInterval) -> Bool
}

/// Runs S75 Pro transactions over a transport, with the vendor's timing.
/// Blocking: call it off the main thread.
public final class S75Executor: @unchecked Sendable {
    public typealias Log = (_ line: String) -> Void

    private let transport: S75Transport
    private let log: Log?
    /// Set to 0 in tests to run without the vendor's 35 ms pacing.
    public var delayScale = 1.0

    public init(transport: S75Transport, log: Log? = nil) {
        self.transport = transport
        self.log = log
    }

    private func sleep(_ seconds: Double) {
        if seconds * delayScale > 0 { Thread.sleep(forTimeInterval: seconds * delayScale) }
    }

    private func send(_ bytes: [UInt8], read: Bool) throws -> [UInt8]? {
        log?("-> " + bytes.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " "))
        try transport.setFeature(bytes)
        sleep(S75Protocol.commandDelay)
        guard read else { return nil }
        let reply = try transport.getFeature()
        log?("<- " + reply.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " "))
        sleep(S75Protocol.commandDelay)
        return reply
    }

    public func run(_ steps: [S75Protocol.Step]) throws {
        for step in steps {
            switch step {
            case .pause(let s):
                sleep(s)
            case .command(let code, _):
                let reply = try send(S75Protocol.bytes(of: step)!, read: true) ?? []
                guard S75Protocol.isAcknowledged(reply, code: code) else {
                    throw ProtocolError.notAcknowledged(String(format: "command 04 %02X", code))
                }
            case .send(let bytes):
                _ = try send(bytes, read: false)
            case .sendRead(let bytes):
                _ = try send(bytes, read: true)
            case .finalize(let read):
                _ = try send(S75Protocol.bytes(of: step)!, read: read)
            }
        }
    }

    /// Uploads a screen buffer built by `ScreenEncoder`. Returns how many pages the
    /// keyboard acknowledged.
    @discardableResult
    public func uploadScreen(_ buffer: [UInt8], progress: ((Int, Int) -> Void)? = nil) throws -> Int {
        let pages = try ScreenEncoder.validate(buffer)
        try run(S75Protocol.screenUploadBegin(pages: pages))
        _ = transport.waitScreenAck(timeout: 0.15)
        var acked = 0
        for i in 0..<pages {
            let page = Array(buffer[(i * ScreenEncoder.pageSize)..<((i + 1) * ScreenEncoder.pageSize)])
            try transport.writeScreenPage(page)
            if transport.waitScreenAck(timeout: 0.4) { acked += 1 } else { log?("screen page \(i + 1)/\(pages): no ACK within 400 ms") }
            progress?(i + 1, pages)
        }
        try run(S75Protocol.screenUploadEnd)
        return acked
    }
}

/// A pretend S75 Pro that acknowledges every command and records what it was sent.
public final class SimulatedS75: S75Transport {
    public private(set) var sent: [[UInt8]] = []
    public private(set) var screenPages = 0
    private var lastCommand: UInt8 = 0
    private let lock = NSLock()

    public init() {}

    public func setFeature(_ report: [UInt8]) throws {
        lock.lock(); defer { lock.unlock() }
        guard report.count == S75Protocol.reportSize else {
            throw ProtocolError.ioFailure("feature report must be 64 bytes, got \(report.count)")
        }
        sent.append(report)
        if report[0] == 0x04 { lastCommand = report[1] }
    }

    public func getFeature() throws -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        var reply = [UInt8](repeating: 0, count: S75Protocol.reportSize)
        reply[0] = 0x04; reply[1] = lastCommand; reply[3] = 0x01
        return reply
    }

    public func writeScreenPage(_ page: [UInt8]) throws {
        guard page.count == ScreenEncoder.pageSize else { throw ProtocolError.ioFailure("screen page must be 4096 bytes") }
        lock.lock(); screenPages += 1; lock.unlock()
    }

    public func waitScreenAck(timeout: TimeInterval) -> Bool { true }
}
