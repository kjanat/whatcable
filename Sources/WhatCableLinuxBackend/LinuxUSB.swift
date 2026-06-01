import Foundation
import WhatCableCore

/// Enumerates attached USB devices from `/sys/bus/usb/devices`, mapping each
/// to a `USBDevice`. WhatCableCore's tree/port logic keys off `locationID`
/// (a packed bus + hub-path value on Darwin); we synthesise an equivalent
/// from the kernel's `busnum` and `devpath` so `isRootDevice`, the device
/// tree, and per-port speed labelling behave the same way.
enum LinuxUSB {
    static var root: String { "\(Sysfs.base)/bus/usb/devices" }

    /// Enumerates USB devices from sysfs and returns a list of discovered USBDevice records.
    ///
    /// Scans the Linux USB sysfs root for device nodes, ignoring interface entries (names containing `:`) and skipping any node that lacks `idVendor` or `idProduct`. For each discovered device it synthesizes a WhatCableCore-style `locationID` from `busnum`/`devpath`, reads identification strings and attributes (vendor/product IDs, manufacturer/product/serial/version strings, negotiated link speed, and bMaxPower), and includes all sysfs attributes in `rawProperties`.
    /// - Returns: An array of `USBDevice` objects representing USB devices discovered under the sysfs USB root.
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
                let pid = Sysfs.hex32("\(dir)/idProduct")
            else { continue }

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
                    deviceClass: Sysfs.hex32("\(dir)/bDeviceClass").map {
                        UInt8(truncatingIfNeeded: $0)
                    },
                    ioClassName: nil,
                    rawProperties: Sysfs.attributes(in: dir)
                )
            )
        }
        return devices
    }

    /// Constructs a WhatCableCore-compatible USB location ID from a bus number and a dot-separated device path.
    ///
    /// The returned 32-bit value packs the bus number into bits 31–24 and encodes up to six hub-path hops as 4-bit nibbles in bits 23–0.
    /// Each hop is parsed from `devpath` (split by "."), converted to an integer, and truncated to its low 4 bits; hops beyond the sixth are ignored.
    /// - Parameters:
    ///   - busnum: USB bus number; only the low 8 bits are used.
    ///   - devpath: Dot-separated hub hops (e.g., "1.2.3"); non-numeric components are skipped.
    /// - Returns: A `UInt32` location ID with the bus number in bits 31–24 and up to six 4-bit hop nibbles in bits 23–0.
    static func locationID(busnum: Int, devpath: String) -> UInt32 {
        var path: UInt32 = 0
        let hops = devpath.split(separator: ".").compactMap { Int($0) }
        for (i, hop) in hops.enumerated() where i < 6 {
            let shift = 20 - (4 * i)
            path |= (UInt32(hop) & 0xF) << UInt32(shift)
        }
        return (UInt32(busnum & 0xFF) << 24) | (path & 0x00FF_FFFF)
    }

    /// Maps a link speed string in megabits per second to WhatCableCore's device speed code.
    /// - Parameter speed: A string containing the negotiated link speed in megabits per second (as provided by sysfs), or `nil`.
    /// - Returns: The corresponding `UInt8` device speed code (`0` = Low Speed ≈1.5 Mbps, `1` = Full Speed 12 Mbps, `2` = High Speed 480 Mbps, `3` = SuperSpeed 5 Gbps, `4` = SuperSpeed+ 10 Gbps, `5` = SuperSpeed+ Gen 2x2 20+ Gbps), or `nil` if `speed` is `nil` or cannot be parsed as a number.
    static func speedRaw(_ speed: String?) -> UInt8? {
        guard let speed, let mbps = Double(speed) else { return nil }
        switch mbps {
        case ..<2: return 0  // 1.5 Mbps — Low Speed
        case ..<13: return 1  // 12 Mbps — Full Speed
        case ..<481: return 2  // 480 Mbps — High Speed
        case ..<5001: return 3  // 5 Gbps — SuperSpeed
        case ..<10001: return 4  // 10 Gbps — SuperSpeed+
        default: return 5  // 20 Gbps — SuperSpeed+ Gen 2x2
        }
    }

    /// Parses a sysfs bMaxPower value and returns the leading numeric component in milliamps.
    /// - Parameter s: The raw sysfs string (for example `"500mA"`) that may start with digits.
    /// - Returns: The leading integer parsed from `s` (milliamps), or `nil` if `s` is `nil` or contains no leading digits.
    static func maxPowerMA(_ s: String?) -> Int? {
        guard let s else { return nil }
        let digits = s.prefix { $0.isNumber }
        return Int(digits)
    }
}
