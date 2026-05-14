import XCTest
@testable import IIGSCore

final class DebuggerPhase14Tests: XCTestCase {
    func testMemoryRowsExposeBankAddressBytesAndASCIIWithoutAdvancingCycles() {
        let session = IIGSDebuggerSession()
        session.loadBinary([0x41, 0x00, 0x7E, 0x80], at: 0x020010)
        let cycles = session.machine.memory.cycleCount

        let rows = session.memoryRows(bank: 0x02, startOffset: 0x0010, rowCount: 1)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].bank, 0x02)
        XCTAssertEqual(rows[0].offset, 0x0010)
        XCTAssertEqual(rows[0].address, 0x020010)
        XCTAssertEqual(Array(rows[0].bytes.prefix(4)), [0x41, 0x00, 0x7E, 0x80])
        XCTAssertEqual(String(rows[0].ascii.prefix(4)), "A.~.")
        XCTAssertEqual(session.machine.memory.cycleCount, cycles)
    }

    func testMemoryRowsCanReachFinalRowOfSelectedBank() {
        let session = IIGSDebuggerSession()

        let rows = session.memoryRows(bank: 0xFF, startOffset: 0xFFF0, rowCount: 1)

        XCTAssertEqual(rows.single?.address, 0xFFFFF0)
        XCTAssertEqual(rows.single?.bytes.count, 16)
    }

    func testSnapshotReportsRegistersFlagsStatusTimingAndMouse() {
        let machine = IIGSMachine()
        machine.cpu.updateRegisters { registers in
            registers.programBank = 0xE1
            registers.programCounter = 0x2000
            registers.accumulator = 0x1234
            registers.x = 0x0056
            registers.y = 0x0078
            registers.status = [.negative, .accumulator8Bit, .interruptDisable, .carry]
            registers.emulationMode = false
        }
        machine.cpu.signal(.irq)
        machine.cpu.signal(.nmi)
        machine.moveMouse(dx: 5, dy: -3, buttonDown: true)
        machine.memory.idle(cycles: 65)
        let session = IIGSDebuggerSession(machine: machine)

        let snapshot = session.snapshot()

        XCTAssertEqual(snapshot.registers.programAddress, 0xE12000)
        XCTAssertEqual(snapshot.registers.accumulator, 0x1234)
        XCTAssertTrue(snapshot.flags.negative)
        XCTAssertTrue(snapshot.flags.accumulator8Bit)
        XCTAssertTrue(snapshot.flags.interruptDisable)
        XCTAssertTrue(snapshot.flags.carry)
        XCTAssertFalse(snapshot.flags.index8Bit)
        XCTAssertTrue(snapshot.status.ready)
        XCTAssertTrue(snapshot.status.irqPending)
        XCTAssertTrue(snapshot.status.nmiPending)
        XCTAssertFalse(snapshot.status.emulationMode)
        XCTAssertEqual(snapshot.timing.cycles, 65)
        XCTAssertEqual(snapshot.timing.videoLine, 1)
        XCTAssertEqual(snapshot.mouse.romX, 5)
        XCTAssertEqual(snapshot.mouse.romY, -3)
        XCTAssertTrue(snapshot.mouse.buttonDown)
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? self[0] : nil
    }
}
