import XCTest
@testable import IIGSCore

final class SoftSwitchPhase4Tests: XCTestCase {
    func testAlternateZeroPageSwitchMapsZeroPageAndStackToAuxiliaryBank() {
        let memory = FlatMemoryBus(size: 0x020000)

        memory[0x000000] = 0x12
        memory[0x000100] = 0x56
        memory[0x00C009] = 0
        memory[0x000000] = 0x34
        memory[0x000100] = 0x78

        XCTAssertEqual(memory[0x00C016] & 0x80, 0x80)
        XCTAssertEqual(memory[0x000000], 0x34)
        XCTAssertEqual(memory[0x000100], 0x78)

        memory[0x00C008] = 0

        XCTAssertEqual(memory[0x00C016] & 0x80, 0x00)
        XCTAssertEqual(memory[0x000000], 0x12)
        XCTAssertEqual(memory[0x000100], 0x56)
    }

    func testAuxiliaryReadAndWriteSwitchesCanBeControlledIndependently() {
        let memory = FlatMemoryBus(size: 0x020000)

        memory[0x000400] = 0x11
        memory[0x00C005] = 0 // RAMWRT on
        memory[0x000400] = 0xAA

        XCTAssertEqual(memory[0x00C014] & 0x80, 0x80)
        XCTAssertEqual(memory[0x000400], 0x11)

        memory[0x00C003] = 0 // RAMRD on

        XCTAssertEqual(memory[0x00C013] & 0x80, 0x80)
        XCTAssertEqual(memory[0x000400], 0xAA)

        memory[0x00C002] = 0
        memory[0x00C004] = 0

        XCTAssertEqual(memory[0x000400], 0x11)
        XCTAssertEqual(memory[0x00C013] & 0x80, 0x00)
        XCTAssertEqual(memory[0x00C014] & 0x80, 0x00)
    }

    func testClassicVideoSwitchesReportStatusBits() {
        let memory = FlatMemoryBus(size: 0x020000)

        _ = memory[0x00C050] // graphics
        memory[0x00C00D] = 0 // 80-column video on
        memory[0x00C055] = 0 // page 2
        memory[0x00C057] = 0 // hires

        XCTAssertEqual(memory[0x00C01A] & 0x80, 0x80)
        XCTAssertEqual(memory[0x00C01F] & 0x80, 0x80)
        XCTAssertEqual(memory[0x00C01C] & 0x80, 0x80)
        XCTAssertEqual(memory[0x00C01D] & 0x80, 0x80)

        _ = memory[0x00C051] // text
        memory[0x00C00C] = 0 // 80-column video off

        XCTAssertEqual(memory[0x00C01A] & 0x80, 0x00)
        XCTAssertEqual(memory[0x00C01F] & 0x80, 0x00)
    }

    func testC068ControlsMemoryStateRegister() {
        let memory = FlatMemoryBus(size: 0x020000)

        memory[0x00C068] = 0xEC

        XCTAssertEqual(memory[0x00C068] & 0xEC, 0xEC)
        XCTAssertEqual(memory[0x00C016] & 0x80, 0x80)
        XCTAssertEqual(memory[0x00C013] & 0x80, 0x80)
        XCTAssertEqual(memory[0x00C014] & 0x80, 0x80)
        XCTAssertTrue(memory.softSwitches.languageCardReadROM)
        XCTAssertTrue(memory.softSwitches.languageCardBank2)
    }

    func testIOPageMirrorsThroughAuxiliaryAndSlowBanks() {
        let memory = FlatMemoryBus()

        memory[0xE1C029] = 0x80
        memory[0xE1C033] = 0xA5
        memory[0xE1C034] = 0xA0

        XCTAssertEqual(memory.softSwitches.videoControl, 0x80)
        XCTAssertEqual(memory[0x00C033], 0xA5)
        XCTAssertEqual(memory[0xE1C034] & 0x80, 0x00)
        XCTAssertEqual(memory.debugRead8(at: 0xE1C034), 0x00)
    }

    func testGameButtonReadsExposeCommandAndOptionModifiers() {
        let memory = FlatMemoryBus(size: 0x020000)

        XCTAssertEqual(memory[0x00C061] & 0x80, 0x00)
        XCTAssertEqual(memory[0x00C062] & 0x80, 0x00)

        memory.adbController.setModifiers([.command])

        XCTAssertEqual(memory[0x00C061] & 0x80, 0x80)
        XCTAssertEqual(memory[0x00C062] & 0x80, 0x00)

        memory.adbController.setModifiers([.option])

        XCTAssertEqual(memory[0x00C061] & 0x80, 0x00)
        XCTAssertEqual(memory[0x00C062] & 0x80, 0x80)
    }

    func testNewVideoRegisterPowersUpWithBankLatchInhibitSet() {
        let memory = FlatMemoryBus(size: 0x020000)

        XCTAssertEqual(memory[0x00C029] & 0x01, 0x01)
    }

    func testRealTimeClockTransactionsCompleteAndReadParameterRAM() {
        let memory = FlatMemoryBus()

        memory[0x00C033] = 0xBA
        memory[0x00C034] = 0xA0
        memory[0x00C033] = 0x14
        memory[0x00C034] = 0xA0
        memory[0x00C033] = 0xFF
        memory[0x00C034] = 0xE0

        XCTAssertEqual(memory[0x00C034] & 0x80, 0x00)
        XCTAssertEqual(memory[0x00C033], 0x00)
    }

    func testRealTimeClockProvidesValidDefaultComplementChecksumByte() {
        let memory = FlatMemoryBus()

        memory[0x00C033] = 0xBF
        memory[0x00C034] = 0xA0
        memory[0x00C033] = 0x78
        memory[0x00C034] = 0xA0
        memory[0x00C033] = 0x00
        memory[0x00C034] = 0xE0

        XCTAssertEqual(memory[0x00C033], 0x90)
    }

    func testRealTimeClockProvidesBootSignatureBytes() {
        let memory = FlatMemoryBus()

        memory[0x00C033] = 0xBD
        memory[0x00C034] = 0xA0
        memory[0x00C033] = 0x44
        memory[0x00C034] = 0xA0
        memory[0x00C033] = 0x00
        memory[0x00C034] = 0xE0

        XCTAssertEqual(memory[0x00C033], 0xCB)
    }

    func testLanguageCardSoftSwitchesSelectROMOrWritableRAM() throws {
        var bytes = Array(repeating: UInt8(0), count: IIGSROMVersion.rom01.expectedSize)
        bytes[0x1D000] = 0xA5
        let rom = try IIGSROMImage(bytes: bytes)
        let memory = FlatMemoryBus(size: 0x020000)
        memory.installROM(rom)

        XCTAssertEqual(memory[0x00D000], 0xA5)

        _ = memory[0x00C083] // read RAM, bank 2, arm prewrite
        memory[0x00D000] = 0x11
        XCTAssertEqual(memory[0x00D000], 0x00)

        _ = memory[0x00C083] // second access enables writes
        memory[0x00D000] = 0x22

        XCTAssertEqual(memory[0x00D000], 0x22)
        XCTAssertEqual(memory[0x00C012] & 0x80, 0x80)

        _ = memory[0x00C082] // read ROM, bank 2, disable writes

        XCTAssertEqual(memory[0x00D000], 0xA5)
        XCTAssertEqual(memory[0x00C012] & 0x80, 0x00)
    }

    func testLanguageCardBankOneAndBankTwoAreSeparateForD000Page() throws {
        let rom = try IIGSROMImage(bytes: Array(repeating: 0, count: IIGSROMVersion.rom01.expectedSize))
        let memory = FlatMemoryBus(size: 0x020000)
        memory.installROM(rom)

        _ = memory[0x00C083]
        _ = memory[0x00C083]
        memory[0x00D000] = 0x22

        _ = memory[0x00C08B]
        _ = memory[0x00C08B]
        memory[0x00D000] = 0x11

        XCTAssertEqual(memory[0x00D000], 0x11)

        _ = memory[0x00C080]

        XCTAssertEqual(memory[0x00D000], 0x22)
    }
}
