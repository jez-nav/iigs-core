import XCTest
@testable import IIGSCore

final class DebuggerPhase12Tests: XCTestCase {
    func testParserRecognizesCoreCommandsAndHexAddressForms() throws {
        let parser = IIGSDebuggerCommandParser()

        XCTAssertEqual(try parser.parse("regs"), .registers)
        XCTAssertEqual(try parser.parse("step 3"), .step(3))
        XCTAssertEqual(try parser.parse("run $10"), .run(16))
        XCTAssertEqual(try parser.parse("cycles 20"), .runCycles(20))
        XCTAssertEqual(try parser.parse("bp 00/8000"), .addBreakpoint(0x008000))
        XCTAssertEqual(try parser.parse("bc 0x00C000"), .removeBreakpoint(0x00C000))
        XCTAssertEqual(try parser.parse("mem $E1:2000 4"), .readMemory(0xE12000, 4))
        XCTAssertEqual(try parser.parse("set C030 FF"), .writeMemory(0x00C030, 0xFF))
        XCTAssertEqual(try parser.parse("reset warm"), .reset(.warm))
        XCTAssertEqual(try parser.parse("snapshot"), .snapshot)
        XCTAssertEqual(try parser.parse("events"), .events)
        XCTAssertEqual(try parser.parse("schedule paddle 20 2"), .scheduleEvent(.paddleTimeout, 20, 2))
        XCTAssertEqual(try parser.parse("runpc 008010 100"), .runUntilPC(0x008010, 100))
        XCTAssertEqual(try parser.parse("assert pc 008000"), .assertion(.programCounter(0x008000)))
        XCTAssertEqual(try parser.parse("assert reg A 42"), .assertion(.register("A", 0x42)))
        XCTAssertEqual(try parser.parse("assert flag Z 1"), .assertion(.flag("Z", true)))
        XCTAssertEqual(try parser.parse("assert status irq 0"), .assertion(.status("irq", false)))
        XCTAssertEqual(try parser.parse("assert mem 2000 5A"), .assertion(.memory(0x002000, 0x5A)))
        XCTAssertEqual(try parser.parse("assert cycles >= 10"), .assertion(.cycles(.greaterThanOrEqual, 10)))
        XCTAssertEqual(try parser.parse("quit"), .quit)
        XCTAssertNil(try parser.parse(""))
    }

    func testParserReportsUsefulErrors() {
        let parser = IIGSDebuggerCommandParser()

        XCTAssertThrowsError(try parser.parse("nope")) { error in
            XCTAssertEqual(error as? IIGSDebuggerError, .unknownCommand("nope"))
        }
        XCTAssertThrowsError(try parser.parse("bp")) { error in
            XCTAssertEqual(error as? IIGSDebuggerError, .missingArgument("breakpoint address"))
        }
        XCTAssertThrowsError(try parser.parse("set 2000 zzz")) { error in
            XCTAssertEqual(error as? IIGSDebuggerError, .invalidNumber("zzz"))
        }
    }

    func testSessionLoadsBinaryAndReadsWritesMemory() throws {
        let session = IIGSDebuggerSession(machine: IIGSMachine(romImage: try makeROM(resetVector: 0x8000)))

        session.loadBinary([0xA9, 0x42], at: 0x008000)
        XCTAssertEqual(try session.execute(.readMemory(0x008000, 2)), "$008000: $A9 $42")
        XCTAssertEqual(try session.execute(.writeMemory(0x002000, 0x5A)), "$002000 <- $5A")
        XCTAssertEqual(try session.execute(.readMemory(0x002000, 1)), "$002000: $5A")
    }

    func testSessionResetRegistersAndStepOutput() throws {
        let session = IIGSDebuggerSession(machine: IIGSMachine(romImage: try makeROM(resetVector: 0x8000)))
        session.loadBinary([0xA9, 0x7F], at: 0x008000)

        XCTAssertEqual(try session.execute(.reset(.cold)), "Reset cold PC=$008000")
        let stepOutput = try session.execute(.step(1))

        XCTAssertTrue(stepOutput.contains("Stepped 1 instruction"))
        XCTAssertTrue(stepOutput.contains("last $008000"))
        XCTAssertTrue(stepOutput.contains("A=$007F"))
        XCTAssertTrue(try session.execute(.registers).contains("PC=$008002"))
    }

    func testSessionRunStopsAtBreakpoint() throws {
        let session = IIGSDebuggerSession(machine: IIGSMachine(romImage: try makeROM(resetVector: 0x8000)))
        session.loadBinary([0xEA, 0xEA, 0xCB], at: 0x008000)
        _ = try session.execute(.reset(.cold))

        XCTAssertEqual(try session.execute(.addBreakpoint(0x008002)), "Breakpoint set at $008002")
        XCTAssertEqual(try session.execute(.listBreakpoints), "$008002")
        let runOutput = try session.execute(.run(10))

        XCTAssertTrue(runOutput.contains("Stopped: breakpoint $008002"))
        XCTAssertTrue(runOutput.contains("instructions=2"))
        XCTAssertEqual(session.machine.currentProgramAddress, 0x008002)
        XCTAssertEqual(try session.execute(.removeBreakpoint(0x008002)), "Breakpoint cleared at $008002")
        XCTAssertEqual(try session.execute(.listBreakpoints), "No breakpoints")
    }

    func testSessionRunCyclesAndHelp() throws {
        let session = IIGSDebuggerSession(machine: IIGSMachine(romImage: try makeROM(resetVector: 0x8000)))
        session.loadBinary([0xEA, 0xEA, 0xEA], at: 0x008000)
        _ = try session.execute(.reset(.cold))

        let output = try session.execute(.runCycles(2))

        XCTAssertTrue(output.contains("Stopped: cycle limit"))
        XCTAssertTrue(output.contains("PC=$008002"))
        XCTAssertTrue(try session.execute(.help).contains("Commands:"))
    }

    func testSessionPhase17AssertionsSnapshotAndEvents() throws {
        let session = IIGSDebuggerSession(machine: IIGSMachine(romImage: try makeROM(resetVector: 0x8000)))
        session.loadBinary([
            0xA9, 0x00,       // LDA #$00
            0x8D, 0x00, 0x20, // STA $2000
            0xCB              // WAI
        ], at: 0x008000)

        _ = try session.execute(.reset(.cold))
        _ = try session.execute(.step(2))

        XCTAssertEqual(try session.execute(.assertion(.programCounter(0x008005))), "ASSERT OK pc $008005")
        XCTAssertEqual(try session.execute(.assertion(.register("A", 0x0000))), "ASSERT OK reg A $0000")
        XCTAssertEqual(try session.execute(.assertion(.flag("Z", true))), "ASSERT OK flag Z 1")
        XCTAssertEqual(try session.execute(.assertion(.memory(0x002000, 0x00))), "ASSERT OK mem $002000 $00")
        XCTAssertNoThrow(try session.execute(.assertion(.cycles(.greaterThanOrEqual, 1))))

        let snapshot = try session.execute(.snapshot)
        XCTAssertTrue(snapshot.contains("flags=N0"))
        XCTAssertTrue(snapshot.contains("status=RDY1"))
        XCTAssertTrue(snapshot.contains("timing=cycles:"))

        XCTAssertEqual(
            try session.execute(.scheduleEvent(.paddleTimeout, 3, 2)),
            "Scheduled paddleTimeout after 3 cycle(s) payload=000002"
        )
        session.machine.advanceCycles(3)
        XCTAssertTrue(try session.execute(.events).contains("serviced"))
        XCTAssertTrue(try session.execute(.events).contains("paddleTimeout"))
    }

    func testSessionPhase17AssertionFailureIsUseful() throws {
        let session = IIGSDebuggerSession(machine: IIGSMachine(romImage: try makeROM(resetVector: 0x8000)))
        _ = try session.execute(.reset(.cold))

        XCTAssertThrowsError(try session.execute(.assertion(.programCounter(0x008001)))) { error in
            XCTAssertEqual(error as? IIGSDebuggerError, .assertionFailed("PC expected $008001 got $008000"))
        }
    }

    private func makeROM(resetVector: UInt16) throws -> IIGSROMImage {
        var bytes = Array(repeating: UInt8(0), count: IIGSROMVersion.rom01.expectedSize)
        bytes[bytes.count - 4] = UInt8(resetVector & 0x00FF)
        bytes[bytes.count - 3] = UInt8(resetVector >> 8)
        return try IIGSROMImage(bytes: bytes, version: .rom01)
    }
}
