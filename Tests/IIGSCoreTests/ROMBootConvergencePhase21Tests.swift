import XCTest
@testable import IIGSCore

final class ROMBootConvergencePhase21Tests: XCTestCase {
    func testDiagnosticDecoderUsesTechnicalNote95TestNames() {
        let vblFailure = IIGSROMDiagnosticCode(rawValue: 0x0B01_0000)

        XCTAssertEqual(vblFailure.testNumber, 0x0B)
        XCTAssertEqual(vblFailure.testName, "Interrupts Test")
        XCTAssertTrue(vblFailure.detail.contains("VBL interrupt timeout"))
        XCTAssertTrue(vblFailure.description.contains("$0B010000"))
    }

    func testDiagnosticDecoderKeepsUnknownFFFFVisible() {
        let unknown = IIGSROMDiagnosticCode(rawValue: 0xFFFF_0000)

        XCTAssertEqual(unknown.testName, "Unknown ROM diagnostic test")
        XCTAssertTrue(unknown.description.contains("BB=$FF"))
    }

    func testDebuggerParsesAndFormatsDiagnosticCommand() throws {
        let parser = IIGSDebuggerCommandParser()
        XCTAssertEqual(try parser.parse("diag 0A010000"), .decodeDiagnostic(0x0A01_0000))

        let session = IIGSDebuggerSession()
        let output = try session.execute(.decodeDiagnostic(0x0A01_0000))

        XCTAssertTrue(output.contains("Shadow Register Test"))
        XCTAssertTrue(output.contains("text page 1 shadow failed"))
    }

    func testColdResetRestoresROM1VisibleStartupHardwareDefaults() throws {
        let machine = IIGSMachine(romImage: try makeROM(resetVector: 0x8000))
        machine.memory[0x00C035] = 0x00
        machine.memory[0x00C036] = 0x80
        machine.memory[0x00C068] = 0xEC
        machine.memory.adbController.setModifiers([.command, .option])

        machine.reset(.cold)

        XCTAssertEqual(machine.memory.softSwitches.stateRegister, 0x0C)
        XCTAssertEqual(machine.memory.softSwitches.shadowInhibit, 0x08)
        XCTAssertEqual(machine.memory.softSwitches.speedRegister & 0x80, 0x00)
        XCTAssertEqual(machine.memory.softSwitches.videoControl & 0x01, 0x01)
        XCTAssertEqual(machine.memory.adbController.modifierRegister, 0x00)
        XCTAssertEqual(machine.memory[0x00C061] & 0x80, 0x00)
        XCTAssertEqual(machine.memory[0x00C062] & 0x80, 0x00)
        XCTAssertFalse(machine.memory.irqLineAsserted)
    }

    func testMegaIIVideoCounterEncodingMatchesTechnicalNote39ReadbackRecipe() {
        XCTAssertEqual(IIGSVideoTiming.verticalCounter(atCycle: 0), 0x80)
        XCTAssertEqual(IIGSVideoTiming.horizontalCounter(atCycle: 0) & 0x80, 0x00)
        XCTAssertEqual(decodedScanline(atCycle: 0), 0)

        let line1 = UInt64(IIGSVideoTiming.cyclesPerLine)
        XCTAssertEqual(IIGSVideoTiming.verticalCounter(atCycle: line1), 0x80)
        XCTAssertEqual(IIGSVideoTiming.horizontalCounter(atCycle: line1) & 0x80, 0x80)
        XCTAssertEqual(decodedScanline(atCycle: line1), 1)

        let vblStart = UInt64(IIGSVideoTiming.classicVisibleLines * IIGSVideoTiming.cyclesPerLine)
        XCTAssertEqual(decodedScanline(atCycle: vblStart), UInt8(IIGSVideoTiming.classicVisibleLines))
        XCTAssertEqual(IIGSVideoTiming.verticalBlankStatus(atCycle: vblStart - 1), 0x00)
        XCTAssertEqual(IIGSVideoTiming.verticalBlankStatus(atCycle: vblStart), 0x80)
    }

    func testDebuggerSnapshotExposesBootCriticalHardwareState() throws {
        let session = IIGSDebuggerSession(machine: IIGSMachine(romImage: try makeROM(resetVector: 0x8000)))
        _ = try session.execute(.reset(.cold))

        let snapshot = session.snapshot()

        XCTAssertEqual(snapshot.hardware.stateRegister, 0x0C)
        XCTAssertEqual(snapshot.hardware.shadowInhibit, 0x08)
        XCTAssertEqual(snapshot.hardware.keyboardModifiers, 0x00)
        XCTAssertEqual(snapshot.hardware.verticalCounter, IIGSVideoTiming.verticalCounter(atCycle: session.machine.memory.cycleCount))
    }

    private func decodedScanline(atCycle cycle: UInt64) -> UInt8 {
        let horizontal = IIGSVideoTiming.horizontalCounter(atCycle: cycle)
        let vertical = IIGSVideoTiming.verticalCounter(atCycle: cycle)
        let carry = horizontal & 0x80 != 0
        return (vertical << 1) | (carry ? 1 : 0)
    }

    private func makeROM(resetVector: UInt16) throws -> IIGSROMImage {
        var bytes = Array(repeating: UInt8(0xEA), count: IIGSROMVersion.rom01.expectedSize)
        bytes[bytes.count - 4] = UInt8(resetVector & 0x00FF)
        bytes[bytes.count - 3] = UInt8(resetVector >> 8)
        return try IIGSROMImage(bytes: bytes)
    }
}
