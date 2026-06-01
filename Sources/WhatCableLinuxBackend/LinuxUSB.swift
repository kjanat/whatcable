import Foundation
import WhatCableCore

/// Enumerates attached USB devices from `/sys/bus/usb/devices`, mapping each
/// to a `USBDevice`. WhatCableCore's tree/port logic keys off `locationID`
/// (a packed bus + hub-path value on Darwin); we synthesise an equivalent
/// from the kernel's `busnum` and `devpath` so `isRootDevice`, the device
/// tree, and per-port speed labelling behave the same way.
enum LinuxUSB {
    static var root: String { "\(Sysfs.base)/bus/usb/devices" }

    static func read() -> [USBDevice] {
        var devices: [USBDevice] = []
        for name in Sysfs.list(root) {
            // Skip interface nodes ("2-1:1.0") — only whole-device nodes carry
            // idVendor/idProduct. Root hubs ("usb1") are kept; they enumerate
            // as real devices and their zero devpath keeps them out of the
            // root-SuperSpeed heuristics.
            if name.contains(":") { continue }
            let dir = "\(root)/\(name)"
            guard let vid = Sysfs.hex32("\(dir)/idVendor"),
                  let pid = Sysfs.hex32("\(dir)/idProduct") else { continue }

            let busnum = Sysfs.int("\(dir)/busnum") ?? 0
            let devpath = Sysfs.string("\(dir)/devpath") ?? "0"
            let locationID = locationID(busnum: busnum, devpath: devpath)

            devices.append(
                USBDevice(
                    id: locationID == 0 ? UInt64(devices.count + 1) : UInt64(locationID),
                    locationID: locationID,
                    vendorID: UInt16(truncatingIfNeeded: vid),
                    productID: UInt16(truncatingIfNeeded: pid),
                    vendorName: Sysfs.string("\(dir)/manufacturer"),
                    productName: Sysfs.string("\(dir)/product"),
                    serialNumber: Sysfs.string("\(dir)/serial"),
                    usbVersion: Sysfs.string("\(dir)/version"),
                    speedRaw: speedRaw(Sysfs.string("\(dir)/speed")),
                    busPowerMA: maxPowerMA(Sysfs.string("\(dir)/bMaxPower")),
                    currentMA: nil,  // Live draw isn't exposed per-device on Linux.
                    busIndex: busnum,
                    controllerPortName: nil,
                    deviceClass: Sysfs.hex32("\(dir)/bDeviceClass").map { UInt8(truncatingIfNeeded: $0) },
                    ioClassName: nil,
                    rawProperties: Sysfs.attributes(in: dir)
                )
            )
        }
        return devices
    }

    /// Pack busnum + devpath into the bit layout WhatCableCore expects:
    /// bits 31-24 = controller/bus index, bits 23-0 = hub-path nibbles
    /// (one nibble per hop, most-significant first). `devpath` is a
    /// dotted hop list like "1.2.1"; a direct-attached device has a single
    /// hop, giving exactly one non-zero nibble (`isRootDevice == true`).
    static func locationID(busnum: Int, devpath: String) -> UInt32 {
        var path: UInt32 = 0
        let hops = devpath.split(separator: ".").compactMap { Int($0) }
        for (i, hop) in hops.enumerated() where i < 6 {
            let shift = 20 - (4 * i)
            path |= (UInt32(hop) & 0xF) << UInt32(shift)
        }
        return (UInt32(busnum & 0xFF) << 24) | (path & 0x00FF_FFFF)
    }

    /// Map the kernel's negotiated link `speed` (in Mbps) onto the
    /// `IOUSBHostDevice` "Device Speed" enum WhatCableCore decodes.
    static func speedRaw(_ speed: String?) -> UInt8? {
        guard let speed, let mbps = Double(speed) else { return nil }
        switch mbps {
        case ..<2:        return 0   // 1.5 Mbps — Low Speed
        case ..<13:       return 1   // 12 Mbps — Full Speed
        case ..<481:      return 2   // 480 Mbps — High Speed
        case ..<5001:     return 3   // 5 Gbps — SuperSpeed
        case ..<10001:    return 4   // 10 Gbps — SuperSpeed+
        default:          return 5   // 20 Gbps — SuperSpeed+ Gen 2x2
        }
    }

    /// Parse `bMaxPower` ("500mA", "0mA", or a bare number) into milliamps.
    static func maxPowerMA(_ s: String?) -> Int? {
        guard let s else { return nil }
        let digits = s.prefix { $0.isNumber }
        return Int(digits)
    }
}
