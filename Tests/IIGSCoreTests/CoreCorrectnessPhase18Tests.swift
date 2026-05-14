import XCTest
@testable import IIGSCore

final class CoreCorrectnessPhase18Tests: XCTestCase {
    func testC023ScanlineInterruptAssertsAndClearsThroughC032() {
        let machine = IIGSMachine()

        machine.memory[0x00C023] = IIGSInterruptState.c023ScanlineEnableMask
        machine.advanceCycles(IIGSVideoTiming.cyclesPerLine)

        XCTAssertEqual(machine.memory[0x00C023] & IIGSInterruptState.c023AnyPendingMask, IIGSInterruptState.c023AnyPendingMask)
        XCTAssertEqual(machine.memory[0x00C023] & IIGSInterruptState.c023ScanlinePendingMask, IIGSInterruptState.c023ScanlinePendingMask)
        XCTAssertTrue(machine.memory.irqLineAsserted)

        machine.memory[0x00C032] = IIGSInterruptState.c023ScanlinePendingMask

        XCTAssertEqual(machine.memory[0x00C023] & IIGSInterruptState.c023AnyPendingMask, 0)
        XCTAssertEqual(machine.memory[0x00C023] & IIGSInterruptState.c023ScanlinePendingMask, 0)
        XCTAssertFalse(machine.memory.irqLineAsserted)
    }

    func testClockTickSetsC023OneSecondInterrupt() {
        let machine = IIGSMachine()

        machine.memory[0x00C023] = IIGSInterruptState.c023OneSecondEnableMask
        machine.advanceCycles(IIGSVideoTiming.cyclesPerFrame * 60)

        XCTAssertEqual(machine.memory[0x00C023] & IIGSInterruptState.c023AnyPendingMask, IIGSInterruptState.c023AnyPendingMask)
        XCTAssertEqual(machine.memory[0x00C023] & IIGSInterruptState.c023OneSecondPendingMask, IIGSInterruptState.c023OneSecondPendingMask)
        XCTAssertTrue(machine.memory.irqLineAsserted)
        XCTAssertTrue(machine.drainServicedDeviceEvents().contains { $0.kind == .clockTick })

        machine.memory[0x00C032] = 0

        XCTAssertEqual(machine.memory[0x00C023] & IIGSInterruptState.c023AnyPendingMask, 0)
        XCTAssertFalse(machine.memory.irqLineAsserted)
    }

    func testPaddleTriggerAndTimeoutAreCycleDriven() {
        let memory = FlatMemoryBus(size: 0x020000)
        memory.setPaddlePosition(3, paddle: 0)

        memory[0x00C070] = 0

        XCTAssertEqual(memory[0x00C064] & 0x80, 0x80)

        memory.idle(cycles: 3)

        XCTAssertEqual(memory[0x00C064] & 0x80, 0x00)
    }
}
