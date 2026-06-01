import Foundation
import Testing

@testable import WhatCableCore

@Suite("USB Billboard device detection")
struct USBDeviceBillboardTests {

    private func device(
        deviceClass: UInt8? = nil,
        ioClassName: String? = nil,
        productName: String? = nil
    ) -> USBDevice {
        USBDevice(
            id: 1, locationID: 0x0100_0000, vendorID: 0, productID: 0,
            vendorName: nil, productName: productName, serialNumber: nil,
            usbVersion: nil, speedRaw: nil, busPowerMA: nil, currentMA: nil,
            deviceClass: deviceClass, ioClassName: ioClassName,
            rawProperties: [:]
        )
    }

    @Test("bDeviceClass 0x11 is the spec-defined Billboard Device Class")
    func detectsByDeviceClass() {
        #expect(device(deviceClass: 0x11).isBillboardDevice)
    }

    @Test("Apple's Billboard IOKit class is recognised")
    func detectsByClassName() {
        #expect(device(ioClassName: "AppleUSBHostBillboardDevice").isBillboardDevice)
    }

    @Test("The product name macOS assigns is recognised")
    func detectsByProductName() {
        // The one signal observed in the wild so far: a real device showed up
        // named "Generic Billboard Device".
        #expect(device(productName: "Generic Billboard Device").isBillboardDevice)
    }

    @Test("An ordinary device is not a Billboard device")
    func ordinaryDeviceIsNot() {
        // bDeviceClass 9 is a USB hub, the common case next to a dock.
        #expect(
            !device(deviceClass: 9, ioClassName: "IOUSBHostDevice", productName: "USB3.0 Hub")
                .isBillboardDevice)
        #expect(!device().isBillboardDevice)
    }
}
