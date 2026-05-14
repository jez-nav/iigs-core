public struct ProcessorStatus: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let carry = ProcessorStatus(rawValue: 0x01)
    public static let zero = ProcessorStatus(rawValue: 0x02)
    public static let interruptDisable = ProcessorStatus(rawValue: 0x04)
    public static let decimal = ProcessorStatus(rawValue: 0x08)
    public static let indexRegister8Bit = ProcessorStatus(rawValue: 0x10)
    public static let accumulator8Bit = ProcessorStatus(rawValue: 0x20)
    public static let overflow = ProcessorStatus(rawValue: 0x40)
    public static let negative = ProcessorStatus(rawValue: 0x80)

    public static let resetValue: ProcessorStatus = [
        .interruptDisable,
        .indexRegister8Bit,
        .accumulator8Bit,
    ]
}

