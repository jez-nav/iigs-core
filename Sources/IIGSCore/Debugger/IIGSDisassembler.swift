public struct IIGSDisassemblyOptions: Equatable, Sendable {
    public var accumulatorIs8Bit: Bool
    public var indexRegistersAre8Bit: Bool

    public init(accumulatorIs8Bit: Bool, indexRegistersAre8Bit: Bool) {
        self.accumulatorIs8Bit = accumulatorIs8Bit
        self.indexRegistersAre8Bit = indexRegistersAre8Bit
    }

    public init(registers: CPURegisters) {
        self.accumulatorIs8Bit = registers.accumulatorIs8Bit
        self.indexRegistersAre8Bit = registers.indexRegistersAre8Bit
    }
}

public struct IIGSDisassembledInstruction: Equatable, Identifiable, Sendable {
    public let address: UInt32
    public let bytes: [UInt8]
    public let mnemonic: String
    public let operand: String

    public var id: UInt32 { address }
    public var length: Int { bytes.count }
    public var text: String { operand.isEmpty ? mnemonic : "\(mnemonic) \(operand)" }

    public init(address: UInt32, bytes: [UInt8], mnemonic: String, operand: String = "") {
        self.address = masked24(address)
        self.bytes = bytes
        self.mnemonic = mnemonic
        self.operand = operand
    }
}

public struct IIGSDisassembler: Sendable {
    public typealias ByteReader = (UInt32) -> UInt8

    public init() {}

    public func decode(
        at address: UInt32,
        readByte: ByteReader,
        options: IIGSDisassemblyOptions
    ) -> IIGSDisassembledInstruction {
        let address = masked24(address)
        let opcode = readByte(address)
        guard let info = Self.opcodes[opcode] else {
            return IIGSDisassembledInstruction(address: address, bytes: [opcode], mnemonic: "DB", operand: "$\(hex(opcode))")
        }

        let length = info.mode.length(options: options)
        let bytes = (0..<length).map { readByte(address &+ UInt32($0)) }
        return IIGSDisassembledInstruction(
            address: address,
            bytes: bytes,
            mnemonic: info.mnemonic,
            operand: info.mode.operand(address: address, bytes: bytes, options: options)
        )
    }

    public func decode(
        at address: UInt32,
        count: Int,
        readByte: ByteReader,
        options: IIGSDisassemblyOptions
    ) -> [IIGSDisassembledInstruction] {
        var rows: [IIGSDisassembledInstruction] = []
        rows.reserveCapacity(max(0, count))
        var nextAddress = masked24(address)
        for _ in 0..<max(0, count) {
            let row = decode(at: nextAddress, readByte: readByte, options: options)
            rows.append(row)
            nextAddress = masked24(nextAddress &+ UInt32(max(1, row.length)))
        }
        return rows
    }

    private static let opcodes: [UInt8: OpcodeInfo] = [
        0x00: .init("BRK", .immediateByte),
        0x02: .init("COP", .immediateByte),
        0x08: .init("PHP", .implied),
        0x09: .init("ORA", .immediateAccumulator),
        0x0A: .init("ASL", .accumulator),
        0x0B: .init("PHD", .implied),
        0x10: .init("BPL", .relative8),
        0x18: .init("CLC", .implied),
        0x1A: .init("INA", .implied),
        0x1B: .init("TCS", .implied),
        0x20: .init("JSR", .absolute),
        0x22: .init("JSL", .absoluteLong),
        0x28: .init("PLP", .implied),
        0x29: .init("AND", .immediateAccumulator),
        0x2A: .init("ROL", .accumulator),
        0x2B: .init("PLD", .implied),
        0x30: .init("BMI", .relative8),
        0x38: .init("SEC", .implied),
        0x3A: .init("DEA", .implied),
        0x3B: .init("TSC", .implied),
        0x40: .init("RTI", .implied),
        0x42: .init("WDM", .immediateByte),
        0x44: .init("MVP", .blockMove),
        0x48: .init("PHA", .implied),
        0x49: .init("EOR", .immediateAccumulator),
        0x4A: .init("LSR", .accumulator),
        0x4B: .init("PHK", .implied),
        0x4C: .init("JMP", .absolute),
        0x50: .init("BVC", .relative8),
        0x54: .init("MVN", .blockMove),
        0x58: .init("CLI", .implied),
        0x5A: .init("PHY", .implied),
        0x5B: .init("TCD", .implied),
        0x5C: .init("JML", .absoluteLong),
        0x60: .init("RTS", .implied),
        0x62: .init("PER", .relative16),
        0x64: .init("STZ", .direct),
        0x68: .init("PLA", .implied),
        0x69: .init("ADC", .immediateAccumulator),
        0x6A: .init("ROR", .accumulator),
        0x6B: .init("RTL", .implied),
        0x6C: .init("JMP", .absoluteIndirect),
        0x70: .init("BVS", .relative8),
        0x78: .init("SEI", .implied),
        0x7A: .init("PLY", .implied),
        0x7B: .init("TDC", .implied),
        0x7C: .init("JMP", .absoluteIndexedIndirect),
        0x80: .init("BRA", .relative8),
        0x82: .init("BRL", .relative16),
        0x84: .init("STY", .direct),
        0x85: .init("STA", .direct),
        0x86: .init("STX", .direct),
        0x88: .init("DEY", .implied),
        0x89: .init("BIT", .immediateAccumulator),
        0x8A: .init("TXA", .implied),
        0x8B: .init("PHB", .implied),
        0x8C: .init("STY", .absolute),
        0x8D: .init("STA", .absolute),
        0x8E: .init("STX", .absolute),
        0x8F: .init("STA", .absoluteLong),
        0x90: .init("BCC", .relative8),
        0x98: .init("TYA", .implied),
        0x9A: .init("TXS", .implied),
        0x9B: .init("TXY", .implied),
        0x9C: .init("STZ", .absolute),
        0x9E: .init("STZ", .absoluteIndexedX),
        0x9F: .init("STA", .absoluteLongIndexedX),
        0xA0: .init("LDY", .immediateIndex),
        0xA2: .init("LDX", .immediateIndex),
        0xA4: .init("LDY", .direct),
        0xA5: .init("LDA", .direct),
        0xA6: .init("LDX", .direct),
        0xA8: .init("TAY", .implied),
        0xA9: .init("LDA", .immediateAccumulator),
        0xAA: .init("TAX", .implied),
        0xAB: .init("PLB", .implied),
        0xAC: .init("LDY", .absolute),
        0xAD: .init("LDA", .absolute),
        0xAE: .init("LDX", .absolute),
        0xAF: .init("LDA", .absoluteLong),
        0xB0: .init("BCS", .relative8),
        0xB8: .init("CLV", .implied),
        0xBA: .init("TSX", .implied),
        0xBB: .init("TYX", .implied),
        0xBC: .init("LDY", .absoluteIndexedX),
        0xBD: .init("LDA", .absoluteIndexedX),
        0xBE: .init("LDX", .absoluteIndexedY),
        0xBF: .init("LDA", .absoluteLongIndexedX),
        0xC0: .init("CPY", .immediateIndex),
        0xC2: .init("REP", .immediateByte),
        0xC8: .init("INY", .implied),
        0xC9: .init("CMP", .immediateAccumulator),
        0xCA: .init("DEX", .implied),
        0xCB: .init("WAI", .implied),
        0xD0: .init("BNE", .relative8),
        0xD4: .init("PEI", .directIndirect),
        0xD8: .init("CLD", .implied),
        0xDA: .init("PHX", .implied),
        0xDB: .init("STP", .implied),
        0xDC: .init("JML", .absoluteIndirectLong),
        0xE0: .init("CPX", .immediateIndex),
        0xE2: .init("SEP", .immediateByte),
        0xE8: .init("INX", .implied),
        0xE9: .init("SBC", .immediateAccumulator),
        0xEA: .init("NOP", .implied),
        0xEB: .init("XBA", .implied),
        0xF0: .init("BEQ", .relative8),
        0xF4: .init("PEA", .absolute),
        0xF8: .init("SED", .implied),
        0xFA: .init("PLX", .implied),
        0xFB: .init("XCE", .implied),
        0xFC: .init("JSR", .absoluteIndexedIndirect),
    ]

    private func hex(_ value: UInt8) -> String {
        Self.hex(UInt32(value), width: 2)
    }

    private static func hex(_ value: UInt32, width: Int) -> String {
        let text = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: Swift.max(0, width - text.count)) + text
    }
}

private struct OpcodeInfo: Sendable {
    let mnemonic: String
    let mode: DisassemblyAddressingMode

    init(_ mnemonic: String, _ mode: DisassemblyAddressingMode) {
        self.mnemonic = mnemonic
        self.mode = mode
    }
}

private enum DisassemblyAddressingMode: Sendable {
    case implied
    case accumulator
    case immediateByte
    case immediateAccumulator
    case immediateIndex
    case direct
    case directIndirect
    case absolute
    case absoluteIndexedX
    case absoluteIndexedY
    case absoluteLong
    case absoluteLongIndexedX
    case absoluteIndirect
    case absoluteIndirectLong
    case absoluteIndexedIndirect
    case relative8
    case relative16
    case blockMove

    func length(options: IIGSDisassemblyOptions) -> Int {
        switch self {
        case .implied, .accumulator:
            return 1
        case .immediateAccumulator:
            return options.accumulatorIs8Bit ? 2 : 3
        case .immediateIndex:
            return options.indexRegistersAre8Bit ? 2 : 3
        case .immediateByte, .direct, .directIndirect, .relative8:
            return 2
        case .absolute, .absoluteIndexedX, .absoluteIndexedY, .absoluteIndirect, .absoluteIndirectLong, .absoluteIndexedIndirect, .relative16, .blockMove:
            return 3
        case .absoluteLong, .absoluteLongIndexedX:
            return 4
        }
    }

    func operand(address: UInt32, bytes: [UInt8], options: IIGSDisassemblyOptions) -> String {
        switch self {
        case .implied:
            return ""
        case .accumulator:
            return "A"
        case .immediateByte:
            return "#$\(hex(byte(bytes, 1)))"
        case .immediateAccumulator:
            return immediate(bytes: bytes, isByte: options.accumulatorIs8Bit)
        case .immediateIndex:
            return immediate(bytes: bytes, isByte: options.indexRegistersAre8Bit)
        case .direct:
            return "$\(hex(byte(bytes, 1)))"
        case .directIndirect:
            return "($\(hex(byte(bytes, 1))))"
        case .absolute:
            return "$\(hex(word(bytes, 1)))"
        case .absoluteIndexedX:
            return "$\(hex(word(bytes, 1))),X"
        case .absoluteIndexedY:
            return "$\(hex(word(bytes, 1))),Y"
        case .absoluteLong:
            return "$\(hex(long(bytes, 1), width: 6))"
        case .absoluteLongIndexedX:
            return "$\(hex(long(bytes, 1), width: 6)),X"
        case .absoluteIndirect:
            return "($\(hex(word(bytes, 1))))"
        case .absoluteIndirectLong:
            return "[$\(hex(word(bytes, 1)))]"
        case .absoluteIndexedIndirect:
            return "($\(hex(word(bytes, 1))),X)"
        case .relative8:
            let displacement = Int8(bitPattern: byte(bytes, 1))
            let base = masked24(address &+ UInt32(length(options: options)))
            let target = masked24(UInt32(bitPattern: Int32(bitPattern: base) &+ Int32(displacement)))
            return "$\(hex(target, width: 6))"
        case .relative16:
            let displacement = Int16(bitPattern: word(bytes, 1))
            let base = masked24(address &+ UInt32(length(options: options)))
            let target = masked24(UInt32(bitPattern: Int32(bitPattern: base) &+ Int32(displacement)))
            return "$\(hex(target, width: 6))"
        case .blockMove:
            return "$\(hex(byte(bytes, 1))),$\(hex(byte(bytes, 2)))"
        }
    }

    private func immediate(bytes: [UInt8], isByte: Bool) -> String {
        if isByte {
            return "#$\(hex(byte(bytes, 1)))"
        }
        return "#$\(hex(word(bytes, 1)))"
    }

    private func byte(_ bytes: [UInt8], _ index: Int) -> UInt8 {
        bytes.indices.contains(index) ? bytes[index] : 0
    }

    private func word(_ bytes: [UInt8], _ index: Int) -> UInt16 {
        UInt16(byte(bytes, index)) | (UInt16(byte(bytes, index + 1)) << 8)
    }

    private func long(_ bytes: [UInt8], _ index: Int) -> UInt32 {
        UInt32(byte(bytes, index)) | (UInt32(byte(bytes, index + 1)) << 8) | (UInt32(byte(bytes, index + 2)) << 16)
    }

    private func hex(_ value: UInt8) -> String {
        hex(UInt32(value), width: 2)
    }

    private func hex(_ value: UInt16) -> String {
        hex(UInt32(value), width: 4)
    }

    private func hex(_ value: UInt32, width: Int) -> String {
        let text = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: Swift.max(0, width - text.count)) + text
    }
}
