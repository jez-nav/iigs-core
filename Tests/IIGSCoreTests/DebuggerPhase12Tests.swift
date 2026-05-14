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

    private func makeROM(resetVector: UInt16) throws -> IIGSROMImage {
        var bytes = Array(repeating: UInt8(0), count: IIGSROMVersion.rom01.expectedSize)
        bytes[bytes.count - 4] = UInt8(resetVector & 0x00FF)
        bytes[bytes.count - 3] = UInt8(resetVector >> 8)
        return try IIGSROMImage(bytes: bytes, version: .rom01)
    }
}
