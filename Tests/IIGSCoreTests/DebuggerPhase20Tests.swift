import XCTest
@testable import IIGSCore

final class DebuggerPhase20Tests: XCTestCase {
    func testDebuggerSessionRendersFrameworkOwnedVideoFrame() {
        let session = IIGSDebuggerSession()
        session.machine.memory.write8(0x80, at: 0x00C029)

        let frame = session.renderVideoFrame()

        XCTAssertEqual(frame.width, IIGSVideoRenderer.superHiresWidth + IIGSVideoRenderer.wideBorderX * 2)
        XCTAssertEqual(frame.height, IIGSVideoRenderer.superHiresHeight + IIGSVideoRenderer.superHiresBorderY * 2)
        XCTAssertEqual(frame.pixels.count, frame.width * frame.height)
    }

    func testDebuggerSessionRendersPreEnableSuperHiresShadowWrites() {
        let session = IIGSDebuggerSession()
        writePaletteEntry(1, raw: 0x0F00, to: session.machine.memory)

        session.machine.memory.write8(0x11, at: 0x012000)
        session.machine.memory.write8(0x80, at: 0x00C029)

        let frame = session.renderVideoFrame()

        XCTAssertEqual(session.machine.memory.debugRead8(at: 0xE12000), 0x11)
        XCTAssertEqual(frame[IIGSVideoRenderer.wideBorderX, IIGSVideoRenderer.superHiresBorderY], IIGSRGBColor(red: 0xFF, green: 0x00, blue: 0x00))
        XCTAssertEqual(frame[IIGSVideoRenderer.wideBorderX + 1, IIGSVideoRenderer.superHiresBorderY], IIGSRGBColor(red: 0xFF, green: 0x00, blue: 0x00))
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

    func testDebuggerSessionControlResetRunsMachineReset() throws {
        let session = IIGSDebuggerSession(machine: IIGSMachine(romImage: try makeROM(resetVector: 0x9000)))

        session.injectKeyboardInput(ascii: nil, keyCode: 0x7F, modifiers: [.control], isKeyUp: false)

        XCTAssertEqual(session.machine.currentProgramAddress, 0x009000)
        XCTAssertEqual(session.machine.memory.adbController.modifierRegister & IIGSADBModifiers.control.rawValue, IIGSADBModifiers.control.rawValue)
    }

    func testDebuggerSessionMouseInputFeedsADBMouseQueue() {
        let session = IIGSDebuggerSession()

        session.moveMouse(dx: 4, dy: -2, buttonDown: true)

        XCTAssertEqual(session.machine.memory[0x00C024], 0x84)
        XCTAssertEqual(session.machine.memory[0x00C024], 0x7E)
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

    func testDebuggerSessionLiveCycleBatchStopsAtBreakpoint() throws {
        let session = IIGSDebuggerSession(machine: IIGSMachine(romImage: try makeROM(resetVector: 0x8000)))
        session.loadBinary([0xEA, 0xEA, 0xEA], at: 0x008000)
        _ = try session.execute(.reset(.cold))
        _ = try session.execute(.addBreakpoint(0x008002))

        let result = try session.runLiveCycleBatch(cycleLimit: 1_000, instructionLimit: 100)

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

    private func writePaletteEntry(_ entry: Int, raw: UInt16, to memory: FlatMemoryBus, palette: Int = 0) {
        let address = UInt32(0xE19E00 + (palette * 16 + entry) * 2)
        memory.write8(UInt8(raw & 0x00FF), at: address)
        memory.write8(UInt8(raw >> 8), at: address + 1)
    }
}
