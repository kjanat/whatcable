import Testing

@testable import WhatCableCore

@Suite("PDO Decoding")
struct PDODecodingTests {
    @Test("Fixed supply: 5V 3A")
    func fixedSupply5V3A() {
        // bits 31:30 = 00 (fixed), bits 19:10 = 100 (100 * 50mV = 5000mV), bits 9:0 = 300 (300 * 10mA = 3000mA)
        let raw: UInt32 = (100 << 10) | 300
        let pdo = PDO.decode(rawValue: raw)
        #expect(pdo == .fixed(voltage: 5000, maxCurrent: 3000))
    }

    @Test("Fixed supply: 20V 5A")
    func fixedSupply20V5A() {
        let raw: UInt32 = (400 << 10) | 500
        let pdo = PDO.decode(rawValue: raw)
        #expect(pdo == .fixed(voltage: 20000, maxCurrent: 5000))
    }

    @Test("Fixed supply: 9V 3A")
    func fixedSupply9V3A() {
        let raw: UInt32 = (180 << 10) | 300
        let pdo = PDO.decode(rawValue: raw)
        #expect(pdo == .fixed(voltage: 9000, maxCurrent: 3000))
    }

    @Test("Battery supply")
    func batterySupply() {
        // bits 31:30 = 01 (battery), bits 19:10 = 100 (5000mV min), bits 9:0 = 60 (60 * 250mW = 15000mW)
        let raw: UInt32 = (1 << 30) | (100 << 10) | 60
        let pdo = PDO.decode(rawValue: raw)
        #expect(pdo == .battery(minVoltage: 5000, maxPower: 15000))
    }

    @Test("Variable supply")
    func variableSupply() {
        // bits 31:30 = 10 (variable), bits 19:10 = 100 (5000mV min), bits 9:0 = 300 (3000mA)
        let raw: UInt32 = (2 << 30) | (100 << 10) | 300
        let pdo = PDO.decode(rawValue: raw)
        #expect(pdo == .variable(minVoltage: 5000, maxCurrent: 3000))
    }

    @Test("APDO/PPS: 3.3-21V 5A")
    func apdoPPS() {
        // bits 31:30 = 11 (APDO), bits 24:17 = 210 (210 * 100mV = 21000mV max),
        // bits 15:8 = 33 (33 * 100mV = 3300mV min), bits 6:0 = 100 (100 * 50mA = 5000mA)
        let raw: UInt32 = (3 << 30) | (210 << 17) | (33 << 8) | 100
        let pdo = PDO.decode(rawValue: raw)
        #expect(pdo == .apdo(minVoltage: 3300, maxVoltage: 21000, maxCurrent: 5000))
    }

    @Test("Negative ioreg value (unsigned overflow) decodes correctly")
    func negativeIoregOverflow() {
        // ioreg sometimes reports negative values for unsigned 32-bit PDOs.
        // Simulates masking a negative Int with 0xFFFFFFFF before decoding.
        let negative: Int = -1_073_741_524
        let masked = UInt32(bitPattern: Int32(truncatingIfNeeded: negative))
        let pdo = PDO.decode(rawValue: masked)
        // Type bits 31:30 = 0b11 = APDO, remaining bits decode per APDO layout
        if case .apdo = pdo {
            // passes: correctly identified as APDO
        } else {
            Issue.record("Expected APDO for overflow value, got \(pdo)")
        }
    }
}
