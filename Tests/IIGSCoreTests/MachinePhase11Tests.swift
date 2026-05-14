import XCTest
@testable import IIGSCore

final class MachinePhase11Tests: XCTestCase {
    func testColdResetLoadsROM01VectorAndRecordsResetKind() throws {
        let machine = IIGSMachine(romImage: try makeROM(.rom01, resetVector: 0x8000))

        machine.reset(.cold)

        XCTAssertEqual(machine.lastResetKind, .cold)
        XCTAssertEqual(machine.currentProgramAddress, 0x008000)
        XCTAssertEqual(machine.cpu.registers.programCounter, 0x8000)
        XCTAssertEqual(machine.cpu.registers.programBank, 0)
    }

    func testWarmResetLoadsROM03VectorAndPreservesMemory() throws {
        let machine = IIGSMachine(romImage: try makeROM(.rom03, resetVector: 0x9000))
        machine.memory[0x002000] = 0x5A

        machine.reset(.warm)

        XCTAssertEqual(machine.lastResetKind, .warm)
        XCTAssertEqual(machine.currentProgramAddress, 0x009000)
        XCTAssertEqual(machine.memory[0x002000], 0x5A)
    }

    func testInstallROMFromBytesSupportsROMLoadAPI() throws {
        var bytes = Array(repeating: UInt8(0), count: IIGSROMVersion.rom01.expectedSize)
        bytes[bytes.count - 4] = 0x34
        bytes[bytes.count - 3] = 0x12
        let machine = IIGSMachine()

        try machine.installROM(bytes: bytes)
        machine.reset()

        XCTAssertEqual(machine.memory.romImage?.version, .rom01)
        XCTAssertEqual(machine.cpu.registers.programCounter, 0x1234)
    }

    func testRunUntilStopReportsWaitingState() throws {
        let machine = IIGSMachine(romImage: try makeROM(.rom01, resetVector: 0x8000))
        machine.memory.load([0xEA, 0xEA, 0xCB], at: 0x008000)
        machine.reset()

        let result = try machine.runUntilStop(instructionLimit: 10)

        XCTAssertEqual(result.instructionsExecuted, 3)
        XCTAssertEqual(result.stopReason, .waiting)
        XCTAssertEqual(result.finalAddress, 0x008003)
        XCTAssertTrue(machine.cpu.isWaiting)
    }

    func testRunUntilBreakpointStopsBeforeExecutingBreakpointInstruction() throws {
        let machine = IIGSMachine(romImage: try makeROM(.rom01, resetVector: 0x8000))
        machine.memory.load([0xEA, 0xEA, 0xCB], at: 0x008000)
        machine.reset()

        let result = try machine.runUntilBreakpoint(0x008001, instructionLimit: 10)

        XCTAssertEqual(result.instructionsExecuted, 1)
        XCTAssertEqual(result.stopReason, .breakpoint(0x008001))
        XCTAssertEqual(result.finalAddress, 0x008001)
        XCTAssertFalse(machine.cpu.isWaiting)
    }

    func testRunForCyclesStopsAfterCycleBudget() throws {
        let machine = IIGSMachine(romImage: try makeROM(.rom01, resetVector: 0x8000))
        machine.memory.load([0xEA, 0xEA, 0xEA], at: 0x008000)
        machine.reset()

        let result = try machine.runForCycles(2, instructionLimit: 10)

        XCTAssertEqual(result.instructionsExecuted, 2)
        XCTAssertEqual(result.stopReason, .cycleLimitReached)
        XCTAssertEqual(result.finalAddress, 0x008002)
        XCTAssertEqual(result.cyclesElapsed, 2)
    }

    func testStepInstructionReportsExecutedAddressCyclesAndRegisters() throws {
        let machine = IIGSMachine(romImage: try makeROM(.rom01, resetVector: 0x8000))
        machine.memory.load([0xA9, 0x7F], at: 0x008000)
        machine.reset()

        let result = try machine.stepInstruction()

        XCTAssertEqual(result.address, 0x008000)
        XCTAssertEqual(result.cycles, 2)
        XCTAssertEqual(result.registers.accumulator, 0x007F)
        XCTAssertEqual(machine.currentProgramAddress, 0x008002)
    }

    func testNoMediaBootPathCanExecuteUntilBreakpointWithoutMountedStorage() throws {
        let machine = IIGSMachine(romImage: try makeROM(.rom01, resetVector: 0x8000))
        machine.memory.load([0xEA, 0xEA, 0xEA], at: 0x008000)
        machine.reset()

        let result = try machine.runUntilStop(instructionLimit: 2)

        XCTAssertEqual(machine.smartPortController.units.keys.sorted(), [])
        XCTAssertNil(machine.memory.iwmController.drive1.media)
        XCTAssertEqual(result.stopReason, .instructionLimitReached)
        XCTAssertEqual(result.finalAddress, 0x008002)
    }

    func testSlotStorageMountAPIsRemainAvailableForBootSelectionHarnesses() throws {
        let machine = IIGSMachine(romImage: try makeROM(.rom01, resetVector: 0x8000))
        let blockDevice = try IIGSBlockDevice(bytes: Array(repeating: 0, count: 800 * 1024))
        let floppy = try IIGSFloppyMedia(raw5_25: Array(repeating: 0, count: 143_360))

        machine.mountSmartPortDevice(blockDevice, unit: 1)
        machine.mountFloppyMedia(floppy, drive: 1)

        XCTAssertEqual(machine.smartPortController.units.keys.sorted(), [1])
        XCTAssertNotNil(machine.memory.iwmController.drive1.media)
    }

    private func makeROM(_ version: IIGSROMVersion, resetVector: UInt16) throws -> IIGSROMImage {
        var bytes = Array(repeating: UInt8(0), count: version.expectedSize)
        bytes[bytes.count - 4] = UInt8(resetVector & 0x00FF)
        bytes[bytes.count - 3] = UInt8(resetVector >> 8)
        return try IIGSROMImage(bytes: bytes, version: version)
    }
}
