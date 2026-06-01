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

    /// Read a UTF-8 file at the given path and return its trimmed contents.
    /// - Parameter path: The filesystem path to the file to read.
    /// - Returns: The file contents with NUL (`\u{0}`) bytes removed and leading/trailing whitespace/newlines trimmed, or `nil` if the file is unreadable or the resulting string is empty.
    static func string(_ path: String) -> String? {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        let trimmed =
            raw
            .replacingOccurrences(of: "\u{0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Parses a base-10 integer value from the sysfs attribute at `path`.
    /// - Parameter path: File system path to the attribute.
    /// - Returns: An `Int` parsed from the file's contents, or `nil` if the attribute is missing, unreadable, or not a valid decimal integer.
    static func int(_ path: String) -> Int? {
        guard let s = string(path) else { return nil }
        return Int(s)
    }

    /// Parses a hexadecimal 32-bit unsigned integer from a sysfs text attribute.
    /// - Parameters:
    ///   - path: Path to the sysfs attribute file to read.
    /// - Returns: A `UInt32` parsed from the file's UTF-8 contents interpreted as hexadecimal (accepts an optional `0x`/`0X` prefix), or `nil` if the attribute is missing, unreadable, or not a valid hexadecimal `UInt32`.
    static func hex32(_ path: String) -> UInt32? {
        guard var s = string(path) else { return nil }
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s = String(s.dropFirst(2)) }
        return UInt32(s, radix: 16)
    }

    /// Interprets a sysfs attribute file as a boolean-like value.
    /// - Parameters:
    ///   - path: Path to the sysfs attribute file.
    /// - Returns: `true` if the file contains one of `"1"`, `"yes"`, `"y"`, `"true"`, `"enabled"`, or `"on"`; `false` if it contains one of `"0"`, `"no"`, `"n"`, `"false"`, `"disabled"`, or `"off"`; `nil` if the file is missing/unreadable or contains an unrecognized value.
    static func bool(_ path: String) -> Bool? {
        guard let s = string(path)?.lowercased() else { return nil }
        switch s {
        case "1", "yes", "y", "true", "enabled", "on": return true
        case "0", "no", "n", "false", "disabled", "off": return false
        default: return nil
        }
    }

    /// Lists the immediate entries of a directory in stable (sorted) order.
    /// - Parameter path: Filesystem path of the directory to list.
    /// - Returns: A sorted array of entry names contained in the directory, or an empty array if the directory does not exist or cannot be read.
    static func list(_ path: String) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return []
        }
        return entries.sorted()
    }

    /// Checks whether a filesystem entry exists at the given path.
    /// - Parameter path: The filesystem path to test.
    /// - Returns: `true` if a file, directory, or symlink target exists at `path`, `false` otherwise.
    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Returns a dictionary mapping immediate child entry names of `dir` to their readable scalar values.
    ///
    /// For each immediate child that is a regular, readable file, the file's trimmed contents are used as the value with newline characters replaced by spaces. Directory entries and unreadable/missing files are omitted.
    /// - Parameters:
    ///   - dir: Path to the directory whose immediate file attributes should be collected.
    /// - Returns: A `[String: String]` where keys are child entry names and values are their single-line contents.
    static func attributes(in dir: String) -> [String: String] {
        var out: [String: String] = [:]
        for name in list(dir) {
            let full = dir + "/" + name
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: full, isDirectory: &isDir),
                !isDir.boolValue
            else { continue }
            if let value = string(full) {
                out[name] = value.replacingOccurrences(of: "\n", with: " ")
            }
        }
        return out
    }
}
