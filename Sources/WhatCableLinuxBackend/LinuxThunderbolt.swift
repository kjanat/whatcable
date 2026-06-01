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

    static func read() -> [IOThunderboltSwitch] {
        var switches: [IOThunderboltSwitch] = []
        for name in Sysfs.list(root) {
            // Router directories are "<domain>-<route>". Skip retimers
            // ("0-0:1.1"), the domain nodes ("domain0"), and anything else.
            guard let dash = name.firstIndex(of: "-"),
                  !name.contains(":"),
                  !name.hasPrefix("domain") else { continue }
            let routeHex = String(name[name.index(after: dash)...])
            guard let route = Int64(routeHex, radix: 16) else { continue }
            let dir = "\(root)/\(name)"

            // A router only reports identity once authorized/!= a bare port.
            guard Sysfs.exists("\(dir)/unique_id") || Sysfs.exists("\(dir)/device_name") else { continue }

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

    /// Approximate hop count from the route string: each non-zero hex nibble
    /// is one downstream hop. The host router (route 0) is depth 0.
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
