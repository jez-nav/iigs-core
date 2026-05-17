import XCTest
@testable import IIGSCore

final class CPUPhase1Tests: XCTestCase {
    func testResetLoadsVectorAndForcesEmulationState() {
        let machine = machineWithProgram([], start: 0x3456)

        machine.reset()

        let registers = machine.cpu.registers
        XCTAssertTrue(registers.emulationMode)
        XCTAssertTrue(registers.status.contains(.accumulator8Bit))
        XCTAssertTrue(registers.status.contains(.indexRegister8Bit))
        XCTAssertTrue(registers.status.contains(.interruptDisable))
        XCTAssertEqual(registers.directPage, 0)
        XCTAssertEqual(registers.dataBank, 0)
        XCTAssertEqual(registers.programBank, 0)
        XCTAssertEqual(registers.stackPointer, 0x01FF)
        XCTAssertEqual(registers.programCounter, 0x3456)
    }

    func testXCELeavesEmulationModeWhenCarryIsClear() throws {
        let machine = machineWithProgram([
            0x18,       // CLC
            0xFB,       // XCE
        ])
        machine.reset()

        try machine.run(instructionLimit: 2)

        let registers = machine.cpu.registers
        XCTAssertFalse(registers.emulationMode)
        XCTAssertTrue(registers.status.contains(.carry))
        XCTAssertEqual(registers.programCounter, 0x0202)
    }

    func testREPSEPControlRegisterWidthsAndIndexTruncation() throws {
        let machine = machineWithProgram([
            0x18,             // CLC
            0xFB,             // XCE
            0xC2, 0x30,       // REP #$30
            0xA9, 0x34, 0x12, // LDA #$1234
            0xA2, 0x78, 0x56, // LDX #$5678
            0xA0, 0xBC, 0x9A, // LDY #$9ABC
            0xE2, 0x10,       // SEP #$10
        ])
        machine.reset()

        try machine.run(instructionLimit: 7)

        let registers = machine.cpu.registers
        XCTAssertFalse(registers.emulationMode)
        XCTAssertEqual(registers.accumulator, 0x1234)
        XCTAssertEqual(registers.x, 0x0078)
        XCTAssertEqual(registers.y, 0x00BC)
        XCTAssertFalse(registers.status.contains(.accumulator8Bit))
        XCTAssertTrue(registers.status.contains(.indexRegister8Bit))
    }

    func testXBASwapsAccumulatorBytesWithoutOverflowing() throws {
        let machine = machineWithProgram([
            0x18,             // CLC
            0xFB,             // XCE
            0xC2, 0x20,       // REP #$20
            0xA9, 0x03, 0xBB, // LDA #$BB03
            0xEB              // XBA
        ])
        machine.reset()

        try machine.run(instructionLimit: 5)

        XCTAssertEqual(machine.cpu.registers.accumulator, 0x03BB)
        XCTAssertTrue(machine.cpu.registers.status.contains(.negative))
    }

    func testImmediateLoadsStoresAndTransfers() throws {
        let machine = machineWithProgram([
            0xA9, 0x42,       // LDA #$42
            0x8D, 0x00, 0x20, // STA $2000
            0xAA,             // TAX
            0xE8,             // INX
            0x8E, 0x01, 0x20, // STX $2001
            0xA8,             // TAY
            0xC8,             // INY
            0x8C, 0x02, 0x20, // STY $2002
        ])
        machine.reset()

        try machine.run(instructionLimit: 8)

        XCTAssertEqual(machine.memory[0x002000], 0x42)
        XCTAssertEqual(machine.memory[0x002001], 0x43)
        XCTAssertEqual(machine.memory[0x002002], 0x43)
        XCTAssertEqual(machine.cpu.registers.x, 0x43)
        XCTAssertEqual(machine.cpu.registers.y, 0x43)
    }

    func testDirectPageAddressingUsesDirectRegisterAndReportsAlignmentCycle() throws {
        let machine = machineWithProgram([
            0xA5, 0x10, // LDA $10
        ])
        machine.memory[0x001211] = 0x7F
        machine.reset()
        machine.cpu.updateRegisters { registers in
            registers.directPage = 0x1201
        }

        let cycles = try machine.step()

        XCTAssertEqual(machine.cpu.registers.accumulator & 0x00FF, 0x7F)
        XCTAssertEqual(cycles, 4)
    }

    func testJSRAndRTSUseEmulationStack() throws {
        let machine = machineWithProgram([
            0x20, 0x06, 0x02, // JSR $0206
            0xA9, 0x55,       // LDA #$55
            0xEA,             // NOP
            0xA9, 0xAA,       // LDA #$AA
            0x60,             // RTS
        ])
        machine.reset()

        try machine.run(instructionLimit: 4)

        XCTAssertEqual(machine.cpu.registers.accumulator & 0x00FF, 0x55)
        XCTAssertEqual(machine.cpu.registers.stackPointer, 0x01FF)
        XCTAssertEqual(machine.cpu.registers.programCounter, 0x0205)
    }

    func testPHAAndPLARoundTripThroughStack() throws {
        let machine = machineWithProgram([
            0xA9, 0xA5, // LDA #$A5
            0x48,       // PHA
            0xA9, 0x00, // LDA #$00
            0x68,       // PLA
        ])
        machine.reset()

        try machine.run(instructionLimit: 4)

        XCTAssertEqual(machine.cpu.registers.accumulator & 0x00FF, 0xA5)
        XCTAssertTrue(machine.cpu.registers.status.contains(.negative))
        XCTAssertFalse(machine.cpu.registers.status.contains(.zero))
        XCTAssertEqual(machine.cpu.registers.stackPointer, 0x01FF)
    }

    func testBRKUsesEmulationVectorAndStacksReturnAfterSignature() throws {
        let machine = machineWithProgram([
            0x00, 0x12, // BRK #$12
        ])
        machine.memory[0x00FFFE] = 0x00
        machine.memory[0x00FFFF] = 0x90
        machine.reset()

        let cycles = try machine.step()

        XCTAssertEqual(cycles, 7)
        XCTAssertEqual(machine.cpu.registers.programCounter, 0x9000)
        XCTAssertEqual(machine.cpu.registers.stackPointer, 0x01FC)
        XCTAssertEqual(machine.memory[0x0001FF], 0x02)
        XCTAssertEqual(machine.memory[0x0001FE], 0x02)
        XCTAssertEqual(machine.memory[0x0001FD] & 0x10, 0x10)
        XCTAssertTrue(machine.cpu.registers.status.contains(.interruptDisable))
    }

    func testPhase2COPUsesEmulationVector() throws {
        let machine = machineWithProgram([
            0x02, 0x34, // COP #$34
        ])
        machine.memory[0x00FFF4] = 0x00
        machine.memory[0x00FFF5] = 0x80
        machine.reset()

        try machine.step()

        XCTAssertEqual(machine.cpu.registers.programCounter, 0x8000)
        XCTAssertEqual(machine.cpu.registers.stackPointer, 0x01FC)
        XCTAssertEqual(machine.memory[0x0001FF], 0x02)
        XCTAssertEqual(machine.memory[0x0001FE], 0x02)
        XCTAssertTrue(machine.cpu.registers.status.contains(.interruptDisable))
    }

    func testPhase2BinaryAndDecimalADC() throws {
        let machine = machineWithProgram([
            0x18,             // CLC
            0xFB,             // XCE
            0xC2, 0x20,       // REP #$20
            0xA9, 0x34, 0x12, // LDA #$1234
            0x18,             // CLC
            0x69, 0x11, 0x11, // ADC #$1111
            0xE2, 0x20,       // SEP #$20
            0xF8,             // SED
            0xA9, 0x45,       // LDA #$45
            0x18,             // CLC
            0x69, 0x55,       // ADC #$55
        ])
        machine.reset()

        try machine.run(instructionLimit: 11)

        XCTAssertEqual(machine.cpu.registers.accumulator, 0x2300)
        XCTAssertTrue(machine.cpu.registers.status.contains(.carry))
        XCTAssertTrue(machine.cpu.registers.status.contains(.zero))
    }

    func testPhase2ADCWrapsCarryWithoutDebugOverflow() throws {
        let machine = machineWithProgram([
            0x18,             // CLC
            0xFB,             // XCE
            0xC2, 0x20,       // REP #$20
            0xA9, 0xFF, 0xFF, // LDA #$FFFF
            0x18,             // CLC
            0x69, 0x01, 0x00, // ADC #$0001
        ])
        machine.reset()

        try machine.run(instructionLimit: 6)

        XCTAssertEqual(machine.cpu.registers.accumulator, 0x0000)
        XCTAssertTrue(machine.cpu.registers.status.contains(.carry))
        XCTAssertTrue(machine.cpu.registers.status.contains(.zero))
    }

    func testPhase2SBCWrapsBorrowWithoutDebugOverflow() throws {
        let machine = machineWithProgram([
            0x18,             // CLC
            0xFB,             // XCE
            0xC2, 0x20,       // REP #$20
            0xA9, 0x00, 0x00, // LDA #$0000
            0x18,             // CLC: borrow one extra
            0xE9, 0x01, 0x00, // SBC #$0001
        ])
        machine.reset()

        try machine.run(instructionLimit: 6)

        XCTAssertEqual(machine.cpu.registers.accumulator, 0xFFFE)
        XCTAssertFalse(machine.cpu.registers.status.contains(.carry))
        XCTAssertTrue(machine.cpu.registers.status.contains(.negative))
    }

    func testPhase2DecimalSBC() throws {
        let machine = machineWithProgram([
            0xF8,       // SED
            0x38,       // SEC
            0xA9, 0x50, // LDA #$50
            0xE9, 0x01, // SBC #$01
        ])
        machine.reset()

        try machine.run(instructionLimit: 4)

        XCTAssertEqual(machine.cpu.registers.accumulator & 0x00FF, 0x49)
        XCTAssertTrue(machine.cpu.registers.status.contains(.carry))
    }

    func testPhase2DataBankAndAbsoluteLongLoads() throws {
        let machine = machineWithProgram([
            0x18,             // CLC
            0xFB,             // XCE
            0xC2, 0x20,       // REP #$20
            0xAD, 0x56, 0x34, // LDA $3456 through DBR
            0xAF, 0x00, 0x40, 0x03, // LDA $03/4000
        ])
        machine.memory[0x023456] = 0xCD
        machine.memory[0x023457] = 0xAB
        machine.memory[0x034000] = 0x34
        machine.memory[0x034001] = 0x12
        machine.reset()
        machine.cpu.updateRegisters { registers in
            registers.dataBank = 0x02
        }

        try machine.run(instructionLimit: 5)

        XCTAssertEqual(machine.cpu.registers.accumulator, 0x1234)
    }

    func testPhase2JSLAndRTLRestoreProgramBankAndReturnAddress() throws {
        let machine = machineWithProgram([
            0x18,                   // CLC
            0xFB,                   // XCE
            0x22, 0x00, 0x03, 0x01, // JSL $01/0300
            0xA9, 0x55,             // LDA #$55
        ])
        machine.memory.load([
            0xA9, 0xAA, // LDA #$AA
            0x6B,       // RTL
        ], at: 0x010300)
        machine.reset()

        try machine.run(instructionLimit: 6)

        XCTAssertEqual(machine.cpu.registers.programBank, 0)
        XCTAssertEqual(machine.cpu.registers.programCounter, 0x0208)
        XCTAssertEqual(machine.cpu.registers.stackPointer, 0x01FF)
        XCTAssertEqual(machine.cpu.registers.accumulator & 0x00FF, 0x55)
    }

    func testPhase2JSRAbsoluteIndexedIndirectReadsPointerFromProgramBank() throws {
        let machine = IIGSMachine()
        machine.memory.load([
            0xA2, 0x02,       // LDX #$02
            0xFC, 0x00, 0x04, // JSR ($0400,X)
            0xA9, 0x55,       // LDA #$55
        ], at: 0x010200)
        machine.memory[0x010402] = 0x00
        machine.memory[0x010403] = 0x06
        machine.memory.load([
            0xA9, 0xAA, // LDA #$AA
            0x60,       // RTS
        ], at: 0x010600)
        machine.reset()
        machine.cpu.updateRegisters {
            $0.programBank = 0x01
            $0.programCounter = 0x0200
        }

        try machine.run(instructionLimit: 5)

        XCTAssertEqual(machine.cpu.registers.programBank, 0x01)
        XCTAssertEqual(machine.cpu.registers.programCounter, 0x0207)
        XCTAssertEqual(machine.cpu.registers.accumulator & 0x00FF, 0x55)
    }

    func testPhase2JMPAbsoluteIndexedIndirectReadsPointerFromProgramBank() throws {
        let machine = IIGSMachine()
        machine.memory.load([
            0xA2, 0x02,       // LDX #$02
            0x7C, 0x00, 0x04, // JMP ($0400,X)
            0xA9, 0x11,       // LDA #$11; skipped when the vector is read from bank 1
        ], at: 0x010200)
        machine.memory[0x010402] = 0x00
        machine.memory[0x010403] = 0x06
        machine.memory.load([
            0xA9, 0x42, // LDA #$42
        ], at: 0x010600)
        machine.reset()
        machine.cpu.updateRegisters {
            $0.programBank = 0x01
            $0.programCounter = 0x0200
        }

        try machine.run(instructionLimit: 3)

        XCTAssertEqual(machine.cpu.registers.programBank, 0x01)
        XCTAssertEqual(machine.cpu.registers.programCounter, 0x0602)
        XCTAssertEqual(machine.cpu.registers.accumulator & 0x00FF, 0x42)
    }

    func testPhase2NativeIRQStacksFullFrameAndRTIRestoresIt() throws {
        let machine = machineWithProgram([
            0x18, // CLC
            0xFB, // XCE
            0x58, // CLI
            0xEA, // NOP
        ])
        machine.memory[0x00FFEE] = 0x00
        machine.memory[0x00FFEF] = 0x90
        machine.memory[0x009000] = 0x40 // RTI
        machine.reset()

        try machine.run(instructionLimit: 3)
        machine.cpu.signal(.irq)
        try machine.step()

        XCTAssertEqual(machine.cpu.registers.programCounter, 0x9000)
        XCTAssertEqual(machine.cpu.registers.programBank, 0)
        XCTAssertEqual(machine.cpu.registers.stackPointer, 0x01FB)
        XCTAssertEqual(machine.memory[0x0001FF], 0x00)
        XCTAssertEqual(machine.memory[0x0001FE], 0x02)
        XCTAssertEqual(machine.memory[0x0001FD], 0x03)
        XCTAssertTrue(machine.cpu.registers.status.contains(.interruptDisable))

        try machine.step()

        XCTAssertEqual(machine.cpu.registers.programCounter, 0x0203)
        XCTAssertEqual(machine.cpu.registers.stackPointer, 0x01FF)
        XCTAssertFalse(machine.cpu.registers.status.contains(.interruptDisable))
    }

    func testPhase2WAIIdlesUntilInterrupt() throws {
        let machine = machineWithProgram([
            0x18, // CLC
            0xFB, // XCE
            0x58, // CLI
            0xCB, // WAI
            0xEA, // NOP
        ])
        machine.memory[0x00FFEE] = 0x00
        machine.memory[0x00FFEF] = 0x90
        machine.reset()

        try machine.run(instructionLimit: 4)
        XCTAssertTrue(machine.cpu.isWaiting)
        XCTAssertEqual(machine.cpu.registers.programCounter, 0x0204)

        try machine.step()
        XCTAssertTrue(machine.cpu.isWaiting)
        XCTAssertEqual(machine.cpu.registers.programCounter, 0x0204)

        machine.cpu.signal(.irq)
        try machine.step()

        XCTAssertFalse(machine.cpu.isWaiting)
        XCTAssertEqual(machine.cpu.registers.programCounter, 0x9000)
    }

    func testPhase2MVNCopiesOneByteAndRepeatsUntilAccumulatorUnderflows() throws {
        let machine = machineWithProgram([
            0x18,             // CLC
            0xFB,             // XCE
            0xC2, 0x30,       // REP #$30
            0xA2, 0x00, 0x10, // LDX #$1000
            0xA0, 0x00, 0x20, // LDY #$2000
            0xA9, 0x00, 0x00, // LDA #$0000
            0x54, 0x03, 0x02, // MVN destination bank $03, source bank $02
        ])
        machine.memory[0x021000] = 0x7E
        machine.reset()

        try machine.run(instructionLimit: 7)

        XCTAssertEqual(machine.memory[0x032000], 0x7E)
        XCTAssertEqual(machine.cpu.registers.accumulator, 0xFFFF)
        XCTAssertEqual(machine.cpu.registers.x, 0x1001)
        XCTAssertEqual(machine.cpu.registers.y, 0x2001)
        XCTAssertEqual(machine.cpu.registers.dataBank, 0x03)
    }
}

private func machineWithProgram(_ program: [UInt8], start: UInt16 = 0x0200) -> IIGSMachine {
    let machine = IIGSMachine()
    machine.memory[0x00FFFC] = UInt8(truncatingIfNeeded: start)
    machine.memory[0x00FFFD] = UInt8(truncatingIfNeeded: start >> 8)
    machine.memory.load(program, at: UInt32(start))
    return machine
}
