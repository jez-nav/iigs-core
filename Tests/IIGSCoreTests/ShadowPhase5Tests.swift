import XCTest
@testable import IIGSCore

final class ShadowPhase5Tests: XCTestCase {
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

    func testSuperHiresShadowFromAuxiliaryBankRequiresSHREnabled() {
        let memory = FlatMemoryBus()

        memory[0x012000] = 0x55
        XCTAssertEqual(memory[0xE12000], 0x00)

        memory[0x00C029] = 0x80
        memory[0x012000] = 0x66

        XCTAssertEqual(memory[0xE12000], 0x66)
    }

    func testSuperHiresShadowCanBeInhibited() {
        let memory = FlatMemoryBus()

        memory[0x00C029] = 0x80
        memory[0x00C035] = 0x10
        memory[0x012000] = 0xCC

        XCTAssertEqual(memory[0x012000], 0xCC)
        XCTAssertEqual(memory[0xE12000], 0x00)
    }

    func testShadowAllCopiesOddExpansionBanksIntoSuperHiresShadow() {
        let memory = FlatMemoryBus()

        memory[0x00C029] = 0x80
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
