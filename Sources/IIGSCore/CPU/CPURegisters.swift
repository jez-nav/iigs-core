public struct CPURegisters: Equatable, Sendable {
    public var accumulator: UInt16
    public var x: UInt16
    public var y: UInt16
    public var stackPointer: UInt16
    public var directPage: UInt16
    public var dataBank: UInt8
    public var programBank: UInt8
    public var programCounter: UInt16
    public var status: ProcessorStatus
    public var emulationMode: Bool

    public init(
        accumulator: UInt16 = 0,
        x: UInt16 = 0,
        y: UInt16 = 0,
        stackPointer: UInt16 = 0x01FF,
        directPage: UInt16 = 0,
        dataBank: UInt8 = 0,
        programBank: UInt8 = 0,
        programCounter: UInt16 = 0,
        status: ProcessorStatus = .resetValue,
        emulationMode: Bool = true
    ) {
        self.accumulator = accumulator
        self.x = x
        self.y = y
        self.stackPointer = stackPointer
        self.directPage = directPage
        self.dataBank = dataBank
        self.programBank = programBank
        self.programCounter = programCounter
        self.status = status
        self.emulationMode = emulationMode
    }

    public var accumulatorIs8Bit: Bool {
        status.contains(.accumulator8Bit)
    }

    public var indexRegistersAre8Bit: Bool {
        status.contains(.indexRegister8Bit)
    }
}

