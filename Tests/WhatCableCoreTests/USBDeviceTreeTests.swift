import Testing

@testable import WhatCableCore

@Suite("USBDeviceNode tree builder")
struct USBDeviceTreeTests {

    // MARK: - parentLocationID

    @Test("Root device returns nil parent")
    func rootDeviceParentIsNil() {
        // 0x14100000: bus 0x14, first-hop nibble 1, rest zero
        #expect(USBDevice.parentLocationID(0x1410_0000) == nil)
    }

    @Test("One hop deep returns root parent")
    func oneHopDeepParent() {
        // 0x14110000: parent should be 0x14100000
        #expect(USBDevice.parentLocationID(0x1411_0000) == 0x1410_0000)
    }

    @Test("Two hops deep returns one-hop parent")
    func twoHopsDeepParent() {
        // 0x14111000: parent should be 0x14110000
        #expect(USBDevice.parentLocationID(0x1411_1000) == 0x1411_0000)
    }

    @Test("Zero locationID returns nil")
    func zeroLocationIDParentIsNil() {
        #expect(USBDevice.parentLocationID(0) == nil)
    }

    // MARK: - buildTree

    @Test("Empty input returns empty tree")
    func emptyTree() {
        let tree = USBDeviceNode.buildTree(from: [])
        #expect(tree.isEmpty)
    }

    @Test("Single root device becomes top-level node")
    func singleRoot() {
        let d = makeDevice(id: 1, locationID: 0x1410_0000, name: "Hub")
        let tree = USBDeviceNode.buildTree(from: [d])
        #expect(tree.count == 1)
        #expect(tree[0].depth == 0)
        #expect(tree[0].children.isEmpty)
    }

    @Test("Hub with child device produces nested tree")
    func hubWithChild() {
        let hub = makeDevice(id: 1, locationID: 0x1410_0000, name: "Hub")
        let child = makeDevice(id: 2, locationID: 0x1411_0000, name: "Keyboard")
        let tree = USBDeviceNode.buildTree(from: [child, hub])
        #expect(tree.count == 1)
        #expect(tree[0].device.productName == "Hub")
        #expect(tree[0].depth == 0)
        #expect(tree[0].children.count == 1)
        #expect(tree[0].children[0].device.productName == "Keyboard")
        #expect(tree[0].children[0].depth == 1)
    }

    @Test("Virtual root: devices without parent in list are top-level")
    func virtualRoot() {
        // Two devices whose computed parent (0x14100000) is not in the list.
        // Both should be top-level at depth 0.
        let d1 = makeDevice(id: 1, locationID: 0x1411_0000, name: "Drive")
        let d2 = makeDevice(id: 2, locationID: 0x1412_0000, name: "Camera")
        let tree = USBDeviceNode.buildTree(from: [d2, d1])
        #expect(tree.count == 2)
        #expect(tree[0].depth == 0)
        #expect(tree[1].depth == 0)
        // Sorted by locationID
        #expect(tree[0].device.productName == "Drive")
        #expect(tree[1].device.productName == "Camera")
    }

    @Test("Hub at virtual-root depth in list becomes parent")
    func hubAtVirtualRootDepthPresent() {
        // When the hub IS in the list, it should be the parent.
        let hub = makeDevice(id: 1, locationID: 0x1410_0000, name: "Hub")
        let child = makeDevice(id: 2, locationID: 0x1411_0000, name: "Mouse")
        let tree = USBDeviceNode.buildTree(from: [child, hub])
        #expect(tree.count == 1)
        #expect(tree[0].device.productName == "Hub")
        #expect(tree[0].children.count == 1)
        #expect(tree[0].children[0].device.productName == "Mouse")
    }

    @Test("Orphan at depth 3 becomes top-level when no ancestors in list")
    func orphanAtDepthThree() {
        // Device at three hops deep, but neither parent nor grandparent in list.
        let orphan = makeDevice(id: 1, locationID: 0x1411_1000, name: "Orphan")
        let tree = USBDeviceNode.buildTree(from: [orphan])
        #expect(tree.count == 1)
        #expect(tree[0].depth == 0)
        #expect(tree[0].device.productName == "Orphan")
    }

    @Test("Three-level nesting: hub -> sub-hub -> device")
    func threeLevelNesting() {
        let hub = makeDevice(id: 1, locationID: 0x1410_0000, name: "Root Hub")
        let subHub = makeDevice(id: 2, locationID: 0x1411_0000, name: "Sub Hub")
        let leaf = makeDevice(id: 3, locationID: 0x1411_1000, name: "Leaf")
        let tree = USBDeviceNode.buildTree(from: [leaf, hub, subHub])
        #expect(tree.count == 1)
        #expect(tree[0].children.count == 1)
        #expect(tree[0].children[0].children.count == 1)
        #expect(tree[0].children[0].children[0].device.productName == "Leaf")
        #expect(tree[0].children[0].children[0].depth == 2)
    }

    @Test("Children of same parent are sorted by locationID")
    func childrenSortedByLocationID() {
        let hub = makeDevice(id: 1, locationID: 0x1410_0000, name: "Hub")
        let c1 = makeDevice(id: 2, locationID: 0x1413_0000, name: "Third")
        let c2 = makeDevice(id: 3, locationID: 0x1411_0000, name: "First")
        let c3 = makeDevice(id: 4, locationID: 0x1412_0000, name: "Second")
        let tree = USBDeviceNode.buildTree(from: [c1, c2, hub, c3])
        #expect(tree[0].children.count == 3)
        #expect(tree[0].children[0].device.productName == "First")
        #expect(tree[0].children[1].device.productName == "Second")
        #expect(tree[0].children[2].device.productName == "Third")
    }

    @Test("Zero locationID devices are always top-level")
    func zeroLocationIDIsTopLevel() {
        let d = makeDevice(id: 1, locationID: 0, name: "Zero")
        let tree = USBDeviceNode.buildTree(from: [d])
        #expect(tree.count == 1)
        #expect(tree[0].depth == 0)
    }

    // MARK: - flatten

    @Test("Flatten produces pre-order traversal with correct depths")
    func flattenPreOrder() {
        let hub = makeDevice(id: 1, locationID: 0x1410_0000, name: "Hub")
        let child1 = makeDevice(id: 2, locationID: 0x1411_0000, name: "A")
        let child2 = makeDevice(id: 3, locationID: 0x1412_0000, name: "B")
        let grandchild = makeDevice(id: 4, locationID: 0x1411_1000, name: "A1")
        let tree = USBDeviceNode.buildTree(from: [grandchild, child2, hub, child1])
        let flat = USBDeviceNode.flatten(tree)
        #expect(flat.count == 4)
        #expect(flat[0].device.productName == "Hub")
        #expect(flat[0].depth == 0)
        #expect(flat[1].device.productName == "A")
        #expect(flat[1].depth == 1)
        #expect(flat[2].device.productName == "A1")
        #expect(flat[2].depth == 2)
        #expect(flat[3].device.productName == "B")
        #expect(flat[3].depth == 1)
    }

    // MARK: - helpers

    private func makeDevice(
        id: UInt64,
        locationID: UInt32,
        name: String,
        speedRaw: UInt8? = nil
    ) -> USBDevice {
        USBDevice(
            id: id,
            locationID: locationID,
            vendorID: 0,
            productID: 0,
            vendorName: nil,
            productName: name,
            serialNumber: nil,
            usbVersion: nil,
            speedRaw: speedRaw,
            busPowerMA: nil,
            currentMA: nil,
            rawProperties: [:]
        )
    }
}
