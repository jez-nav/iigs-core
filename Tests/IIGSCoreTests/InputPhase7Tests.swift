import XCTest
@testable import IIGSCore

final class InputPhase7Tests: XCTestCase {
    func testAppleIIKeyboardStrobeRepeatsUntilCleared() {
        let memory = FlatMemoryBus()

        memory.adbController.injectAppleIIKey(0x41)

        XCTAssertEqual(memory[0x00C000], 0xC1)
        XCTAssertEqual(memory[0x00C000], 0xC1)

        _ = memory[0x00C010]

        XCTAssertEqual(memory[0x00C000], 0x41)
    }

    func testAppleIIKeyboardModifierRegisterTracksControlKey() {
        let memory = FlatMemoryBus()

        memory.adbController.injectAppleIIKey(0x03, modifiers: [.control])

        XCTAssertEqual(memory[0x00C000], 0x83)
        XCTAssertEqual(memory[0x00C025] & IIGSADBModifiers.control.rawValue, IIGSADBModifiers.control.rawValue)
    }

    func testADBVersionCommandReturnsROM01RevisionByDefault() {
        let memory = FlatMemoryBus()

        memory[0x00C026] = 0x0D

        XCTAssertEqual(memory[0x00C027] & 0x20, 0x20)
        XCTAssertEqual(memory[0x00C026], 5)
        XCTAssertEqual(memory[0x00C027] & 0x20, 0x00)
    }

    func testADBVersionTracksInstalledROMGeneration() throws {
        var bytes = Array(repeating: UInt8(0), count: IIGSROMVersion.rom03.expectedSize)
        bytes[0x3FFFC] = 0x00
        bytes[0x3FFFD] = 0x20
        let rom = try IIGSROMImage(bytes: bytes)
        let memory = FlatMemoryBus(size: 0x020000)

        memory.installROM(rom)
        memory[0x00C026] = 0x0D

        XCTAssertEqual(memory[0x00C026], 6)
    }

    func testADBDataInterruptFollowsDataValidResponse() {
        let memory = FlatMemoryBus()

        memory[0x00C027] = 0x10
        memory[0x00C026] = 0x0D

        XCTAssertTrue(memory.adbController.irqAsserted)
        XCTAssertEqual(memory[0x00C027] & 0x30, 0x30)

        _ = memory[0x00C026]

        XCTAssertFalse(memory.adbController.irqAsserted)
        XCTAssertEqual(memory[0x00C027] & 0x20, 0x00)
    }

    func testADBRAMWriteAndReadCommandsRoundTripOneByte() {
        let memory = FlatMemoryBus()

        memory[0x00C026] = 0x08
        memory[0x00C026] = 0x42
        memory[0x00C026] = 0x99
        memory[0x00C026] = 0x09
        memory[0x00C026] = 0x42

        XCTAssertEqual(memory[0x00C026], 0x99)
    }

    func testKeyboardTalkRegisterZeroReturnsQueuedKeyEvents() {
        let memory = FlatMemoryBus()
        memory.adbController.queueKeyboardKeyDownUp(keyCode: 0x00)

        XCTAssertEqual(memory[0x00C027] & 0x08, 0x08)

        memory[0x00C026] = 0x2C
        XCTAssertEqual(memory[0x00C026], 0x00)
        XCTAssertEqual(memory[0x00C027] & 0x08, 0x08)

        memory[0x00C026] = 0x2C
        XCTAssertEqual(memory[0x00C026], 0x80)
        XCTAssertEqual(memory[0x00C027] & 0x08, 0x00)
    }

    func testMouseMovementIsAvailableThroughMouseRegisterPath() {
        let memory = FlatMemoryBus()

        memory.adbController.moveMouse(dx: 5, dy: -3, buttonDown: true)

        XCTAssertEqual(memory[0x00C027] & 0x80, 0x80)
        XCTAssertEqual(memory[0x00C024], 0x80)
        XCTAssertEqual(memory[0x00C024], 0x05)
        XCTAssertEqual(memory[0x00C024], 0xFD)
        XCTAssertEqual(memory[0x00C027] & 0x80, 0x00)
        XCTAssertEqual(memory.adbController.mouseX, 5)
        XCTAssertEqual(memory.adbController.mouseY, -3)
        XCTAssertTrue(memory.adbController.mouseButtonDown)
    }

    func testMouseInterruptFollowsMouseDataAvailability() {
        let memory = FlatMemoryBus()

        memory[0x00C027] = 0x40
        memory.adbController.moveMouse(dx: 1, dy: 2, buttonDown: false)

        XCTAssertTrue(memory.adbController.irqAsserted)

        _ = memory[0x00C024]
        _ = memory[0x00C024]
        _ = memory[0x00C024]

        XCTAssertFalse(memory.adbController.irqAsserted)
    }

    func testListenRegisterThreeChangesKeyboardAddress() {
        let memory = FlatMemoryBus()
        memory.adbController.queueKeyboardEvent(keyCode: 0x12)

        memory[0x00C026] = 0x2B
        memory[0x00C026] = 0x00
        memory[0x00C026] = 0x05

        memory[0x00C026] = 0x2C
        XCTAssertEqual(memory[0x00C027] & 0x20, 0x00)

        memory[0x00C026] = 0x5C
        XCTAssertEqual(memory[0x00C026], 0x12)
    }
}
