import Foundation
import WhatCableCore

/// Reads the kernel USB Type-C class (`/sys/class/typec`) and the USB Power
/// Delivery class it links to. Produces the port, e-marker identity, and
/// charger power-profile slices of a `CableSnapshot`.
///
/// The mapping to WhatCable's IOKit-shaped model is deliberate:
/// - A Type-C port becomes an `AppleHPMInterface` with `parentPortType == 2`
///   (the USB-C value WhatCableCore already uses to build `portKey`).
/// - The partner's `identity/` VDOs become a `USBPDSOP` with `endpoint == .sop`;
///   the cable's `identity/` VDOs become one with `.sopPrime`. The sysfs file
///   order (`id_header`, `cert_stat`, `product`, `product_type_vdo1..3`) is
///   exactly the 0-indexed VDO order WhatCableCore decodes.
/// - The partner's advertised source PDOs become a `PowerSource`.
enum LinuxTypeC {
    static var root: String { "\(Sysfs.base)/class/typec" }

    /// WhatCableCore's USB-C port-type code, used to form `portKey`
    /// ("\(parentPortType)/\(parentPortNumber)"). Matches the `0x2` the
    /// Darwin backend reports for USB-C ports.
    static let usbCPortType = 2

    /// DisplayPort and Thunderbolt Standard/Vendor IDs, used to recognise the
    /// partner alternate modes that are currently entered.
    static let dpAltModeSVID: UInt32 = 0xFF01
    static let tbtAltModeSVID: UInt32 = 0x8087

    struct Result {
        var ports: [AppleHPMInterface] = []
        var identities: [USBPDSOP] = []
        var powerSources: [PowerSource] = []
    }

    static func read() -> Result {
        var result = Result()
        // Port directories are named "port0", "port1", ... Partner/cable and
        // alt-mode directories share the prefix, so filter to exact matches.
        let portDirs = Sysfs.list(root).filter {
            $0.range(of: #"^port[0-9]+$"#, options: .regularExpression) != nil
        }

        for name in portDirs {
            guard let index = Int(name.dropFirst("port".count)) else { continue }
            let portDir = "\(root)/\(name)"
            let partnerDir = "\(portDir)-partner"
            let cableDir = "\(portDir)-cable"
            let connected = Sysfs.exists(partnerDir)

            // --- e-marker / partner identities -----------------------------
            if let partner = identity(
                in: "\(partnerDir)/identity",
                endpoint: .sop,
                portNumber: index
            ) {
                result.identities.append(partner)
            }
            if let cable = identity(
                in: "\(cableDir)/identity",
                endpoint: .sopPrime,
                portNumber: index
            ) {
                result.identities.append(cable)
            }

            // --- alternate modes (DisplayPort / Thunderbolt) ---------------
            let altModes = activeAltModes(partnerDir: partnerDir, portName: name)
            let dpActive = altModes.contains { $0 == dpAltModeSVID }
            let tbActive = altModes.contains { $0 == tbtAltModeSVID }

            // --- power profiles the partner advertises as a source ---------
            let sources = powerSources(portDir: portDir, partnerDir: partnerDir, portNumber: index)
            result.powerSources.append(contentsOf: sources)

            result.ports.append(
                port(
                    index: index,
                    portDir: portDir,
                    cableDir: cableDir,
                    connected: connected,
                    dpActive: dpActive,
                    tbActive: tbActive
                )
            )
        }
        return result
    }

    // MARK: - Port

    private static func port(
        index: Int,
        portDir: String,
        cableDir: String,
        connected: Bool,
        dpActive: Bool,
        tbActive: Bool
    ) -> AppleHPMInterface {
        let orientation = Sysfs.string("\(portDir)/orientation")
        let cableType = Sysfs.string("\(cableDir)/type")          // passive / active

        // Every PD-capable Type-C port carries CC, so advertise it as a
        // supported transport — WhatCableCore reads "CC" in
        // `transportsSupported` to decide the port can run Discover Identity.
        var supported = ["CC", "USB2"]
        var active: [String] = []
        if connected {
            if dpActive { active.append("DisplayPort"); supported.append("DisplayPort") }
            if tbActive { active.append("CIO"); supported.append("CIO") }
            // USB-C keeps the USB2 D+/D- pair wired alongside DisplayPort and
            // Thunderbolt alt modes, so USB2 is genuinely active there. For a
            // bare partner the Type-C class exposes no USB-data signal, so we
            // do NOT assert USB2 — fabricating it would mislabel charge-only
            // connections as "Slow USB device" and suppress the charging /
            // battery-full headlines. Those paths handle the bare case.
            if dpActive || tbActive { active.append("USB2") }
        }

        var raw = Sysfs.attributes(in: portDir)
        for (k, v) in Sysfs.attributes(in: cableDir) { raw["cable.\(k)"] = v }

        return AppleHPMInterface(
            id: UInt64(index),
            serviceName: "Port-USB-C@\(index)",
            className: "LinuxTypeCPort",
            portDescription: "USB-C Port \(index + 1)",
            portTypeDescription: "USB-C",
            portNumber: index,
            connectionActive: connected,
            activeCable: cableType.map { $0.lowercased().contains("active") },
            opticalCable: nil,
            usbActive: connected ? true : nil,
            superSpeedActive: nil,
            usbModeType: nil,
            usbConnectString: Sysfs.string("\(portDir)/power_operation_mode"),
            transportsSupported: supported,
            transportsActive: active,
            transportsProvisioned: [],
            plugOrientation: orientationCode(orientation),
            plugEventCount: nil,
            connectionCount: nil,
            overcurrentCount: nil,
            pinConfiguration: [:],
            powerCurrentLimits: [],
            firmwareVersion: nil,
            bootFlagsHex: nil,
            busIndex: nil,
            rawProperties: raw
        )
    }

    /// Map the kernel's `orientation` string onto the small integer code the
    /// model carries (1 = normal, 2 = reversed, 0 = unknown/none).
    private static func orientationCode(_ s: String?) -> Int? {
        switch s?.lowercased() {
        case "normal": return 1
        case "reverse": return 2
        case "none", "unknown": return 0
        default: return nil
        }
    }

    // MARK: - Identity (Discover Identity VDOs)

    /// Assemble a `USBPDSOP` from a sysfs `identity/` directory. The kernel
    /// exposes each VDO as a `0x`-prefixed hex file. Returns `nil` when the
    /// directory or the ID Header VDO is absent (an unmarked cable, or no
    /// partner), so callers can simply skip it.
    private static func identity(
        in dir: String,
        endpoint: USBPDSOP.Endpoint,
        portNumber: Int
    ) -> USBPDSOP? {
        guard Sysfs.exists(dir), let idHeader = Sysfs.hex32("\(dir)/id_header") else {
            return nil
        }
        // VDO order matches WhatCableCore's 0-indexed decode:
        // [0]=id_header [1]=cert_stat [2]=product [3..5]=product_type_vdo1..3.
        var vdos: [UInt32] = [idHeader]
        vdos.append(Sysfs.hex32("\(dir)/cert_stat") ?? 0)
        let product = Sysfs.hex32("\(dir)/product") ?? 0
        vdos.append(product)
        for i in 1...3 {
            if let v = Sysfs.hex32("\(dir)/product_type_vdo\(i)") {
                vdos.append(v)
            } else {
                // Stop at the first absent product-type VDO; trailing zeros
                // would otherwise be decoded as real (all-zero) VDOs.
                break
            }
        }

        // VID is the low 16 bits of the ID Header; the Product VDO packs
        // PID in the high half and bcdDevice in the low half.
        let vendorID = Int(idHeader & 0xFFFF)
        let productID = Int((product >> 16) & 0xFFFF)
        let bcdDevice = Int(product & 0xFFFF)

        // The PD revision is exposed on the partner/cable node itself
        // (e.g. "3.0" or "2.0"); map onto the integer SpecRev code.
        let revPath = (dir as NSString).deletingLastPathComponent + "/usb_power_delivery_revision"
        let specRevision = pdRevisionCode(Sysfs.string(revPath))

        return USBPDSOP(
            id: UInt64(bitPattern: Int64(portNumber) << 8 | Int64(endpointTag(endpoint))),
            endpoint: endpoint,
            parentPortType: usbCPortType,
            parentPortNumber: portNumber,
            vendorID: vendorID,
            productID: productID,
            bcdDevice: bcdDevice,
            vdos: vdos,
            specRevision: specRevision
        )
    }

    private static func endpointTag(_ e: USBPDSOP.Endpoint) -> Int {
        switch e {
        case .sop: return 0
        case .sopPrime: return 1
        case .sopDoublePrime: return 2
        case .unknown: return 3
        }
    }

    private static func pdRevisionCode(_ s: String?) -> Int {
        guard let major = s?.split(separator: ".").first, let n = Int(major) else { return 0 }
        return n
    }

    // MARK: - Alternate modes

    /// SVIDs of the partner alternate modes that are currently *entered*
    /// (`active == yes`). Alt-mode directories are named `<port>-partner.N`.
    private static func activeAltModes(partnerDir: String, portName: String) -> [UInt32] {
        guard Sysfs.exists(partnerDir) else { return [] }
        var svids: [UInt32] = []
        for entry in Sysfs.list(partnerDir) where entry.hasPrefix("\(portName)-partner.") {
            let modeDir = "\(partnerDir)/\(entry)"
            guard Sysfs.bool("\(modeDir)/active") == true,
                  let svid = Sysfs.hex32("\(modeDir)/svid") else { continue }
            svids.append(svid)
        }
        return svids
    }

    // MARK: - Power (source PDOs)

    /// The PDOs the partner advertises as a power source (i.e. the charger
    /// menu). Prefers the partner's own PD object, then the port's. Returns an
    /// empty array when no source capabilities are exposed.
    private static func powerSources(
        portDir: String,
        partnerDir: String,
        portNumber: Int
    ) -> [PowerSource] {
        let candidates = [
            "\(partnerDir)/usb_power_delivery/source-capabilities",
            "\(portDir)/usb_power_delivery/source-capabilities"
        ]
        guard let capsDir = candidates.first(where: { Sysfs.exists($0) }) else { return [] }

        var options: [PowerOption] = []
        // PDO directories are named "<n>:fixed_supply", "<n>:variable_supply",
        // "<n>:battery", "<n>:programmable_supply". Sort numerically by index.
        let pdoDirs = Sysfs.list(capsDir)
            .filter { $0.contains(":") }
            .sorted { (Int($0.prefix(while: { $0 != ":" })) ?? 0) < (Int($1.prefix(while: { $0 != ":" })) ?? 0) }

        for pdo in pdoDirs {
            let dir = "\(capsDir)/\(pdo)"
            let kind = pdo.split(separator: ":").last.map(String.init) ?? ""
            if let option = powerOption(dir: dir, kind: kind) {
                options.append(option)
            }
        }
        guard !options.isEmpty else { return [] }

        return [
            PowerSource(
                id: UInt64(portNumber),
                name: "USB-PD",
                parentPortType: usbCPortType,
                parentPortNumber: portNumber,
                options: options,
                winning: nil  // Negotiated PDO isn't exposed via sysfs (tcpm debugfs only).
            )
        ]
    }

    private static func powerOption(dir: String, kind: String) -> PowerOption? {
        switch kind {
        case "fixed_supply":
            guard let mv = Sysfs.int("\(dir)/voltage"),
                  let ma = Sysfs.int("\(dir)/maximum_current") else { return nil }
            return PowerOption(voltageMV: mv, maxCurrentMA: ma, maxPowerMW: mv * ma / 1000)
        case "variable_supply", "programmable_supply":
            guard let mv = Sysfs.int("\(dir)/maximum_voltage"),
                  let ma = Sysfs.int("\(dir)/maximum_current") else { return nil }
            return PowerOption(voltageMV: mv, maxCurrentMA: ma, maxPowerMW: mv * ma / 1000)
        case "battery":
            guard let mv = Sysfs.int("\(dir)/maximum_voltage"),
                  let mw = Sysfs.int("\(dir)/maximum_power") else { return nil }
            let ma = mv > 0 ? mw * 1000 / mv : 0
            return PowerOption(voltageMV: mv, maxCurrentMA: ma, maxPowerMW: mw)
        default:
            return nil
        }
    }
}
