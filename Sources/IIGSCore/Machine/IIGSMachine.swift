public enum IIGSResetKind: Equatable, Sendable {
    case cold
    case warm
}

public enum IIGSMachineStopReason: Equatable, Sendable {
    case instructionLimitReached
    case cycleLimitReached
    case breakpoint(UInt32)
    case stopped
    case waiting
}

public struct IIGSMachineStepResult: Equatable, Sendable {
    public let address: UInt32
    public let cycles: Int
    public let registers: CPURegisters
}

public struct IIGSMachineRunResult: Equatable, Sendable {
    public let instructionsExecuted: Int
    public let cyclesElapsed: UInt64
    public let stopReason: IIGSMachineStopReason
    public let finalAddress: UInt32
}

public final class IIGSMachine {
    public let memory: FlatMemoryBus
    public let cpu: CPU65816
    public let smartPortController = IIGSSmartPortController()
    public private(set) var lastResetKind: IIGSResetKind?

    public init(memorySize: Int = FlatMemoryBus.fullAddressSpaceSize, romImage: IIGSROMImage? = nil) {
        self.memory = FlatMemoryBus(size: memorySize)
        self.cpu = CPU65816()
        if let romImage {
            memory.installROM(romImage)
        }
    }

    public func installROM(_ romImage: IIGSROMImage) {
        memory.installROM(romImage)
    }

    public func installROM(bytes: [UInt8]) throws {
        installROM(try IIGSROMImage(bytes: bytes))
    }

    public func reset(_ kind: IIGSResetKind = .cold) {
        lastResetKind = kind
        cpu.reset(using: memory)
    }

    public var currentProgramAddress: UInt32 {
        (UInt32(cpu.registers.programBank) << 16) | UInt32(cpu.registers.programCounter)
    }

    public func injectAppleIIKey(_ ascii: UInt8, modifiers: IIGSADBModifiers = []) {
        memory.adbController.injectAppleIIKey(ascii, modifiers: modifiers)
    }

    public func queueKeyboardEvent(keyCode: UInt8, isKeyUp: Bool = false) {
        memory.adbController.queueKeyboardEvent(keyCode: keyCode, isKeyUp: isKeyUp)
    }

    public func queueKeyboardKeyDownUp(keyCode: UInt8) {
        memory.adbController.queueKeyboardKeyDownUp(keyCode: keyCode)
    }

    public func moveMouse(dx: Int8, dy: Int8, buttonDown: Bool) {
        memory.adbController.moveMouse(dx: dx, dy: dy, buttonDown: buttonDown)
    }

    public func mountSmartPortDevice(_ device: IIGSBlockDevice, unit: UInt8 = 1) {
        smartPortController.mount(device, unit: unit)
    }

    public func mountFloppyMedia(_ media: IIGSFloppyMedia, drive: UInt8 = 1) {
        memory.iwmController.mount(media, drive: drive)
    }

    @discardableResult
    public func executeSmartPort(command: UInt8, parameterListAddress: UInt32) -> IIGSSmartPortResult {
        smartPortController.execute(command: command, parameterListAddress: parameterListAddress, memory: memory)
    }

    @discardableResult
    public func executeSmartPortFirmwareEntry(_ entryAddress: UInt16, command: UInt8, parameterListAddress: UInt32) -> IIGSSmartPortResult {
        smartPortController.executeFirmwareEntry(entryAddress, command: command, parameterListAddress: parameterListAddress, memory: memory)
    }

    @discardableResult
    public func step() throws -> Int {
        try cpu.step(using: memory)
    }

    @discardableResult
    public func stepInstruction() throws -> IIGSMachineStepResult {
        let address = currentProgramAddress
        let cycles = try step()
        return IIGSMachineStepResult(address: address, cycles: cycles, registers: cpu.registers)
    }

    public func run(instructionLimit: Int) throws {
        _ = try runUntilStop(instructionLimit: instructionLimit)
    }

    @discardableResult
    public func runUntilStop(instructionLimit: Int, breakpoints: Set<UInt32> = []) throws -> IIGSMachineRunResult {
        precondition(instructionLimit >= 0)
        let startingCycles = memory.cycleCount
        var executed = 0

        while executed < instructionLimit {
            let address = currentProgramAddress
            if breakpoints.contains(address) {
                return runResult(
                    instructionsExecuted: executed,
                    startingCycles: startingCycles,
                    stopReason: .breakpoint(address)
                )
            }

            _ = try step()
            executed += 1

            if cpu.isStopped {
                return runResult(
                    instructionsExecuted: executed,
                    startingCycles: startingCycles,
                    stopReason: .stopped
                )
            }

            if cpu.isWaiting {
                return runResult(
                    instructionsExecuted: executed,
                    startingCycles: startingCycles,
                    stopReason: .waiting
                )
            }
        }

        return runResult(
            instructionsExecuted: executed,
            startingCycles: startingCycles,
            stopReason: .instructionLimitReached
        )
    }

    @discardableResult
    public func runForCycles(_ cycleLimit: Int, instructionLimit: Int = Int.max) throws -> IIGSMachineRunResult {
        precondition(cycleLimit >= 0)
        precondition(instructionLimit >= 0)
        let startingCycles = memory.cycleCount
        var executed = 0

        while memory.cycleCount - startingCycles < UInt64(cycleLimit), executed < instructionLimit {
            _ = try step()
            executed += 1

            if cpu.isStopped {
                return runResult(
                    instructionsExecuted: executed,
                    startingCycles: startingCycles,
                    stopReason: .stopped
                )
            }

            if cpu.isWaiting {
                return runResult(
                    instructionsExecuted: executed,
                    startingCycles: startingCycles,
                    stopReason: .waiting
                )
            }
        }

        let reason: IIGSMachineStopReason = executed == instructionLimit ? .instructionLimitReached : .cycleLimitReached
        return runResult(instructionsExecuted: executed, startingCycles: startingCycles, stopReason: reason)
    }

    @discardableResult
    public func runUntilBreakpoint(_ breakpoint: UInt32, instructionLimit: Int) throws -> IIGSMachineRunResult {
        try runUntilStop(instructionLimit: instructionLimit, breakpoints: [masked24(breakpoint)])
    }

    private func runResult(
        instructionsExecuted: Int,
        startingCycles: UInt64,
        stopReason: IIGSMachineStopReason
    ) -> IIGSMachineRunResult {
        IIGSMachineRunResult(
            instructionsExecuted: instructionsExecuted,
            cyclesElapsed: memory.cycleCount - startingCycles,
            stopReason: stopReason,
            finalAddress: currentProgramAddress
        )
    }
}
