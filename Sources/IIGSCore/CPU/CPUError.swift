public enum CPUError: Error, Equatable, CustomStringConvertible {
    case unsupportedOpcode(UInt8, address: UInt32)

    public var description: String {
        switch self {
        case let .unsupportedOpcode(opcode, address):
            let opcodeText = String(opcode, radix: 16, uppercase: true)
            let addressText = String(address, radix: 16, uppercase: true)
            return "Unsupported opcode $\(opcodeText) at $\(addressText)"
        }
    }
}

