import Foundation
import XCTest
@testable import IIGSCore

final class ROMPhase3Tests: XCTestCase {
    func testROM01MapsIntoFEAndFFBanksAndMirrorsResetVector() throws {
        var bytes = Array(repeating: UInt8(0), count: IIGSROMVersion.rom01.expectedSize)
        bytes[0x00000] = 0xA1
        bytes[0x1D000] = 0xC0
        bytes[0x1FFFC] = 0x34
        bytes[0x1FFFD] = 0x12
        bytes[0x1FFFF] = 0x5A
        let rom = try IIGSROMImage(bytes: bytes)
        let memory = FlatMemoryBus(size: 0x020000)

        memory.installROM(rom)

        XCTAssertEqual(memory[0xFE0000], 0xA1)
        XCTAssertEqual(memory[0xFFFFFC], 0x34)
        XCTAssertEqual(memory[0xFFFFFD], 0x12)
        XCTAssertEqual(memory[0xFFFFFF], 0x5A)
        XCTAssertEqual(memory[0x00D000], 0xC0)
        XCTAssertEqual(memory[0x00FFFC], 0x34)
        XCTAssertEqual(memory[0x00FFFD], 0x12)

        memory[0xFE0000] = 0x99
        memory[0x00FFFC] = 0x99

        XCTAssertEqual(memory[0xFE0000], 0xA1)
        XCTAssertEqual(memory[0x00FFFC], 0x34)
    }

    func testROM03MapsIntoFCThroughFFBanks() throws {
        var bytes = Array(repeating: UInt8(0), count: IIGSROMVersion.rom03.expectedSize)
        bytes[0x00000] = 0x03
        bytes[0x20000] = 0xFE
        bytes[0x3FFFF] = 0xFF
        let rom = try IIGSROMImage(bytes: bytes)
        let memory = FlatMemoryBus(size: 0x020000)

        memory.installROM(rom)

        XCTAssertEqual(memory[0xFC0000], 0x03)
        XCTAssertEqual(memory[0xFE0000], 0xFE)
        XCTAssertEqual(memory[0xFFFFFF], 0xFF)
        XCTAssertEqual(memory[0xFBFFFF], 0xFF)
    }

    func testResetUsesInstalledROMVector() throws {
        var bytes = Array(repeating: UInt8(0), count: IIGSROMVersion.rom01.expectedSize)
        bytes[0x1FFFC] = 0x78
        bytes[0x1FFFD] = 0x56
        let rom = try IIGSROMImage(bytes: bytes)
        let machine = IIGSMachine(romImage: rom)

        machine.reset()

        XCTAssertEqual(machine.cpu.registers.programCounter, 0x5678)
    }

    func testInvalidROMSizeIsRejected() {
        XCTAssertThrowsError(try IIGSROMImage(bytes: [0x00])) { error in
            XCTAssertEqual(error as? IIGSROMError, .invalidSize(1))
        }
    }

    func testLocalROM01FixtureCanResetMachineWhenPresent() throws {
        let romURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LocalAssets/ROMs/Apple_IIGS_ROM01.bin")
        guard FileManager.default.fileExists(atPath: romURL.path) else {
            throw XCTSkip("Local ROM01 fixture is not present")
        }

        let rom = try IIGSROMImage(bytes: Array(Data(contentsOf: romURL)))
        let machine = IIGSMachine(romImage: rom)
        let expectedPC = UInt16(rom.byte(at: 0x1FFFC)) | (UInt16(rom.byte(at: 0x1FFFD)) << 8)

        machine.reset()

        XCTAssertEqual(rom.version, .rom01)
        XCTAssertEqual(rom.size, 0x020000)
        XCTAssertEqual(machine.memory[0xFE0000], rom.byte(at: 0))
        XCTAssertEqual(machine.cpu.registers.programCounter, expectedPC)
    }
}
