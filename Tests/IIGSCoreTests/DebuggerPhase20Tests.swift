import XCTest
@testable import IIGSCore

final class DebuggerPhase20Tests: XCTestCase {
    func testDebuggerSessionRendersFrameworkOwnedVideoFrame() {
        let session = IIGSDebuggerSession()
        session.machine.memory.write8(0x80, at: 0x00C029)

        let frame = session.renderVideoFrame()

        XCTAssertEqual(frame.width, IIGSVideoRenderer.superHiresWidth)
        XCTAssertEqual(frame.height, IIGSVideoRenderer.superHiresHeight)
        XCTAssertEqual(frame.pixels.count, frame.width * frame.height)
    }

    func testDebuggerSessionKeyboardInputFeedsAppleIIAndADBQueues() {
        let session = IIGSDebuggerSession()

        session.injectKeyboardInput(ascii: 0x41, keyCode: 0x00, modifiers: [.shift], isKeyUp: false)

        XCTAssertEqual(session.machine.memory[0x00C000], 0xC1)
        XCTAssertEqual(session.machine.memory[0x00C025] & IIGSADBModifiers.shift.rawValue, IIGSADBModifiers.shift.rawValue)

        session.machine.memory[0x00C026] = 0x2C
        XCTAssertEqual(session.machine.memory[0x00C026], 0x00)

        session.injectKeyboardInput(ascii: nil, keyCode: 0x00, modifiers: [], isKeyUp: true)
        session.machine.memory[0x00C026] = 0x2C
        XCTAssertEqual(session.machine.memory[0x00C026], 0x80)
    }

    func testDebuggerSessionMouseInputFeedsADBMouseQueue() {
        let session = IIGSDebuggerSession()

        session.moveMouse(dx: 4, dy: -2, buttonDown: true)

        XCTAssertEqual(session.machine.memory[0x00C024], 0x80)
        XCTAssertEqual(session.machine.memory[0x00C024], 0x04)
        XCTAssertEqual(session.machine.memory[0x00C024], 0xFE)
        XCTAssertEqual(session.snapshot().mouse.romX, 4)
        XCTAssertEqual(session.snapshot().mouse.romY, -2)
        XCTAssertTrue(session.snapshot().mouse.buttonDown)
    }

    func testDebuggerSessionLiveBatchStopsAtBreakpoint() throws {
        let session = IIGSDebuggerSession(machine: IIGSMachine(romImage: try makeROM(resetVector: 0x8000)))
        session.loadBinary([0xEA, 0xEA, 0xEA], at: 0x008000)
        _ = try session.execute(.reset(.cold))
        _ = try session.execute(.addBreakpoint(0x008002))

        let result = try session.runLiveBatch(instructionLimit: 100)

        XCTAssertEqual(result.stopReason, .breakpoint(0x008002))
        XCTAssertEqual(result.instructionsExecuted, 2)
        XCTAssertEqual(session.machine.currentProgramAddress, 0x008002)
    }

    private func makeROM(resetVector: UInt16) throws -> IIGSROMImage {
        var bytes = Array(repeating: UInt8(0), count: IIGSROMVersion.rom01.expectedSize)
        bytes[bytes.count - 4] = UInt8(resetVector & 0x00FF)
        bytes[bytes.count - 3] = UInt8(resetVector >> 8)
        return try IIGSROMImage(bytes: bytes, version: .rom01)
    }
}
