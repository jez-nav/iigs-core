import XCTest
@testable import IIGSCore

final class ShadowPhase5Tests: XCTestCase {
    func testSlowMemoryBanksAreSeparateFromFastBanksOutsideShadowedWrites() {
        let memory = FlatMemoryBus()

        memory[0x000300] = 0x12
        memory[0x010300] = 0x34
        memory[0x00A000] = 0x56
        memory[0x01A000] = 0x78

        XCTAssertEqual(memory[0xE00300], 0x00)
        XCTAssertEqual(memory[0xE10300], 0x00)
        XCTAssertEqual(memory[0xE0A000], 0x00)
        XCTAssertEqual(memory[0xE1A000], 0x00)

        memory[0xE00301] = 0x9A
        memory[0xE10301] = 0xBC

        XCTAssertEqual(memory[0x000301], 0x00)
        XCTAssertEqual(memory[0x010301], 0x00)
        XCTAssertEqual(memory[0xE00301], 0x9A)
        XCTAssertEqual(memory[0xE10301], 0xBC)
    }

    func testToolboxJumpTableAreaIsNotClobberedByAuxiliaryRAMWrites() {
        let memory = FlatMemoryBus()

        memory[0xE10000] = 0x5C
        memory[0xE103C0] = 0xA5
        memory[0x010000] = 0x00
        memory[0x0103C0] = 0x00

        XCTAssertEqual(memory[0xE10000], 0x5C)
        XCTAssertEqual(memory[0xE103C0], 0xA5)
        XCTAssertEqual(memory[0x010000], 0x00)
        XCTAssertEqual(memory[0x0103C0], 0x00)
    }

    func testClassicTextAndHiresWritesShadowIntoE0() {
        let memory = FlatMemoryBus()

        memory[0x000400] = 0x11
        memory[0x000800] = 0x22
        memory[0x002000] = 0x33
        memory[0x004000] = 0x44

        XCTAssertEqual(memory[0xE00400], 0x11)
        XCTAssertEqual(memory[0xE00800], 0x22)
        XCTAssertEqual(memory[0xE02000], 0x33)
        XCTAssertEqual(memory[0xE04000], 0x44)
    }

    func testClassicShadowInhibitPreventsOnlySelectedRegion() {
        let memory = FlatMemoryBus()

        memory[0x00C035] = 0x01
        memory[0x000400] = 0xAA
        memory[0x000800] = 0xBB

        XCTAssertEqual(memory[0x000400], 0xAA)
        XCTAssertEqual(memory[0xE00400], 0x00)
        XCTAssertEqual(memory[0xE00800], 0xBB)
        XCTAssertEqual(memory[0x00C035], 0x01)
    }

    func testAuxiliaryWriteSwitchStillShadowsDisplayVisibleClassicPage() {
        let memory = FlatMemoryBus()

        memory[0x00C005] = 0 // RAMWRT on
        memory[0x000400] = 0x7E

        XCTAssertEqual(memory[0x000400], 0x00)
        XCTAssertEqual(memory[0x010400], 0x7E)
        XCTAssertEqual(memory[0xE00400], 0x7E)
    }

    func testSuperHiresShadowFromAuxiliaryBankDoesNotRequireSHREnabled() {
        let memory = FlatMemoryBus()

        memory[0x012000] = 0x55
        XCTAssertEqual(memory[0xE12000], 0x55)

        memory[0x00C029] = 0x80
        memory[0x012000] = 0x66

        XCTAssertEqual(memory[0xE12000], 0x66)
    }

    func testSuperHiresShadowCanBeInhibited() {
        let memory = FlatMemoryBus()

        memory[0x00C035] = 0x08
        memory[0x012000] = 0xCC

        XCTAssertEqual(memory[0x012000], 0xCC)
        XCTAssertEqual(memory[0xE12000], 0x00)
    }

    func testROMStartupShadowDefaultInhibitsSuperHiresShadow() {
        let memory = FlatMemoryBus()

        memory.resetHardware(.cold)
        memory[0x012000] = 0xCC

        XCTAssertEqual(memory[0x00C035], 0x08)
        XCTAssertEqual(memory[0x012000], 0xCC)
        XCTAssertEqual(memory[0xE12000], 0x00)

        memory[0x00C035] = 0x00
        memory[0x012000] = 0xDD

        XCTAssertEqual(memory[0xE12000], 0xDD)
    }

    func testShadowAllCopiesOddExpansionBanksIntoSuperHiresShadow() {
        let memory = FlatMemoryBus()

        memory[0x032000] = 0x12
        XCTAssertEqual(memory[0xE12000], 0x00)

        memory[0x00C036] = 0x10
        memory[0x032000] = 0x34
        memory[0x042000] = 0x56

        XCTAssertEqual(memory[0xE12000], 0x34)
        XCTAssertEqual(memory[0x042000], 0x56)
        XCTAssertEqual(memory[0x00C036] & 0x10, 0x10)
    }
}
