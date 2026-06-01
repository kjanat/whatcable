import Foundation
import WhatCableCore

/// Reads `/sys/class/power_supply` for the connected charger and maps it onto
/// `AdapterInfo` (WhatCable's system-wide "what brick is attached" view).
///
/// On Linux the external charger usually appears as a non-Battery supply
/// (`type` of `Mains` / `USB`, often named `tcpm-source-psy-*`,
/// `ucsi-source-psy-*`, or `AC`). Voltages are reported in microvolts and
/// currents in microamps, so we scale to the millivolt/milliamp units the
/// model carries.
enum LinuxPowerSupply {
    static var root: String { "\(Sysfs.base)/class/power_supply" }

    /// Finds a suitable non-battery power-supply entry under sysfs and constructs an `AdapterInfo` describing that adapter.
    ///
    /// The function prefers a non-battery supply whose `online` sysfs entry is `true`; if none are reported online it falls back to the first non-battery supply found. Voltage and current are read from sysfs and converted to millivolts/milliamps when applicable; rated wattage is derived from available sysfs fields (prefer `voltage_max × current_max`, then `input_power_limit`, then a fallback `voltage × current`).
    /// - Returns: An `AdapterInfo` for the selected adapter, or `nil` if no non-battery power-supply directory is found.
    static func read() -> AdapterInfo? {
        // Prefer an online non-battery supply; fall back to the first
        // non-battery supply so we still surface the brick's rated capacity
        // even if `online` is unreported.
        let supplies = Sysfs.list(root)
            .map { "\(root)/\($0)" }
            .filter { (Sysfs.string("\($0)/type") ?? "").lowercased() != "battery" }

        let chosen = supplies.first { Sysfs.bool("\($0)/online") == true } ?? supplies.first
        guard let dir = chosen else { return nil }

        let voltageMV =
            Sysfs.int("\(dir)/voltage_now").map { $0 / 1000 }
            ?? Sysfs.int("\(dir)/voltage_max").map { $0 / 1000 }
        let currentMA =
            Sysfs.int("\(dir)/current_max").map { $0 / 1000 }
            ?? Sysfs.int("\(dir)/current_now").map { $0 / 1000 }

        // Rated wattage: prefer the brick's advertised maximum (voltage_max ×
        // current_max), then an explicit input_power_limit, then the live
        // voltage × max current.
        let watts = ratedWatts(dir: dir, fallbackVoltageMV: voltageMV, fallbackCurrentMA: currentMA)

        let type = Sysfs.string("\(dir)/type")
        let usbType = Sysfs.string("\(dir)/usb_type")  // e.g. "C" or "[PD]"
        let online = Sysfs.bool("\(dir)/online")

        return AdapterInfo(
            watts: watts,
            isCharging: online,
            source: (online == true) ? "AC" : nil,
            voltageMV: voltageMV,
            currentMA: currentMA,
            adapterDescription: usbType.map { "USB-PD charger (\($0))" }
                ?? type.map { "\($0.lowercased()) charger" },
            manufacturer: Sysfs.string("\(dir)/manufacturer"),
            name: Sysfs.string("\(dir)/model_name")
        )
    }

    /// Compute the rated wattage for a power supply from available sysfs values.
    /// - Parameters:
    ///   - dir: Filesystem path to the power_supply directory to read sysfs fields from.
    ///   - fallbackVoltageMV: Optional fallback voltage in millivolts used if max voltage is not available.
    ///   - fallbackCurrentMA: Optional fallback current in milliamps used if max current is not available.
    /// - Returns: The rated power in watts rounded to the nearest integer if calculable, `nil` if insufficient data.
    private static func ratedWatts(dir: String, fallbackVoltageMV: Int?, fallbackCurrentMA: Int?)
        -> Int?
    {
        if let vMax = Sysfs.int("\(dir)/voltage_max"), let iMax = Sysfs.int("\(dir)/current_max"),
            vMax > 0, iMax > 0
        {
            return Int((Double(vMax) * Double(iMax) / 1_000_000_000_000).rounded())  // µV × µA → W
        }
        if let limitUW = Sysfs.int("\(dir)/input_power_limit"), limitUW > 0 {
            return Int((Double(limitUW) / 1_000_000).rounded())  // µW → W
        }
        if let mv = fallbackVoltageMV, let ma = fallbackCurrentMA, mv > 0, ma > 0 {
            return Int((Double(mv) * Double(ma) / 1_000_000).rounded())  // mV × mA → W
        }
        return nil
    }
}
