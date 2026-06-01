import Foundation
import IOKit
import WhatCableCore

@MainActor
public final class VDMIdentityWatcher: ObservableObject {
    public enum Endpoint: String, Codable, Sendable {
        case sop = "SOP"
        case sopPrime = "SOP'"
    }

    public struct VDMIdentityUpdate: Codable, Sendable, Equatable {
        public let portIndex: Int
        /// Port type description (e.g. "USB-C", "MagSafe 3") used to
        /// disambiguate ports that share the same portIndex.
        public let portType: String
        public let endpoint: Endpoint
        public let identity: VDMIdentity
    }

    @Published public private(set) var identities: [VDMIdentityUpdate] = []

    public let updates: AsyncStream<VDMIdentityUpdate>

    private static let matchedClasses = [
        "IOPortTransportComponentCCUSBPDSOP",
        "IOPortTransportComponentCCUSBPDSOPp",
    ]

    private var continuation: AsyncStream<VDMIdentityUpdate>.Continuation?
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    public init() {
        var continuation: AsyncStream<VDMIdentityUpdate>.Continuation?
        updates = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public func start() {
        guard notifyPort == nil else { return }
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        notifyPort = port

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let added: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let watcher = Unmanaged<VDMIdentityWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in watcher.handleAdded(iterator) }
        }
        let removed: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let watcher = Unmanaged<VDMIdentityWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in watcher.handleRemoved(iterator) }
        }

        for className in Self.matchedClasses {
            var addedIter: io_iterator_t = 0
            if IOServiceAddMatchingNotification(
                port,
                kIOMatchedNotification,
                IOServiceMatching(className),
                added,
                selfPtr,
                &addedIter
            ) == KERN_SUCCESS {
                handleAdded(addedIter)
                iterators.append(addedIter)
            }

            var removedIter: io_iterator_t = 0
            if IOServiceAddMatchingNotification(
                port,
                kIOTerminatedNotification,
                IOServiceMatching(className),
                removed,
                selfPtr,
                &removedIter
            ) == KERN_SUCCESS {
                handleRemoved(removedIter)
                iterators.append(removedIter)
            }
        }
    }

    public func stop() {
        for iter in iterators where iter != 0 { IOObjectRelease(iter) }
        iterators.removeAll()
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
        identities.removeAll()
    }

    public func refresh() {
        identities.removeAll()
        for className in Self.matchedClasses {
            var iter: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iter)
                == KERN_SUCCESS
            {
                handleAdded(iter)
                IOObjectRelease(iter)
            }
        }
    }

    private func handleAdded(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let update = makeUpdate(from: service) {
                identities.removeAll {
                    $0.portIndex == update.portIndex && $0.portType == update.portType
                        && $0.endpoint == update.endpoint
                }
                identities.append(update)
                continuation?.yield(update)
            }
            IOObjectRelease(service)
        }
    }

    private func handleRemoved(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let endpoint = Self.endpoint(for: service) {
                func read(_ key: String) -> Any? {
                    IORegistryEntryCreateCFProperty(
                        service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
                }
                let portIndex = wcPortIndex(read: read, service: service)
                let portType = wcPortType(read: read, service: service)
                identities.removeAll {
                    $0.portIndex == portIndex && $0.portType == portType && $0.endpoint == endpoint
                }
            }
        }
    }

    private func makeUpdate(from service: io_service_t) -> VDMIdentityUpdate? {
        guard let endpoint = Self.endpoint(for: service) else { return nil }

        func read(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
        }

        let metadata = wcDictionary(read("Metadata"))
        let vdos = wcArray(metadata["VDOs"]).compactMap(wcData)
        let identity = VDMIdentity(
            vendorId: wcInt(metadata["VID"]) != 0
                ? wcInt(metadata["VID"]) : wcInt(read("Vendor ID")),
            productId: wcInt(metadata["PID"]) != 0
                ? wcInt(metadata["PID"]) : wcInt(read("Product ID")),
            bcdDevice: wcInt(metadata["bcdDevice"]),
            specRevision: wcInt(metadata["Specification Revision"]) != 0
                ? wcInt(metadata["Specification Revision"])
                : wcInt(read("Specification Revision")),
            vdos: vdos,
            productType: metadata["Product Type"].map(wcInt) ?? read("Product Type").map(wcInt),
            productTypeDescription: (metadata["Product Type Description"] as? String)
                ?? (read("Product Type Description") as? String)
        )
        return VDMIdentityUpdate(
            portIndex: wcPortIndex(read: read, service: service),
            portType: wcPortType(read: read, service: service),
            endpoint: endpoint,
            identity: identity
        )
    }

    private static func endpoint(for service: io_service_t) -> Endpoint? {
        var classBuf = [CChar](repeating: 0, count: 128)
        guard IOObjectGetClass(service, &classBuf) == KERN_SUCCESS else { return nil }
        switch String(cString: classBuf) {
        case "IOPortTransportComponentCCUSBPDSOP": return .sop
        case "IOPortTransportComponentCCUSBPDSOPp": return .sopPrime
        default: return nil
        }
    }
}
