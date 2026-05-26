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

    func testAuxiliaryReadAndWriteSwitchesDoNotMoveZeroPageOrStack() {
        let memory = FlatMemoryBus(size: 0x020000)

        memory[0x000080] = 0x11
        memory[0x000180] = 0x22
        memory[0x00C005] = 0 // RAMWRT on
        memory[0x000080] = 0xAA
        memory[0x000180] = 0xBB
        memory[0x00C003] = 0 // RAMRD on

        XCTAssertEqual(memory[0x000080], 0xAA)
        XCTAssertEqual(memory[0x000180], 0xBB)
        XCTAssertEqual(memory.peek8(at: 0x000080), 0xAA)
        XCTAssertEqual(memory.peek8(at: 0x000180), 0xBB)
        XCTAssertEqual(memory.peek8(at: 0x010080), 0x00)
        XCTAssertEqual(memory.peek8(at: 0x010180), 0x00)

        memory[0x00C009] = 0 // ALTZP on
        memory[0x000080] = 0x5A
        memory[0x000180] = 0xA5

        XCTAssertEqual(memory.peek8(at: 0x010080), 0x5A)
        XCTAssertEqual(memory.peek8(at: 0x010180), 0xA5)
        XCTAssertEqual(memory.peek8(at: 0x000080), 0xAA)
        XCTAssertEqual(memory.peek8(at: 0x000180), 0xBB)
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

        memory[0x00C068] = 0xFC

        XCTAssertEqual(memory[0x00C068] & 0xFC, 0xFC)
        XCTAssertEqual(memory[0x00C016] & 0x80, 0x80)
        XCTAssertEqual(memory[0x00C01C] & 0x80, 0x80)
        XCTAssertEqual(memory[0x00C013] & 0x80, 0x80)
        XCTAssertEqual(memory[0x00C014] & 0x80, 0x80)
        XCTAssertTrue(memory.softSwitches.languageCardReadROM)
        XCTAssertTrue(memory.softSwitches.languageCardBank2)
    }

    func testC068DistinguishesPage2FromAuxiliaryBankBits() {
        let memory = FlatMemoryBus(size: 0x020000)

        memory[0x00C068] = 0x40

        XCTAssertEqual(memory[0x00C01C] & 0x80, 0x80)
        XCTAssertEqual(memory[0x00C013] & 0x80, 0x00)
        XCTAssertEqual(memory[0x00C014] & 0x80, 0x00)

        memory[0x00C068] = 0x30

        XCTAssertEqual(memory[0x00C01C] & 0x80, 0x00)
        XCTAssertEqual(memory[0x00C013] & 0x80, 0x80)
        XCTAssertEqual(memory[0x00C014] & 0x80, 0x80)
    }

    func testIIgsVectorPullsUseROMWhileIOShadowingIsEnabled() throws {
        let rom = try IIGSROMImage(bytes: Array(repeating: 0, count: IIGSROMVersion.rom01.expectedSize))
        let memory = FlatMemoryBus()
        memory.installROM(rom)
        memory.resetHardware(.cold)

        XCTAssertEqual(memory.interruptVectorAddress(0x00FFEE), 0xFFFFEE)

        memory[0x00C035] = 0x40

        XCTAssertEqual(memory.interruptVectorAddress(0x00FFEE), 0x00FFEE)
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

    func testUnavailableHighBanksAreNotExposedAsExpansionRAM() {
        let memory = FlatMemoryBus()

        memory[0x7F0000] = 0x34
        memory[0x800000] = 0x12
        memory[0xDF1234] = 0x56
        memory[0xE12000] = 0xA5

        XCTAssertEqual(memory.debugRead8(at: 0x7F0000), 0x34)
        XCTAssertEqual(memory.debugRead8(at: 0x800000), 0xFF)
        XCTAssertEqual(memory.debugRead8(at: 0xDF1234), 0xFF)
        XCTAssertEqual(memory.debugRead8(at: 0xE12000), 0xA5)
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

    func testRealTimeClockSupportsParameterRAMWrites() {
        let memory = FlatMemoryBus()

        memory[0x00C033] = 0x3F
        memory[0x00C034] = 0xA0
        memory[0x00C033] = 0x78
        memory[0x00C034] = 0xA0
        memory[0x00C033] = 0xA5
        memory[0x00C034] = 0xA0

        memory[0x00C033] = 0xBF
        memory[0x00C034] = 0xA0
        memory[0x00C033] = 0x78
        memory[0x00C034] = 0xA0
        memory[0x00C033] = 0xFF
        memory[0x00C034] = 0xE0

        XCTAssertEqual(memory[0x00C033], 0xA5)
    }

    func testClockControlLowNibbleAlsoTracksBorderColor() {
        let memory = FlatMemoryBus()

        memory[0x00C034] = 0xAD

        XCTAssertEqual(memory[0x00C034] & 0x0F, 0x0D)
        XCTAssertEqual(memory.softSwitches.borderColor, 0x0D)
        XCTAssertEqual(memory.softSwitches.displayBorderColors[0], 0x0D)
    }

    func testRealTimeClockProvidesDisplayColorDefaults() {
        let memory = FlatMemoryBus()

        memory[0x00C033] = 0xB8
        memory[0x00C034] = 0xA0
        memory[0x00C033] = 0x68
        memory[0x00C034] = 0xA0
        memory[0x00C033] = 0x00
        memory[0x00C034] = 0xE0

        XCTAssertEqual(memory[0x00C033], 0x0F)

        memory[0x00C033] = 0xB8
        memory[0x00C034] = 0xA0
        memory[0x00C033] = 0x6C
        memory[0x00C034] = 0xA0
        memory[0x00C033] = 0x00
        memory[0x00C034] = 0xE0

        XCTAssertEqual(memory[0x00C033], 0x06)
    }

    func testBatteryRAMProvidesBootSlotDefaultsAndChecksum() {
        let memory = FlatMemoryBus()
        let bytes = memory.batteryRAMSnapshot

        XCTAssertEqual(bytes[0x25], 0x00)
        XCTAssertEqual(bytes[0x26], 0x00)
        XCTAssertEqual(bytes[0x27], 0x01)
        XCTAssertEqual(bytes[0x28], 0x00)
        XCTAssertEqual(bytes[0x1E], 0x0F)
        XCTAssertTrue(memory.batteryRAMChecksumIsValid)
        XCTAssertTrue(batteryRAMChecksumIsValid(bytes))
    }

    func testBatteryRAMHighLevelWriteUpdatesChecksum() {
        let memory = FlatMemoryBus()

        memory.setBatteryRAMByte(0x05, at: 0x28)

        XCTAssertEqual(memory.batteryRAMSnapshot[0x28], 0x05)
        XCTAssertTrue(memory.batteryRAMChecksumIsValid)
    }

    func testInvalidLoadedBatteryRAMFallsBackToDefaults() {
        let memory = FlatMemoryBus()

        memory.loadBatteryRAM(Array(repeating: 0, count: 256))

        XCTAssertEqual(memory.batteryRAMSnapshot[0x28], 0x00)
        XCTAssertEqual(memory.batteryRAMSnapshot[0x1E], 0x0F)
        XCTAssertTrue(memory.batteryRAMChecksumIsValid)
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

    func testLanguageCardD000BankOneUsesHiddenC000RAM() throws {
        let rom = try IIGSROMImage(bytes: Array(repeating: 0, count: IIGSROMVersion.rom01.expectedSize))
        let memory = FlatMemoryBus(size: 0x020000)
        memory.installROM(rom)

        _ = memory[0x00C08B]
        _ = memory[0x00C08B]
        memory[0x00D123] = 0x5A

        XCTAssertEqual(memory.peek8(at: 0x00C123), 0x5A)
        XCTAssertEqual(memory.peek8(at: 0x00D123), 0x00)
        XCTAssertEqual(memory[0x00D123], 0x5A)
    }

    func testAuxiliaryBankLanguageCardCanReadROMAndWriteRAM() throws {
        var bytes = Array(repeating: UInt8(0), count: IIGSROMVersion.rom01.expectedSize)
        bytes[0x1E123] = 0xA5
        let rom = try IIGSROMImage(bytes: bytes)
        let memory = FlatMemoryBus(size: 0x020000)
        memory.installROM(rom)

        XCTAssertEqual(memory[0x01E123], 0xA5)

        _ = memory[0x00C083]
        _ = memory[0x00C083]
        memory[0x01E123] = 0x3C

        XCTAssertEqual(memory[0x01E123], 0x3C)
    }

    func testAlternateZeroPageMovesBankZeroLanguageCardRAMToAuxiliaryBank() throws {
        let rom = try IIGSROMImage(bytes: Array(repeating: 0, count: IIGSROMVersion.rom01.expectedSize))
        let memory = FlatMemoryBus(size: 0x020000)
        memory.installROM(rom)

        _ = memory[0x00C009]
        _ = memory[0x00C083]
        _ = memory[0x00C083]
        memory[0x00D000] = 0x7E
        memory[0x00E000] = 0x81

        XCTAssertEqual(memory.peek8(at: 0x01D000), 0x7E)
        XCTAssertEqual(memory.peek8(at: 0x01E000), 0x81)
        XCTAssertEqual(memory.peek8(at: 0x00D000), 0x00)
        XCTAssertEqual(memory.peek8(at: 0x00E000), 0x00)
    }

    func testSlowBanksUseLanguageCardD000BankSelectionWithoutROMOverlay() throws {
        var bytes = Array(repeating: UInt8(0), count: IIGSROMVersion.rom01.expectedSize)
        bytes[0x1D000] = 0xA5
        let rom = try IIGSROMImage(bytes: bytes)
        let memory = FlatMemoryBus()
        memory.installROM(rom)

        _ = memory[0x00C083]
        _ = memory[0x00C083]
        memory[0xE0D000] = 0x22
        _ = memory[0x00C08B]
        _ = memory[0x00C08B]
        memory[0xE0D000] = 0x11

        XCTAssertEqual(memory[0xE0D000], 0x11)

        _ = memory[0x00C082]

        XCTAssertEqual(memory[0x00D000], 0xA5)
        XCTAssertEqual(memory[0xE0D000], 0x22)
    }

    private func batteryRAMChecksumIsValid(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 256 else {
            return false
        }

        var checksum: UInt16 = 0
        for index in stride(from: 0xFA, through: 0x00, by: -1) {
            checksum = (checksum << 1) | (checksum >> 15)
            let word = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
            checksum = checksum &+ word
        }

        let stored = UInt16(bytes[0xFC]) | (UInt16(bytes[0xFD]) << 8)
        let complement = UInt16(bytes[0xFE]) | (UInt16(bytes[0xFF]) << 8)
        return stored == checksum && complement == (checksum ^ 0xAAAA)
    }
}
