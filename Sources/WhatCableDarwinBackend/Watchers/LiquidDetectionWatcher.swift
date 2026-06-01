import Foundation
import IOKit
import WhatCableCore

@MainActor
public final class LiquidDetectionWatcher: ObservableObject {
    public struct LiquidDetectionUpdate: Codable, Sendable, Equatable {
        public let portIndex: Int
        public let portType: String
        public let status: LiquidDetectionStatus
    }

    @Published public private(set) var statuses: [LiquidDetectionUpdate] = []

    public let updates: AsyncStream<LiquidDetectionUpdate>

    private var continuation: AsyncStream<LiquidDetectionUpdate>.Continuation?
    private var notifyPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    public init() {
        var continuation: AsyncStream<LiquidDetectionUpdate>.Continuation?
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
            let watcher = Unmanaged<LiquidDetectionWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in watcher.handleAdded(iterator) }
        }
        let removed: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let watcher = Unmanaged<LiquidDetectionWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in watcher.handleRemoved(iterator) }
        }

        if IOServiceAddMatchingNotification(
            port,
            kIOMatchedNotification,
            IOServiceMatching("AppleHPMLDCMType2"),
            added,
            selfPtr,
            &addedIterator
        ) == KERN_SUCCESS {
            handleAdded(addedIterator)
        }

        if IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            IOServiceMatching("AppleHPMLDCMType2"),
            removed,
            selfPtr,
            &removedIterator
        ) == KERN_SUCCESS {
            handleRemoved(removedIterator)
        }
    }

    public func stop() {
        if addedIterator != 0 {
            IOObjectRelease(addedIterator)
            addedIterator = 0
        }
        if removedIterator != 0 {
            IOObjectRelease(removedIterator)
            removedIterator = 0
        }
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
        statuses.removeAll()
    }

    public func refresh() {
        statuses.removeAll()
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("AppleHPMLDCMType2"), &iter) == KERN_SUCCESS
        {
            handleAdded(iter)
            IOObjectRelease(iter)
        }
    }

    private func handleAdded(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let update = makeUpdate(from: service) {
                statuses.removeAll {
                    $0.portIndex == update.portIndex && $0.portType == update.portType
                }
                statuses.append(update)
                continuation?.yield(update)
            }
            IOObjectRelease(service)
        }
    }

    private func handleRemoved(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func read(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue()
            }
            let portIndex = wcPortIndex(read: read, service: service)
            let portType = wcPortType(read: read, service: service)
            statuses.removeAll {
                $0.portIndex == portIndex && $0.portType == portType
            }
        }
    }

    private func makeUpdate(from service: io_service_t) -> LiquidDetectionUpdate? {
        func read(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
        }

        let state =
            (read("StateDescription") as? String)
            ?? read("State").map { String(wcInt($0)) }
            ?? "Unknown"
        let status = LiquidDetectionStatus(
            liquidDetected: wcBool(read("LiquidDetected")),
            state: state,
            measurementStatus: wcInt(read("MeasurementStatus")),
            mitigationsEnabled: wcBool(read("MitigationsEnabled"))
        )
        return LiquidDetectionUpdate(
            portIndex: wcPortIndex(read: read, service: service),
            portType: wcPortType(read: read, service: service),
            status: status
        )
    }
}
