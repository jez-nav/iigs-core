import XCTest
@testable import IIGSCore

final class TimingPhase15Tests: XCTestCase {
    func testSchedulerFiresSameCycleEventsInDeterministicPriorityThenInsertionOrder() {
        let scheduler = IIGSEventScheduler()
        let firstCustom = scheduler.schedule(kind: .custom, at: 10, payload: 1)
        scheduler.schedule(kind: .docOscillator, at: 10, payload: 2)
        let secondCustom = scheduler.schedule(kind: .custom, at: 10, payload: 3)
        scheduler.schedule(kind: .videoFrame, at: 10, payload: 4)

        scheduler.advance(to: 10)
        let fired = scheduler.drainFiredEvents()

        XCTAssertEqual(fired.map(\.kind), [.videoFrame, .docOscillator, .custom, .custom])
        XCTAssertEqual(fired.map(\.payload), [4, 2, 1, 3])
        XCTAssertEqual(fired[2].id, firstCustom)
        XCTAssertEqual(fired[3].id, secondCustom)
    }

    func testMachineSchedulesVideoCadenceFromMasterCycleCounter() {
        let machine = IIGSMachine()

        machine.advanceCycles(IIGSVideoTiming.cyclesPerLine)

        XCTAssertEqual(machine.scheduler.currentCycle, UInt64(IIGSVideoTiming.cyclesPerLine))
        XCTAssertEqual(IIGSVideoTiming.position(atCycle: machine.scheduler.currentCycle).line, 1)

        let pendingKinds = machine.scheduler.pendingEvents().map(\.kind)
        XCTAssertTrue(pendingKinds.contains(.videoScanline))
        XCTAssertTrue(pendingKinds.contains(.verticalBlankStart))
        XCTAssertTrue(pendingKinds.contains(.videoFrame))
    }

    func testVBLInterruptStatusAndClearUseSchedulerTime() {
        let machine = IIGSMachine()
        machine.memory[0x00C041] = IIGSInterruptState.verticalBlankMask
        let vblStart = IIGSVideoTiming.classicVisibleLines * IIGSVideoTiming.cyclesPerLine
        machine.advanceCycles(vblStart - Int(machine.memory.cycleCount))

        XCTAssertEqual(machine.memory[0x00C046] & IIGSInterruptState.verticalBlankMask, IIGSInterruptState.verticalBlankMask)
        XCTAssertTrue(machine.memory.irqLineAsserted)

        machine.memory[0x00C047] = IIGSInterruptState.verticalBlankMask

        XCTAssertEqual(machine.memory[0x00C046] & IIGSInterruptState.verticalBlankMask, 0)
        XCTAssertFalse(machine.memory.irqLineAsserted)
    }

    func testSchedulerAssertedIRQIsTakenAtNextInstructionBoundaryAfterCLI() throws {
        let machine = IIGSMachine()
        machine.memory[0x008000] = 0x58 // CLI
        machine.memory[0x008001] = 0xEA // NOP, should not execute before pending IRQ.
        machine.memory[0x00FFFC] = 0x00
        machine.memory[0x00FFFD] = 0x80
        machine.memory[0x00FFFE] = 0x00
        machine.memory[0x00FFFF] = 0x90
        machine.reset(.cold)
        machine.memory[0x00C041] = IIGSInterruptState.verticalBlankMask

        try machine.step()
        XCTAssertFalse(machine.cpu.registers.status.contains(.interruptDisable))
        XCTAssertEqual(machine.currentProgramAddress, 0x008001)

        let vblStart = IIGSVideoTiming.classicVisibleLines * IIGSVideoTiming.cyclesPerLine
        machine.advanceCycles(vblStart - Int(machine.memory.cycleCount))
        XCTAssertTrue(machine.memory.irqLineAsserted)

        try machine.step()

        XCTAssertEqual(machine.currentProgramAddress, 0x009000)
        XCTAssertTrue(machine.cpu.registers.status.contains(.interruptDisable))
    }

    func testSpeedSwitchPreservesMonotonicSchedulerTime() {
        let machine = IIGSMachine()
        machine.advanceCycles(40)
        let before = machine.scheduler.currentCycle

        machine.memory[0x00C036] = 0x80
        let afterFastSwitch = machine.scheduler.currentCycle
        machine.memory[0x00C036] = 0x00

        XCTAssertEqual(machine.cpuSpeedMode, .slow)
        XCTAssertGreaterThan(afterFastSwitch, before)
        XCTAssertGreaterThan(machine.scheduler.currentCycle, afterFastSwitch)
        XCTAssertEqual(IIGSVideoTiming.position(atCycle: machine.scheduler.currentCycle).frameCycle, Int(machine.scheduler.currentCycle % UInt64(IIGSVideoTiming.cyclesPerFrame)))
    }

    func testPaddleAndDOCEventsAreDrivenBySchedulerTime() {
        let machine = IIGSMachine()

        machine.scheduleDOCEvent(oscillator: 2, afterCycles: 12)
        machine.schedulePaddleTimeout(paddle: 1, afterCycles: 12)
        machine.advanceCycles(11)

        XCTAssertTrue(machine.drainServicedDeviceEvents().isEmpty)

        machine.advanceCycles(1)
        let events = machine.drainServicedDeviceEvents()

        XCTAssertEqual(events.map(\.kind), [.paddleTimeout, .docOscillator])
        XCTAssertEqual(events.map(\.payload), [1, 2])
        XCTAssertEqual(Set(events.map(\.cycle)), [12])
    }
}
