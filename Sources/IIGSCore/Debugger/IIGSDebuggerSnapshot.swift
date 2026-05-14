public struct IIGSDebuggerRegisterSnapshot: Equatable, Sendable {
    public let programAddress: UInt32
    public let programCounter: UInt16
    public let programBank: UInt8
    public let stackPointer: UInt16
    public let directPage: UInt16
    public let dataBank: UInt8
    public let accumulator: UInt16
    public let x: UInt16
    public let y: UInt16
    public let status: UInt8
    public let emulationMode: Bool

    public init(registers: CPURegisters) {
        self.programCounter = registers.programCounter
        self.programBank = registers.programBank
        self.programAddress = (UInt32(registers.programBank) << 16) | UInt32(registers.programCounter)
        self.stackPointer = registers.stackPointer
        self.directPage = registers.directPage
        self.dataBank = registers.dataBank
        self.accumulator = registers.accumulator
        self.x = registers.x
        self.y = registers.y
        self.status = registers.status.rawValue
        self.emulationMode = registers.emulationMode
    }
}

public struct IIGSDebuggerFlagSnapshot: Equatable, Sendable {
    public let negative: Bool
    public let overflow: Bool
    public let accumulator8Bit: Bool
    public let index8Bit: Bool
    public let decimal: Bool
    public let interruptDisable: Bool
    public let zero: Bool
    public let carry: Bool

    public init(status: ProcessorStatus) {
        self.negative = status.contains(.negative)
        self.overflow = status.contains(.overflow)
        self.accumulator8Bit = status.contains(.accumulator8Bit)
        self.index8Bit = status.contains(.indexRegister8Bit)
        self.decimal = status.contains(.decimal)
        self.interruptDisable = status.contains(.interruptDisable)
        self.zero = status.contains(.zero)
        self.carry = status.contains(.carry)
    }
}

public struct IIGSDebuggerStatusSnapshot: Equatable, Sendable {
    public let ready: Bool
    public let irqPending: Bool
    public let nmiPending: Bool
    public let abortPending: Bool
    public let stopped: Bool
    public let waiting: Bool
    public let emulationMode: Bool

    public init(cpu: CPU65816) {
        self.ready = !cpu.isStopped && !cpu.isWaiting
        self.irqPending = cpu.isIRQPending
        self.nmiPending = cpu.isNMIPending
        self.abortPending = cpu.isAbortPending
        self.stopped = cpu.isStopped
        self.waiting = cpu.isWaiting
        self.emulationMode = cpu.registers.emulationMode
    }
}

public struct IIGSDebuggerTimingSnapshot: Equatable, Sendable {
    public let cycles: UInt64
    public let videoLine: Int
    public let videoCycleInLine: Int
    public let videoFrameCycle: Int
    public let inVerticalBlank: Bool

    public init(cycles: UInt64) {
        self.cycles = cycles
        let position = IIGSVideoTiming.position(atCycle: cycles)
        self.videoLine = position.line
        self.videoCycleInLine = position.cycleInLine
        self.videoFrameCycle = position.frameCycle
        self.inVerticalBlank = position.inVerticalBlank
    }
}

public struct IIGSDebuggerMouseSnapshot: Equatable, Sendable {
    public let romX: Int16
    public let romY: Int16
    public let buttonDown: Bool

    public init(adbController: IIGSADBController) {
        self.romX = adbController.mouseX
        self.romY = adbController.mouseY
        self.buttonDown = adbController.mouseButtonDown
    }
}

public struct IIGSDebuggerSnapshot: Equatable, Sendable {
    public let registers: IIGSDebuggerRegisterSnapshot
    public let flags: IIGSDebuggerFlagSnapshot
    public let status: IIGSDebuggerStatusSnapshot
    public let timing: IIGSDebuggerTimingSnapshot
    public let mouse: IIGSDebuggerMouseSnapshot

    public init(machine: IIGSMachine) {
        self.registers = IIGSDebuggerRegisterSnapshot(registers: machine.cpu.registers)
        self.flags = IIGSDebuggerFlagSnapshot(status: machine.cpu.registers.status)
        self.status = IIGSDebuggerStatusSnapshot(cpu: machine.cpu)
        self.timing = IIGSDebuggerTimingSnapshot(cycles: machine.memory.cycleCount)
        self.mouse = IIGSDebuggerMouseSnapshot(adbController: machine.memory.adbController)
    }
}

public struct IIGSDebuggerMemoryRow: Equatable, Identifiable, Sendable {
    public static let bytesPerRow = 16

    public let bank: UInt8
    public let offset: UInt16
    public let address: UInt32
    public let bytes: [UInt8]
    public let ascii: String

    public var id: UInt32 { address }

    public init(bank: UInt8, offset: UInt16, bytes: [UInt8]) {
        self.bank = bank
        self.offset = offset & 0xFFF0
        self.address = (UInt32(bank) << 16) | UInt32(self.offset)
        self.bytes = Array(bytes.prefix(Self.bytesPerRow))
        self.ascii = Self.asciiString(for: self.bytes)
    }

    public static func asciiString(for bytes: [UInt8]) -> String {
        String(bytes.map { byte in
            (0x20...0x7E).contains(byte) ? Character(UnicodeScalar(byte)) : "."
        })
    }
}
