import XCTest
@testable import IIGSCore

final class DebuggerPhase19Tests: XCTestCase {
    func testDisassemblerUsesCurrentAccumulatorAndIndexWidths() {
        let disassembler = IIGSDisassembler()
        let bytes: [UInt32: UInt8] = [
            0x008000: 0xA9,
            0x008001: 0x34,
            0x008002: 0x12,
            0x008003: 0xA2,
            0x008004: 0x56,
            0x008005: 0x78,
        ]

        let native16 = IIGSDisassemblyOptions(accumulatorIs8Bit: false, indexRegistersAre8Bit: false)
        let lda16 = disassembler.decode(at: 0x008000, readByte: { bytes[$0, default: 0] }, options: native16)
        let ldx16 = disassembler.decode(at: 0x008003, readByte: { bytes[$0, default: 0] }, options: native16)

        XCTAssertEqual(lda16.bytes, [0xA9, 0x34, 0x12])
        XCTAssertEqual(lda16.text, "LDA #$1234")
        XCTAssertEqual(ldx16.text, "LDX #$7856")

        let emulationWidths = IIGSDisassemblyOptions(accumulatorIs8Bit: true, indexRegistersAre8Bit: true)
        let lda8 = disassembler.decode(at: 0x008000, readByte: { bytes[$0, default: 0] }, options: emulationWidths)

        XCTAssertEqual(lda8.bytes, [0xA9, 0x34])
        XCTAssertEqual(lda8.text, "LDA #$34")
    }

    func testDisassemblerFormatsRelativeTargetsAndUnknownOpcodes() {
        let bytes: [UInt32: UInt8] = [
            0x008000: 0xD0,
            0x008001: 0xFE,
            0x008002: 0xFF,
        ]
        let options = IIGSDisassemblyOptions(accumulatorIs8Bit: true, indexRegistersAre8Bit: true)
        let disassembler = IIGSDisassembler()

        let branch = disassembler.decode(at: 0x008000, readByte: { bytes[$0, default: 0] }, options: options)
        let unknown = disassembler.decode(at: 0x008002, readByte: { bytes[$0, default: 0] }, options: options)

        XCTAssertEqual(branch.text, "BNE $008000")
        XCTAssertEqual(unknown.text, "DB $FF")
    }

    func testSessionDisassemblyRowsReadMemoryWithoutAdvancingCycles() throws {
        let session = IIGSDebuggerSession(machine: IIGSMachine(romImage: try makeROM(resetVector: 0x8000)))
        session.loadBinary([0xA9, 0x42, 0x8D, 0x00, 0x20], at: 0x008000)
        let cycles = session.machine.memory.cycleCount

        let rows = session.disassemblyRows(startingAt: 0x008000, count: 2)

        XCTAssertEqual(rows.map(\.text), ["LDA #$42", "STA $2000"])
        XCTAssertEqual(session.machine.memory.cycleCount, cycles)
        XCTAssertEqual(try session.execute(.disassemble(0x008000, 2)), "$008000: $A9 $42        LDA #$42\n$008002: $8D $00 $20    STA $2000")
    }

    func testSessionCanWriteRegistersThroughDebuggerCommand() throws {
        let session = IIGSDebuggerSession(machine: IIGSMachine(romImage: try makeROM(resetVector: 0x8000)))
        _ = try session.execute(.reset(.cold))

        XCTAssertEqual(try session.execute(.writeRegister("addr", 0xE12000)), "ADDR <- $E12000")
        XCTAssertEqual(session.machine.currentProgramAddress, 0xE12000)
        XCTAssertEqual(try session.execute(.writeRegister("A", 0x1234)), "A <- $1234")
        XCTAssertEqual(session.machine.cpu.registers.accumulator, 0x1234)
    }

    func testSnapshotExposesInterruptsAndPendingEvents() {
        let machine = IIGSMachine()
        machine.memory.write8(IIGSInterruptState.c023ScanlineEnableMask, at: 0x00C023)
        machine.memory.setScanlineInterruptPending()
        machine.scheduler.schedule(kind: .disk, at: 123, payload: 7)

        let snapshot = IIGSDebuggerSession(machine: machine).snapshot()

        XCTAssertEqual(snapshot.interrupts.c023Status, 0xA2)
        XCTAssertTrue(snapshot.interrupts.scanlinePending)
        XCTAssertTrue(snapshot.interrupts.irqAsserted)
        XCTAssertTrue(snapshot.pendingEvents.contains { $0.kind == .disk && $0.payload == 7 })
    }

    func testParserRecognizesDisassemblyAndRegisterWriteCommands() throws {
        let parser = IIGSDebuggerCommandParser()

        XCTAssertEqual(try parser.parse("disasm 008000 4"), .disassemble(0x008000, 4))
        XCTAssertEqual(try parser.parse("setreg PC 8000"), .writeRegister("PC", 0x8000))
    }

    private func makeROM(resetVector: UInt16) throws -> IIGSROMImage {
        var bytes = Array(repeating: UInt8(0), count: IIGSROMVersion.rom01.expectedSize)
        bytes[bytes.count - 4] = UInt8(resetVector & 0x00FF)
        bytes[bytes.count - 3] = UInt8(resetVector >> 8)
        return try IIGSROMImage(bytes: bytes, version: .rom01)
    }
}
