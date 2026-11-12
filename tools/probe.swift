// Probe for the AULA F75 (SinoWealth 258a:010c) configuration interface.
//
// Usage:
//   swift probe.swift            -> query the model ID (read-only)
//   swift probe.swift flash      -> also show a temporary colour cycle for ~4 s
//
// Both commands come from OpenRGB's SinowealthKeyboard10c driver. Neither one
// writes to the keyboard's saved settings: direct mode reverts on its own about
// a second after the last frame.

import Foundation
import IOKit.hid

let vendorID = 0x258a
let productID = 0x010c
let reportID: CFIndex = 0x06
let reportSize = 520

func findConfigInterface() -> IOHIDDevice? {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let match: [String: Any] = [
        kIOHIDVendorIDKey: vendorID,
        kIOHIDProductIDKey: productID,
        kIOHIDPrimaryUsagePageKey: 0x0001,
        kIOHIDPrimaryUsageKey: 0x0080,
    ]
    IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
    IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return nil }
    // The config interface is the one whose usage pairs include vendor page 0xFF00.
    return devices.first { dev in
        let pairs = IOHIDDeviceGetProperty(dev, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Int]] ?? []
        return pairs.contains { $0[kIOHIDDeviceUsagePageKey] == 0xFF00 }
    }
}

func setFeature(_ dev: IOHIDDevice, _ bytes: [UInt8]) -> IOReturn {
    var buf = [UInt8](repeating: 0, count: reportSize)
    buf.replaceSubrange(0..<bytes.count, with: bytes)
    return IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, reportID, buf, buf.count)
}

func getFeature(_ dev: IOHIDDevice) -> (IOReturn, [UInt8]) {
    var buf = [UInt8](repeating: 0, count: reportSize)
    buf[0] = UInt8(reportID)
    var len = CFIndex(reportSize)
    let r = IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, reportID, &buf, &len)
    return (r, Array(buf.prefix(len)))
}

func hex(_ b: ArraySlice<UInt8>) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }

// The config interface shares a device with the keyboard, so macOS requires
// Input Monitoring permission before it can be opened.
if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
    print("Input Monitoring permission not granted; asking macOS to prompt for it.")
    print("Allow it in System Settings > Privacy & Security > Input Monitoring, then run this again.")
    _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    exit(2)
}

guard let dev = findConfigInterface() else {
    print("AULA F75 config interface not found. Is it plugged in by cable?")
    exit(1)
}
let open = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
print("open:", String(format: "0x%08x", open))

let q = setFeature(dev, [0x06, 0x82, 0x01, 0x00, 0x01, 0x00, 0x06])
print("model query sent:", String(format: "0x%08x", q))
usleep(20_000)
let (g, resp) = getFeature(dev)
print("read:", String(format: "0x%08x", g), "len:", resp.count)
print("first 32 bytes:", hex(resp.prefix(32)))
if resp.count > 13 {
    let model = resp[13]
    print(String(format: "model id: 0x%02x", model), model == 0xCD ? "(AULA F75)" : "(unknown)")
}

if CommandLine.arguments.contains("flash") {
    print("Flashing colours for ~4 s (temporary; the keyboard reverts by itself)...")
    let colours: [(UInt8, UInt8, UInt8)] = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 0, 255)]
    for (r, g, b) in colours {
        var frame: [UInt8] = [0x06, 0x08, 0x00, 0x00, 0x01, 0x00, 0x7A, 0x01]
        for _ in 0..<126 { frame += [r, g, b] }
        let s = setFeature(dev, Array(frame.prefix(reportSize)))
        print(String(format: "frame %3d,%3d,%3d -> 0x%08x", r, g, b, s))
        usleep(1_000_000)
    }
}
IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
