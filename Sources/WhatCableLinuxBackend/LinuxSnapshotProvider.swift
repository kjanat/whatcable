import Foundation
import WhatCableCore

/// Linux implementation of `CableSnapshotProvider`. Reads the kernel's USB
/// Type-C, USB-PD, USB, power-supply, and Thunderbolt sysfs trees and
/// assembles them into a `CableSnapshot`, the same model the macOS/IOKit
/// backend produces. The CLI and GUI bind to the protocol, so neither knows
/// which platform supplied the data.
///
/// sysfs reads are cheap and synchronous, so `snapshot()` reads on demand and
/// `watch()` polls on a 1-second timer, emitting only when the snapshot
/// actually changes — matching the Darwin backend's contract.
public final class LinuxSnapshotProvider: CableSnapshotProvider, @unchecked Sendable {
    public init() {}

    /// Builds a `CableSnapshot` populated with the current Linux hardware state.
    ///
    /// The snapshot includes Type‑C ports, power sources, identities, USB devices, power adapter state,
    /// and Thunderbolt switches; other fields are set to Linux-appropriate defaults (empty arrays or `nil`).
    /// - Returns: A `CableSnapshot` representing the current Linux Type‑C, USB, power supply, and Thunderbolt state.
    private func read() -> CableSnapshot {
        let typeC = LinuxTypeC.read()
        return CableSnapshot(
            ports: typeC.ports,
            powerSources: typeC.powerSources,
            identities: typeC.identities,
            usbDevices: LinuxUSB.read(),
            adapter: LinuxPowerSupply.read(),
            thunderboltSwitches: LinuxThunderbolt.read(),
            isDesktopMac: false,
            federatedIdentities: [],
            usb3Transports: [],
            trmTransports: [],
            cioCapabilities: [],
            typeCPhys: [],
            displayPorts: [],
            batteryFullyCharged: nil
        )
    }

    /// Produce a `CableSnapshot` assembled from the current Linux sysfs state.
    /// - Returns: A `CableSnapshot` built from data read under the Linux sysfs trees.
    /// - Throws: `LinuxBackendError.typeCClassUnavailable` if the `/sys/class/typec` sysfs root is not present.
    public func snapshot() async throws -> CableSnapshot {
        guard Sysfs.exists(LinuxTypeC.root) else {
            throw LinuxBackendError.typeCClassUnavailable
        }
        return read()
    }

    /// Creates an asynchronous stream that emits updated cable snapshots whenever the snapshot changes.
    /// - Returns: An `AsyncThrowingStream<CableSnapshot, Error>` that polls the system once per second and yields a new `CableSnapshot` only when it differs from the last emitted value. The stream will finish with `LinuxBackendError.typeCClassUnavailable` if the `/sys/class/typec` sysfs root is not present.
    public func watch() -> AsyncThrowingStream<CableSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard Sysfs.exists(LinuxTypeC.root) else {
                    continuation.finish(throwing: LinuxBackendError.typeCClassUnavailable)
                    return
                }
                var last: CableSnapshot? = nil
                while !Task.isCancelled {
                    let snap = read()
                    if last != snap {
                        continuation.yield(snap)
                        last = snap
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public enum LinuxBackendError: Error, CustomStringConvertible {
    /// The kernel USB Type-C class (`/sys/class/typec`) is not present. This
    /// is normal on machines with no USB-C controller exposed to the Type-C
    /// subsystem, or on kernels built without `CONFIG_TYPEC`.
    case typeCClassUnavailable

    public var description: String {
        switch self {
        case .typeCClassUnavailable:
            return """
                no USB Type-C ports found at /sys/class/typec. This kernel may lack \
                CONFIG_TYPEC, or no Type-C controller is exposed. WhatCable needs the \
                USB Type-C class to read cable, power, and partner data.
                """
        }
    }
}

/// Provide the default snapshot provider for Linux.
/// - Returns: A `CableSnapshotProvider` instance backed by the Linux sysfs implementation.
public func makeDefaultSnapshotProvider() -> any CableSnapshotProvider {
    LinuxSnapshotProvider()
}
