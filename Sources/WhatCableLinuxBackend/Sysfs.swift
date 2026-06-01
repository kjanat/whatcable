import Foundation

/// Thin, dependency-free helpers for reading the Linux `sysfs` pseudo-files
/// that the kernel exposes for USB Type-C, USB-PD, USB devices, power
/// supplies, and Thunderbolt. Every accessor is read-only and tolerant of
/// missing files: sysfs attributes appear and disappear with hotplug, so the
/// backend treats "file not present" as "attribute unknown" rather than an
/// error.
enum Sysfs {
    /// Base of the sysfs tree. Defaults to `/sys`, but can be overridden with
    /// the `WHATCABLE_SYSFS_ROOT` environment variable so the readers can be
    /// pointed at a captured/synthetic fixture tree for testing on machines
    /// without the matching hardware.
    static let base: String = {
        let env = ProcessInfo.processInfo.environment["WHATCABLE_SYSFS_ROOT"]
        guard let env, !env.isEmpty else { return "/sys" }
        return env.hasSuffix("/") ? String(env.dropLast()) : env
    }()

    /// Read a sysfs attribute and return it trimmed of trailing whitespace /
    /// NUL bytes. Returns `nil` when the file is absent or unreadable.
    static func string(_ path: String) -> String? {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        let trimmed = raw
            .replacingOccurrences(of: "\u{0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Read a base-10 integer attribute (e.g. `voltage_now`).
    static func int(_ path: String) -> Int? {
        guard let s = string(path) else { return nil }
        return Int(s)
    }

    /// Read a hex attribute written as `0x12ab` (the form the USB-PD identity
    /// VDO files use). Falls back to a bare hex string with no prefix.
    static func hex32(_ path: String) -> UInt32? {
        guard var s = string(path) else { return nil }
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s = String(s.dropFirst(2)) }
        return UInt32(s, radix: 16)
    }

    /// Read a boolean-ish attribute. The kernel uses several spellings
    /// ("1"/"0", "yes"/"no", "enabled"/"disabled", "true"/"false").
    static func bool(_ path: String) -> Bool? {
        guard let s = string(path)?.lowercased() else { return nil }
        switch s {
        case "1", "yes", "y", "true", "enabled", "on": return true
        case "0", "no", "n", "false", "disabled", "off": return false
        default: return nil
        }
    }

    /// List the immediate child entries of a directory, sorted for stable
    /// output. Returns an empty array when the directory does not exist.
    static func list(_ path: String) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return []
        }
        return entries.sorted()
    }

    /// True when a path exists (file, directory, or symlink target).
    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Dump every readable scalar attribute in a directory into a string map,
    /// for the `--raw` view. Skips sub-directories and unreadable files, and
    /// collapses multi-line values onto one line so the output stays tabular.
    static func attributes(in dir: String) -> [String: String] {
        var out: [String: String] = [:]
        for name in list(dir) {
            let full = dir + "/" + name
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: full, isDirectory: &isDir),
                  !isDir.boolValue else { continue }
            if let value = string(full) {
                out[name] = value.replacingOccurrences(of: "\n", with: " ")
            }
        }
        return out
    }
}
