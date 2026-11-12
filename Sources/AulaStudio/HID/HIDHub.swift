import AulaCore
import Foundation
import IOKit.hid

enum ConnectionStatus: Equatable {
    case noPermission
    case disconnected
    /// The S75 Pro's 2.4 GHz dongle is present, but settings need the cable.
    case wirelessOnly
    case connected(detail: String)
    case simulated

    var isUsable: Bool {
        switch self {
        case .connected, .simulated: return true
        default: return false
        }
    }
}

/// Watches USB for both keyboards and owns their HID devices.
final class HIDHub: @unchecked Sendable {
    static let s75DongleProductID = 0xFEFE

    var onStatusChange: ((KeyboardModel, ConnectionStatus) -> Void)?
    /// HID keyboard usage (page 0x07) of each key pressed on a supported keyboard.
    var onKeyDown: ((Int) -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let lock = NSLock()
    private var f75Config: IOHIDDevice?
    private var s75Config: IOHIDDevice?
    private var s75Screen: IOHIDDevice?
    private var s75Dongle: IOHIDDevice?

    private(set) var permissionGranted = false

    func start() {
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            KeyboardModel.allCases.forEach { onStatusChange?($0, .noPermission) }
            // Connect as soon as the permission is granted, without a relaunch.
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else { return }
                timer.invalidate()
                self?.start()
            }
            return
        }
        permissionGranted = true

        let matches: [[String: Any]] = [
            [kIOHIDVendorIDKey: 0x258A, kIOHIDProductIDKey: 0x010C],
            [kIOHIDVendorIDKey: 0x0C45, kIOHIDProductIDKey: 0x800A],
            [kIOHIDVendorIDKey: 0x0C45, kIOHIDProductIDKey: Self.s75DongleProductID],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            Unmanaged<HIDHub>.fromOpaque(ctx!).takeUnretainedValue().added(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            Unmanaged<HIDHub>.fromOpaque(ctx!).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            Unmanaged<HIDHub>.fromOpaque(ctx!).takeUnretainedValue().input(value)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        if IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnNotPermitted {
            permissionGranted = false
            KeyboardModel.allCases.forEach { onStatusChange?($0, .noPermission) }
        } else {
            KeyboardModel.allCases.forEach { onStatusChange?($0, status(of: $0)) }
        }
    }

    // MARK: Device bookkeeping

    private static func int(_ device: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? Int) ?? 0
    }

    private static func usagePages(_ device: IOHIDDevice) -> Set<Int> {
        let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Int]] ?? []
        return Set(pairs.compactMap { $0[kIOHIDDeviceUsagePageKey] } + [int(device, kIOHIDPrimaryUsagePageKey)])
    }

    private func added(_ device: IOHIDDevice) {
        let vid = Self.int(device, kIOHIDVendorIDKey), pid = Self.int(device, kIOHIDProductIDKey)
        let pages = Self.usagePages(device)
        lock.lock()
        if vid == 0x258A, pages.contains(0xFF00) {
            f75Config = device
        } else if vid == 0x0C45, pid == 0x800A {
            if pages.contains(S75Protocol.configUsagePage),
               Self.int(device, kIOHIDMaxFeatureReportSizeKey) >= S75Protocol.reportSize {
                s75Config = device
            }
            if pages.contains(S75Protocol.screenUsagePage) { s75Screen = device }
        } else if vid == 0x0C45, pid == Self.s75DongleProductID {
            s75Dongle = device
        }
        lock.unlock()
        notifyAll()
    }

    private func removed(_ device: IOHIDDevice) {
        lock.lock()
        for path in [\HIDHub.f75Config, \.s75Config, \.s75Screen, \.s75Dongle] as [ReferenceWritableKeyPath<HIDHub, IOHIDDevice?>] {
            if let d = self[keyPath: path], CFEqual(d, device) { self[keyPath: path] = nil }
        }
        lock.unlock()
        notifyAll()
    }

    private func notifyAll() {
        KeyboardModel.allCases.forEach { onStatusChange?($0, status(of: $0)) }
    }

    func status(of model: KeyboardModel) -> ConnectionStatus {
        guard permissionGranted else { return .noPermission }
        lock.lock(); defer { lock.unlock() }
        switch model {
        case .f75Pro:
            return f75Config != nil ? .connected(detail: "USB") : .disconnected
        case .s75Pro:
            if s75Config != nil { return .connected(detail: s75Screen != nil ? "USB" : "USB, screen channel missing") }
            return s75Dongle != nil ? .wirelessOnly : .disconnected
        }
    }

    private func input(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == 0x07, IOHIDValueGetIntegerValue(value) == 1 else { return }
        let usage = Int(IOHIDElementGetUsage(element))
        if usage > 0x03 { onKeyDown?(usage) }
    }

    // MARK: F75 Pro

    private let f75Queue = DispatchQueue(label: "aula.f75.send")
    private var f75InFlight = false

    /// Sends one direct-mode frame to the F75 Pro, indexed by LED slot. Dropped
    /// while the previous frame is still being written, so a slow write never backs
    /// up the animation.
    func sendF75Frame(_ colours: [RGB]) {
        lock.lock()
        guard let device = f75Config, !f75InFlight else { lock.unlock(); return }
        f75InFlight = true
        lock.unlock()
        let report = F75Protocol.directFrame(colours)
        f75Queue.async { [weak self] in
            _ = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, F75Protocol.reportID, report, report.count)
            guard let self else { return }
            self.lock.lock(); self.f75InFlight = false; self.lock.unlock()
        }
    }

    /// Runs a configuration transaction on the F75 Pro. Live frames are held back
    /// meanwhile, so they can't land between a read request and its reply.
    /// Blocking: call it off the main thread.
    func f75Transaction(_ body: (F75Channel) throws -> Void) throws {
        lock.lock()
        guard let device = f75Config else { lock.unlock(); throw ProtocolError.notConnected }
        lock.unlock()
        try f75Queue.sync {
            lock.lock(); f75InFlight = true; lock.unlock()
            defer { lock.lock(); f75InFlight = false; lock.unlock() }
            try body(F75Channel(device: device))
        }
    }

    // MARK: S75 Pro

    /// A transport bound to the S75 Pro's current USB devices, for one operation.
    func makeS75Transport() throws -> S75Transport {
        lock.lock(); defer { lock.unlock() }
        guard let config = s75Config else { throw ProtocolError.notConnected }
        return IOKitS75Transport(config: config, screen: s75Screen)
    }
}

/// The F75 Pro's known commands. From OpenRGB's SinowealthKeyboard10c driver and
/// verified on the keyboard: feature report 0x06, 520 bytes, on the 0xFF00 interface.
enum F75Protocol {
    static let reportID: CFIndex = 0x06
    static let reportSize = 520
    static let ledSlots = 128
    static let directHeader: [UInt8] = [0x06, 0x08, 0x00, 0x00, 0x01, 0x00, 0x7A, 0x01]

    static func directFrame(_ colours: [RGB]) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: reportSize)
        buf.replaceSubrange(0..<directHeader.count, with: directHeader)
        for (i, c) in colours.prefix(ledSlots).enumerated() {
            let o = directHeader.count + i * 3
            buf[o] = c.r; buf[o + 1] = c.g; buf[o + 2] = c.b
        }
        return buf
    }
}

/// The F75 Pro's configuration channel: feature report 0x06, 520 bytes each way.
struct F75Channel {
    let device: IOHIDDevice

    func set(_ report: [UInt8]) throws {
        precondition(report.count == F75Onboard.reportSize && report[0] == F75Onboard.reportID)
        let r = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(F75Onboard.reportID), report, report.count)
        guard r == kIOReturnSuccess else { throw ProtocolError.ioFailure(String(format: "F75 SET_REPORT failed (0x%08x)", r)) }
        // AULA's driver leaves 40-120 ms between reports.
        Thread.sleep(forTimeInterval: 0.06)
    }

    func get() throws -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: F75Onboard.reportSize)
        buf[0] = F75Onboard.reportID
        var length = CFIndex(buf.count)
        let r = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(F75Onboard.reportID), &buf, &length)
        guard r == kIOReturnSuccess else { throw ProtocolError.ioFailure(String(format: "F75 GET_REPORT failed (0x%08x)", r)) }
        Thread.sleep(forTimeInterval: 0.04)
        return Array(buf.prefix(length))
    }
}

/// S75 Pro transport over IOKit: feature reports for configuration, interrupt
/// output reports for screen pages, input reports for the screen ACKs.
final class IOKitS75Transport: S75Transport {
    private let config: IOHIDDevice
    private let screen: IOHIDDevice?
    private let acks = DispatchSemaphore(value: 0)
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    init(config: IOHIDDevice, screen: IOHIDDevice?) {
        self.config = config
        self.screen = screen
        if let screen {
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(screen, inputBuffer, 64, { ctx, _, _, _, _, _, _ in
                Unmanaged<IOKitS75Transport>.fromOpaque(ctx!).takeUnretainedValue().acks.signal()
            }, context)
        }
    }

    deinit {
        if let screen { IOHIDDeviceRegisterInputReportCallback(screen, inputBuffer, 64, nil, nil) }
        inputBuffer.deallocate()
    }

    func setFeature(_ report: [UInt8]) throws {
        let r = IOHIDDeviceSetReport(config, kIOHIDReportTypeFeature, 0, report, report.count)
        guard r == kIOReturnSuccess else { throw ProtocolError.ioFailure(String(format: "SET_REPORT failed (0x%08x)", r)) }
    }

    func getFeature() throws -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: S75Protocol.reportSize + 1)
        var length = CFIndex(buf.count)
        let r = IOHIDDeviceGetReport(config, kIOHIDReportTypeFeature, 0, &buf, &length)
        guard r == kIOReturnSuccess else { throw ProtocolError.ioFailure(String(format: "GET_REPORT failed (0x%08x)", r)) }
        let reply = Array(buf.prefix(length))
        // Some stacks keep a leading report-ID byte for unnumbered reports.
        return reply.count == S75Protocol.reportSize + 1 ? Array(reply.dropFirst()) : reply
    }

    func writeScreenPage(_ page: [UInt8]) throws {
        guard let screen else { throw ProtocolError.ioFailure("The S75 Pro's screen channel isn't available.") }
        // An output report goes over the interrupt OUT endpoint. Never send screen
        // pages as feature reports on the control pipe: that crashes the firmware.
        let r = IOHIDDeviceSetReport(screen, kIOHIDReportTypeOutput, 0, page, page.count)
        guard r == kIOReturnSuccess else { throw ProtocolError.ioFailure(String(format: "screen write failed (0x%08x)", r)) }
    }

    func waitScreenAck(timeout: TimeInterval) -> Bool {
        acks.wait(timeout: .now() + timeout) == .success
    }
}
