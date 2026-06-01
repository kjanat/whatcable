import Foundation
import IOKit
import WhatCableCore

@MainActor
public final class PortDiagnosticsWatcher: ObservableObject {
    public struct PortDiagnosticsSnapshot: Codable, Sendable, Equatable {
        public let timestamp: Date
        public let healthCounters: [String: PortHealthCounters]
        public let contracts: [String: PDContract]
        public let eventTraces: [String: PDEventTrace]
    }

    @Published public private(set) var latestSnapshot: PortDiagnosticsSnapshot?

    public let snapshots: AsyncStream<PortDiagnosticsSnapshot>

    private var continuation: AsyncStream<PortDiagnosticsSnapshot>.Continuation?
    private var notifyPort: IONotificationPortRef?
    private var matchIterator: io_iterator_t = 0
    private var cachedPortKeys: [String] = []

    public init() {
        var continuation: AsyncStream<PortDiagnosticsSnapshot>.Continuation?
        snapshots = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public func start() {
        guard notifyPort == nil else { return }
        cachedPortKeys = PowerTelemetryWatcher.hpmPortKeys()
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        notifyPort = port

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let watcher = Unmanaged<PortDiagnosticsWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in
                while case let service = IOIteratorNext(iterator), service != 0 {
                    IOObjectRelease(service)
                }
                watcher.refresh()
            }
        }

        if IOServiceAddMatchingNotification(
            port,
            kIOMatchedNotification,
            IOServiceMatching("AppleSmartBattery"),
            cb,
            selfPtr,
            &matchIterator
        ) == KERN_SUCCESS {
            while case let service = IOIteratorNext(matchIterator), service != 0 {
                IOObjectRelease(service)
            }
            refresh()
        }
    }

    public func stop() {
        if matchIterator != 0 {
            IOObjectRelease(matchIterator)
            matchIterator = 0
        }
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
        cachedPortKeys = []
        latestSnapshot = nil
    }

    public func refresh() {
        guard let dict = PowerTelemetryWatcher.appleSmartBatteryPropertiesForDiagnostics() else {
            return
        }
        let entries = wcArray(dict["PortControllerInfo"]).map(wcDictionary)
        var counters: [String: PortHealthCounters] = [:]
        var contracts: [String: PDContract] = [:]
        var traces: [String: PDEventTrace] = [:]

        for (offset, entry) in entries.enumerated() {
            let key = offset < cachedPortKeys.count ? cachedPortKeys[offset] : "2/\(offset + 1)"
            counters[key] = Self.healthCounters(from: entry)
            contracts[key] = Self.contract(from: entry)
            traces[key] = Self.eventTrace(from: entry)
        }

        let snapshot = PortDiagnosticsSnapshot(
            timestamp: Date(),
            healthCounters: counters,
            contracts: contracts,
            eventTraces: traces
        )
        latestSnapshot = snapshot
        continuation?.yield(snapshot)
    }

    private static func contract(from dict: [String: Any]) -> PDContract {
        let rawPDOs = wcArray(dict["PortControllerPortPDO"]).map(wcUInt32)
        let pdoCount = wcInt(dict["PortControllerNPDOs"])
        let decoded = rawPDOs.prefix(pdoCount > 0 ? pdoCount : rawPDOs.count).map(
            PDO.decode(rawValue:))
        return PDContract(
            activeRdo: wcUInt32(dict["PortControllerActiveContractRdo"]),
            pdoList: decoded,
            pdoCount: pdoCount,
            maxPower: wcInt(dict["PortControllerMaxPower"]),
            capMismatch: wcBool(dict["PortControllerCapMismatch"]),
            srcTypes: wcInt(dict["PortControllerSrcTypes"])
        )
    }

    private static func healthCounters(from dict: [String: Any]) -> PortHealthCounters {
        PortHealthCounters(
            attachCount: wcInt(dict["PortControllerAttachCount"]),
            detachCount: wcInt(dict["PortControllerDetachCount"]),
            hardResetCount: wcInt(dict["PortControllerHardResetCount"]),
            shortDetectCount: wcInt(dict["PortControllerShortDetectCount"]),
            i2cErrCount: wcInt(dict["PortControllerI2cErrCount"]),
            dataRoleSwapCount: wcInt(dict["PortControllerDataRoleSwapCount"]),
            dataRoleSwapFailCount: wcInt(dict["PortControllerDataRoleSwapFailCount"]),
            pwrRoleSwapCount: wcInt(dict["PortControllerPwrRoleSwapCount"]),
            pwrRoleSwapFailCount: wcInt(dict["PortControllerPwrRoleSwapFailCount"]),
            vdoFailCount: wcInt(dict["PortControllerVdoFailCount"]),
            fetEnableFailCount: wcInt(dict["PortControllerInpFetEnFailCount"]),
            fetStatus: wcUInt8(dict["PortControllerFetStatus"]),
            pdState: wcUInt8(dict["PortControllerPDst"]),
            dnState: wcUInt8(dict["PortControllerDnSt"])
        )
    }

    private static func eventTrace(from dict: [String: Any]) -> PDEventTrace {
        let raw =
            wcData(dict["PortControllerEvtBuffer"])
            ?? Data(wcArray(dict["PortControllerEvtBuffer"]).map(wcUInt8))
        let filtered = raw.filter { $0 != 0x00 }
        let events = filtered.map(PDEvent.init(rawValue:))
        return PDEventTrace(rawBuffer: filtered, events: events)
    }
}

extension PowerTelemetryWatcher {
    nonisolated static func appleSmartBatteryPropertiesForDiagnostics() -> [String: Any]? {
        appleSmartBatteryProperties()
    }
}
