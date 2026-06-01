import Foundation

public struct USBDevice: Identifiable, Hashable {
    public let id: UInt64
    public let locationID: UInt32
    public let vendorID: UInt16
    public let productID: UInt16
    public let vendorName: String?
    public let productName: String?
    public let serialNumber: String?
    public let usbVersion: String?
    public let speedRaw: UInt8?
    public let busPowerMA: Int?
    public let currentMA: Int?
    /// Index of the XHCI controller this device is attached to, derived from
    /// the upper byte of `locationID` (and confirmed by walking the IOKit
    /// parent chain to the `AppleT*USBXHCI` ancestor). Used to associate the
    /// device with its physical USB-C port. `nil` if the parent walk failed.
    public let busIndex: Int?
    /// Service name of the physical port this device's XHCI controller is
    /// wired to (e.g. "Port-USB-C@1"), parsed from the controller's
    /// `UsbIOPort` property. This is a direct mapping and is preferred over
    /// `busIndex` when available. `nil` on machines that don't expose
    /// `UsbIOPort` on the XHCI controller.
    public let controllerPortName: String?
    /// USB device base class (`bDeviceClass`). `0x11` is the Billboard Device
    /// Class. `nil` when the property is absent.
    public let deviceClass: UInt8?
    /// The IOKit class the device enumerates as (e.g. "IOUSBHostDevice", or
    /// "AppleUSBHostBillboardDevice" for a Billboard device). Read from
    /// `IOObjectGetClass`. `nil` when unavailable.
    public let ioClassName: String?
    public let rawProperties: [String: String]

    public init(
        id: UInt64,
        locationID: UInt32,
        vendorID: UInt16,
        productID: UInt16,
        vendorName: String?,
        productName: String?,
        serialNumber: String?,
        usbVersion: String?,
        speedRaw: UInt8?,
        busPowerMA: Int?,
        currentMA: Int?,
        busIndex: Int? = nil,
        controllerPortName: String? = nil,
        deviceClass: UInt8? = nil,
        ioClassName: String? = nil,
        rawProperties: [String: String]
    ) {
        self.id = id
        self.locationID = locationID
        self.vendorID = vendorID
        self.productID = productID
        self.vendorName = vendorName
        self.productName = productName
        self.serialNumber = serialNumber
        self.usbVersion = usbVersion
        self.speedRaw = speedRaw
        self.busPowerMA = busPowerMA
        self.currentMA = currentMA
        self.busIndex = busIndex
        self.controllerPortName = controllerPortName
        self.deviceClass = deviceClass
        self.ioClassName = ioClassName
        self.rawProperties = rawProperties
    }

    /// A USB Billboard device. The USB-C spec uses one to report the Alternate
    /// Modes a device supports, and in particular to flag when an Alt Mode
    /// (such as DisplayPort) was advertised but isn't fully entered. Detected
    /// with three independent signals, any of which is sufficient:
    ///   - `bDeviceClass == 0x11` (the spec-defined Billboard Device Class),
    ///   - the IOKit class is Apple's Billboard device class, or
    ///   - the product name macOS assigns ("Generic Billboard Device").
    ///
    /// On signal quality, deliberately not yet matching the order they're
    /// checked: `bDeviceClass` and the IOKit class are the *durable* signals
    /// (defined by the USB spec and by macOS's class hierarchy). The
    /// product-name string is the *fragile* one: "Generic Billboard Device" is
    /// a macOS-supplied label that Apple can rename on any OS bump, at which
    /// point it silently stops matching. It currently carries the feature only
    /// because it is the one signal we've actually seen fire on real hardware;
    /// the live `bDeviceClass` value is still unconfirmed (the Test Kit probe
    /// will gather it). The moment community data confirms `0x11`, that should
    /// become the primary signal and the string match drop to a last resort.
    /// Do not let "it shipped on the string" harden into "the string is the
    /// real detector".
    ///
    /// Naming a Billboard device is always safe; any *diagnosis* from its
    /// presence is gated separately in `DisplayDiagnostic`.
    public var isBillboardDevice: Bool {
        if deviceClass == 0x11 { return true }
        if let cls = ioClassName, cls.localizedCaseInsensitiveContains("BillboardDevice") {
            return true
        }
        if let name = productName, name.localizedCaseInsensitiveContains("Billboard") {
            return true
        }
        return false
    }

    public var speedLabel: String {
        // IOUSBHostDevice "Device Speed" enum values
        switch speedRaw {
        case 0: return "Low Speed (1.5 Mbps)"
        case 1: return "Full Speed (12 Mbps)"
        case 2: return "High Speed (480 Mbps)"
        case 3: return "Super Speed (5 Gbps)"
        case 4: return "Super Speed+ (10 Gbps)"
        case 5: return "Super Speed+ Gen 2x2 (20 Gbps)"
        default: return "Unknown speed"
        }
    }

    /// Whether this device is directly attached to the host controller port
    /// (not behind a USB hub). LocationID bits 31-24 are the bus/controller
    /// index; bits 23-0 are hub-path nibbles (left-to-right, each nibble is
    /// one hop). A root device has exactly one non-zero nibble in the path.
    /// This encoding is an undocumented Apple convention, stable since at
    /// least Snow Leopard but not guaranteed by any public API.
    public var isRootDevice: Bool {
        let hubPath = locationID & 0x00FF_FFFF
        var nonZeroNibbles = 0
        for shift in stride(from: 0, to: 24, by: 4) {
            if (hubPath >> shift) & 0xF != 0 { nonZeroNibbles += 1 }
        }
        return nonZeroNibbles == 1
    }

    /// USB-IF style label for SuperSpeed and above, matching the format
    /// used by USB3Transport.speedLabel. Returns nil for USB 2.0 and below
    /// or when speedRaw is unavailable.
    public var usb3SpeedLabel: String? {
        switch speedRaw {
        case 3: return "USB 3.2 Gen 1 (5 Gbps)"
        case 4: return "USB 3.2 Gen 2 (10 Gbps)"
        case 5: return "USB 3.2 Gen 2x2 (20 Gbps)"
        default: return nil
        }
    }

    /// First directly-attached SuperSpeed device on this port (one non-zero
    /// locationID nibble, `speedRaw >= 3`). The conservative primary signal
    /// for labelling a USB-C port's negotiated link.
    public static func rootSuperSpeed(in devices: [USBDevice]) -> USBDevice? {
        devices.first { $0.isRootDevice && ($0.speedRaw ?? 0) >= 3 }
    }

    public static func parentLocationID(_ locID: UInt32) -> UInt32? {
        let hubPath = locID & 0x00FF_FFFF
        guard hubPath != 0 else { return nil }
        for shift in stride(from: 0, to: 24, by: 4) {
            if (hubPath >> shift) & 0xF != 0 {
                let cleared = locID & ~(UInt32(0xF) << shift)
                return (cleared & 0x00FF_FFFF) == 0 ? nil : cleared
            }
        }
        return nil
    }

    /// Highest-speed SuperSpeed device matched to this port by name
    /// (`controllerPortName`, sourced from IOKit's `UsbIOPort` mapping).
    /// Use only as a last-resort fallback when both `rootSuperSpeed(in:)`
    /// and the HPM transport label are unavailable: on Apple Silicon front
    /// USB-C ports the controller sits behind an internal virtual root
    /// that inflates locationID nibbles, so directly-attached devices fail
    /// `isRootDevice` even though their named port mapping is intact.
    ///
    /// Deliberately excludes devices that matched only by `busIndex`: those
    /// can include peripherals several hubs deep whose `Device Speed` could
    /// overstate the port's upstream link.
    public static func portMatchedSuperSpeed(in devices: [USBDevice]) -> USBDevice? {
        devices
            .filter { $0.controllerPortName != nil && ($0.speedRaw ?? 0) >= 3 }
            .max { ($0.speedRaw ?? 0) < ($1.speedRaw ?? 0) }
    }
}

// MARK: - Device tree

public struct USBDeviceNode: Identifiable {
    public let device: USBDevice
    public let depth: Int
    public let children: [USBDeviceNode]

    public var id: UInt64 { device.id }

    public static func buildTree(from devices: [USBDevice]) -> [USBDeviceNode] {
        guard !devices.isEmpty else { return [] }

        let byLocation = Dictionary(
            devices.map { ($0.locationID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var childrenOf: [UInt32: [USBDevice]] = [:]
        var topLevel: [USBDevice] = []

        for device in devices {
            if device.locationID == 0 {
                topLevel.append(device)
                continue
            }
            if let parentLoc = USBDevice.parentLocationID(device.locationID),
                byLocation[parentLoc] != nil
            {
                childrenOf[parentLoc, default: []].append(device)
            } else {
                topLevel.append(device)
            }
        }

        func build(_ device: USBDevice, depth: Int) -> USBDeviceNode {
            let kids = (childrenOf[device.locationID] ?? [])
                .sorted { $0.locationID < $1.locationID }
                .map { build($0, depth: depth + 1) }
            return USBDeviceNode(device: device, depth: depth, children: kids)
        }

        return
            topLevel
            .sorted { $0.locationID < $1.locationID }
            .map { build($0, depth: 0) }
    }

    public static func flatten(_ nodes: [USBDeviceNode]) -> [USBDeviceNode] {
        var result: [USBDeviceNode] = []
        for node in nodes {
            result.append(node)
            result.append(contentsOf: flatten(node.children))
        }
        return result
    }
}
