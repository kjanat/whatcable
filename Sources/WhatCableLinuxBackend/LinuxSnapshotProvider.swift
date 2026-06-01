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

    public func snapshot() async throws -> CableSnapshot {
        guard Sysfs.exists(LinuxTypeC.root) else {
            throw LinuxBackendError.typeCClassUnavailable
        }
        return read()
    }

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

/// Default backend on Linux. The CLI / GUI call this rather than naming
/// `LinuxSnapshotProvider` directly, mirroring `makeDefaultSnapshotProvider()`
/// in the Darwin backend.
public func makeDefaultSnapshotProvider() -> any CableSnapshotProvider {
    LinuxSnapshotProvider()
}
