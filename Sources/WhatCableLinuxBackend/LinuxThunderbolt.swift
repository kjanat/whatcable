import Foundation
import WhatCableCore

/// Enumerates Thunderbolt / USB4 routers from `/sys/bus/thunderbolt/devices`
/// and maps each to an `IOThunderboltSwitch`. Linux exposes a flat device
/// list named `<domain>-<route>` (e.g. `0-0` is the host router, `0-1` a
/// directly attached device, `0-301` one two hops down). We populate the
/// switch-level identity, generation, and negotiated lane speed; the detailed
/// per-adapter port array that the Darwin backend builds from the IOKit
/// Thunderbolt fabric is left empty (sysfs does not expose per-adapter
/// credit/bandwidth state), so consumers fall back to the generic link view.
enum LinuxThunderbolt {
    static var root: String { "\(Sysfs.base)/bus/thunderbolt/devices" }

    /// Enumerates Thunderbolt/USB4 router devices from sysfs and converts each discovered router into an `IOThunderboltSwitch`.
    ///
    /// The function scans the sysfs Thunderbolt devices directory, ignores retimers and domain entries, parses the router route from the directory name, and only includes routers that expose identity (`unique_id` or `device_name`). For each included router it populates identity and vendor/model fields, computes a route-based depth, and constructs an `IOThunderboltSwitch`.
    /// - Returns: An array of `IOThunderboltSwitch` instances representing the discovered routers (empty if none found).
    static func read() -> [IOThunderboltSwitch] {
        var switches: [IOThunderboltSwitch] = []
        for name in Sysfs.list(root) {
            // Router directories are "<domain>-<route>". Skip retimers
            // ("0-0:1.1"), the domain nodes ("domain0"), and anything else.
            guard let dash = name.firstIndex(of: "-"),
                !name.contains(":"),
                !name.hasPrefix("domain")
            else { continue }
            let routeHex = String(name[name.index(after: dash)...])
            guard let route = Int64(routeHex, radix: 16) else { continue }
            let dir = "\(root)/\(name)"

            // A router only reports identity once authorized/!= a bare port.
            guard Sysfs.exists("\(dir)/unique_id") || Sysfs.exists("\(dir)/device_name") else {
                continue
            }

            let generation = Sysfs.int("\(dir)/generation")
            switches.append(
                IOThunderboltSwitch(
                    id: route,
                    className: "LinuxThunderboltSwitch",
                    vendorID: Sysfs.hex32("\(dir)/vendor").map(Int.init) ?? 0,
                    vendorName: Sysfs.string("\(dir)/vendor_name") ?? "",
                    modelName: Sysfs.string("\(dir)/device_name") ?? "",
                    routerID: switches.count,
                    depth: routeDepth(route),
                    routeString: route,
                    upstreamPortNumber: 0,
                    maxPortNumber: 0,
                    supportedSpeed: SupportedSpeedMask(rawValue: 0),
                    ports: [],
                    parentSwitchUID: nil,
                    thunderboltVersion: generation,
                    deviceID: Sysfs.hex32("\(dir)/device").map(Int.init)
                )
            )
        }
        return switches
    }

    /// Compute an approximate downstream hop count from a Thunderbolt route value.
    /// - Parameter route: The route identifier where each hexadecimal 4-bit nibble represents a potential downstream hop; the value is interpreted as unsigned.
    /// - Returns: The number of downstream hops inferred by counting non-zero 4-bit nibbles in the unsigned interpretation of `route`.
    private static func routeDepth(_ route: Int64) -> Int {
        var depth = 0
        var r = UInt64(bitPattern: route)
        while r != 0 {
            if r & 0xF != 0 { depth += 1 }
            r >>= 4
        }
        return depth
    }
}
