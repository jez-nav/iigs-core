import Foundation

public enum IIGSDebuggerError: Error, Equatable, CustomStringConvertible {
    case unknownCommand(String)
    case missingArgument(String)
    case invalidArgument(String)
    case invalidNumber(String)

    public var description: String {
        switch self {
        case let .unknownCommand(command):
            "Unknown debugger command: \(command)"
        case let .missingArgument(argument):
            "Missing debugger argument: \(argument)"
        case let .invalidArgument(argument):
            "Invalid debugger argument: \(argument)"
        case let .invalidNumber(value):
            "Invalid debugger number: \(value)"
        }
    }
}

public enum IIGSDebuggerCommand: Equatable, Sendable {
    case help
    case quit
    case reset(IIGSResetKind)
    case registers
    case step(Int)
    case run(Int)
    case runCycles(Int)
    case addBreakpoint(UInt32)
    case removeBreakpoint(UInt32)
    case listBreakpoints
    case readMemory(UInt32, Int)
    case writeMemory(UInt32, UInt8)
}

public struct IIGSDebuggerCommandParser: Sendable {
    public init() {}

    public func parse(_ line: String) throws -> IIGSDebuggerCommand? {
        let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let verb = parts.first?.lowercased() else {
            return nil
        }

        switch verb {
        case "h", "help", "?":
            return .help
        case "q", "quit", "exit":
            return .quit
        case "reset":
            return .reset(try parseResetKind(parts.dropFirst()))
        case "r", "regs", "registers":
            return .registers
        case "s", "step":
            return .step(try parseOptionalCount(parts.dropFirst(), defaultValue: 1))
        case "run", "g", "go":
            return .run(try parseOptionalCount(parts.dropFirst(), defaultValue: 1_000))
        case "cycles":
            return .runCycles(try parseRequiredInt(parts.dropFirst(), name: "cycle count"))
        case "bp", "break", "breakpoint":
            return .addBreakpoint(try parseRequiredAddress(parts.dropFirst(), name: "breakpoint address"))
        case "bc", "clear":
            return .removeBreakpoint(try parseRequiredAddress(parts.dropFirst(), name: "breakpoint address"))
        case "bl", "breakpoints":
            return .listBreakpoints
        case "m", "mem", "memory":
            return try parseReadMemory(parts.dropFirst())
        case "set", "write":
            return try parseWriteMemory(parts.dropFirst())
        default:
            throw IIGSDebuggerError.unknownCommand(verb)
        }
    }

    public func parseAddress(_ text: String) throws -> UInt32 {
        let normalized = normalizeNumber(text)
        guard let value = UInt32(normalized, radix: 16) else {
            throw IIGSDebuggerError.invalidNumber(text)
        }
        return masked24(value)
    }

    public func parseByte(_ text: String) throws -> UInt8 {
        let normalized = normalizeNumber(text)
        guard let value = UInt8(normalized, radix: 16) else {
            throw IIGSDebuggerError.invalidNumber(text)
        }
        return value
    }

    private func parseResetKind(_ parts: ArraySlice<String>) throws -> IIGSResetKind {
        guard let value = parts.first?.lowercased() else {
            return .cold
        }
        switch value {
        case "cold":
            return .cold
        case "warm":
            return .warm
        default:
            throw IIGSDebuggerError.invalidArgument(value)
        }
    }

    private func parseOptionalCount(_ parts: ArraySlice<String>, defaultValue: Int) throws -> Int {
        guard let value = parts.first else {
            return defaultValue
        }
        return try parseRequiredInt([value], name: "count")
    }

    private func parseRequiredInt(_ parts: ArraySlice<String>, name: String) throws -> Int {
        guard let value = parts.first else {
            throw IIGSDebuggerError.missingArgument(name)
        }

        if let decimal = Int(value, radix: 10), !looksHexLike(value) {
            return decimal
        }

        let normalized = normalizeNumber(value)
        guard let hex = Int(normalized, radix: 16) else {
            throw IIGSDebuggerError.invalidNumber(value)
        }
        return hex
    }

    private func parseRequiredAddress(_ parts: ArraySlice<String>, name: String) throws -> UInt32 {
        guard let value = parts.first else {
            throw IIGSDebuggerError.missingArgument(name)
        }
        return try parseAddress(value)
    }

    private func parseReadMemory(_ parts: ArraySlice<String>) throws -> IIGSDebuggerCommand {
        let address = try parseRequiredAddress(parts, name: "memory address")
        let count = try parseOptionalCount(parts.dropFirst(), defaultValue: 16)
        return .readMemory(address, count)
    }

    private func parseWriteMemory(_ parts: ArraySlice<String>) throws -> IIGSDebuggerCommand {
        let address = try parseRequiredAddress(parts, name: "memory address")
        guard let value = parts.dropFirst().first else {
            throw IIGSDebuggerError.missingArgument("byte value")
        }
        return .writeMemory(address, try parseByte(value))
    }

    private func normalizeNumber(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("$") {
            value.removeFirst()
        }
        if value.hasPrefix("0X") {
            value.removeFirst(2)
        }
        value = value.replacingOccurrences(of: ":", with: "")
        value = value.replacingOccurrences(of: "/", with: "")
        value = value.replacingOccurrences(of: "_", with: "")
        return value
    }

    private func looksHexLike(_ text: String) -> Bool {
        text.hasPrefix("$") || text.hasPrefix("0x") || text.hasPrefix("0X") || text.contains(":") || text.contains("/") ||
            text.uppercased().contains { ("A"..."F").contains(String($0)) }
    }
}

public final class IIGSDebuggerSession {
    public let machine: IIGSMachine
    public private(set) var breakpoints: Set<UInt32> = []

    public init(machine: IIGSMachine = IIGSMachine()) {
        self.machine = machine
    }

    public func loadROM(bytes: [UInt8]) throws {
        try machine.installROM(bytes: bytes)
    }

    public func loadBinary(_ bytes: [UInt8], at address: UInt32) {
        machine.memory.load(bytes, at: masked24(address))
    }

    public func snapshot() -> IIGSDebuggerSnapshot {
        IIGSDebuggerSnapshot(machine: machine)
    }

    public func memoryRows(bank: UInt8, startOffset: UInt16, rowCount: Int) -> [IIGSDebuggerMemoryRow] {
        let count = max(0, rowCount)
        let firstOffset = startOffset & 0xFFF0
        return (0..<count).map { rowIndex in
            let offset = UInt16(truncatingIfNeeded: UInt32(firstOffset) &+ UInt32(rowIndex * IIGSDebuggerMemoryRow.bytesPerRow))
            let address = (UInt32(bank) << 16) | UInt32(offset)
            let bytes = (0..<IIGSDebuggerMemoryRow.bytesPerRow).map { byteIndex in
                machine.memory.debugRead8(at: address &+ UInt32(byteIndex))
            }
            return IIGSDebuggerMemoryRow(bank: bank, offset: offset, bytes: bytes)
        }
    }

    @discardableResult
    public func execute(_ command: IIGSDebuggerCommand) throws -> String {
        switch command {
        case .help:
            return Self.helpText
        case .quit:
            return "quit"
        case let .reset(kind):
            machine.reset(kind)
            return "Reset \(kind) PC=\(formatAddress(machine.currentProgramAddress))"
        case .registers:
            return formatRegisters()
        case let .step(count):
            return try step(count: count)
        case let .run(limit):
            return try describe(machine.runUntilStop(instructionLimit: limit, breakpoints: breakpoints))
        case let .runCycles(cycles):
            return try describe(machine.runForCycles(cycles))
        case let .addBreakpoint(address):
            breakpoints.insert(masked24(address))
            return "Breakpoint set at \(formatAddress(address))"
        case let .removeBreakpoint(address):
            breakpoints.remove(masked24(address))
            return "Breakpoint cleared at \(formatAddress(address))"
        case .listBreakpoints:
            return formatBreakpoints()
        case let .readMemory(address, count):
            return readMemory(at: address, count: count)
        case let .writeMemory(address, value):
            machine.memory.write8(value, at: address)
            return "\(formatAddress(address)) <- \(formatByte(value))"
        }
    }

    public func formatRegisters() -> String {
        let r = machine.cpu.registers
        return [
            "PC=\(formatAddress(machine.currentProgramAddress))",
            "A=\(formatWord(r.accumulator))",
            "X=\(formatWord(r.x))",
            "Y=\(formatWord(r.y))",
            "S=\(formatWord(r.stackPointer))",
            "D=\(formatWord(r.directPage))",
            "DBR=\(formatByte(r.dataBank))",
            "PBR=\(formatByte(r.programBank))",
            "P=\(formatByte(r.status.rawValue))",
            "E=\(r.emulationMode ? 1 : 0)"
        ].joined(separator: " ")
    }

    public static let helpText = """
    Commands:
      regs                  Show CPU registers
      step [count]          Step one or more instructions
      run [limit]           Run until breakpoint, WAI/STP, or instruction limit
      cycles <count>        Run until at least count bus cycles elapse
      bp <addr>             Add breakpoint
      bc <addr>             Clear breakpoint
      bl                    List breakpoints
      mem <addr> [count]    Read memory
      set <addr> <byte>     Write memory
      reset [cold|warm]     Reset through ROM vector
      quit                  Exit
    """

    private func step(count: Int) throws -> String {
        try requirePositive(count, name: "step count")
        var result: IIGSMachineStepResult?
        for _ in 0..<count {
            result = try machine.stepInstruction()
        }
        guard let result else {
            return "No step executed"
        }
        return "Stepped \(count) instruction(s), last \(formatAddress(result.address)), cycles=\(result.cycles), \(formatRegisters())"
    }

    private func readMemory(at address: UInt32, count: Int) -> String {
        let byteCount = max(0, count)
        var values: [String] = []
        values.reserveCapacity(byteCount)
        for offset in 0..<byteCount {
            values.append(formatByte(machine.memory.read8(at: address &+ UInt32(offset))))
        }
        return "\(formatAddress(address)): \(values.joined(separator: " "))"
    }

    private func formatBreakpoints() -> String {
        guard !breakpoints.isEmpty else {
            return "No breakpoints"
        }
        return breakpoints.sorted().map(formatAddress).joined(separator: "\n")
    }

    private func describe(_ result: IIGSMachineRunResult) -> String {
        "Stopped: \(describe(result.stopReason)) instructions=\(result.instructionsExecuted) cycles=\(result.cyclesElapsed) PC=\(formatAddress(result.finalAddress))"
    }

    private func describe(_ reason: IIGSMachineStopReason) -> String {
        switch reason {
        case .instructionLimitReached:
            "instruction limit"
        case .cycleLimitReached:
            "cycle limit"
        case let .breakpoint(address):
            "breakpoint \(formatAddress(address))"
        case .stopped:
            "stopped"
        case .waiting:
            "waiting"
        }
    }

    private func requirePositive(_ value: Int, name: String) throws {
        if value <= 0 {
            throw IIGSDebuggerError.invalidArgument(name)
        }
    }

    private func formatAddress(_ address: UInt32) -> String {
        "$" + String(formatHex: masked24(address), width: 6)
    }

    private func formatWord(_ value: UInt16) -> String {
        "$" + String(formatHex: UInt32(value), width: 4)
    }

    private func formatByte(_ value: UInt8) -> String {
        "$" + String(formatHex: UInt32(value), width: 2)
    }
}

private extension String {
    init(formatHex value: UInt32, width: Int) {
        let text = String(value, radix: 16, uppercase: true)
        self = String(repeating: "0", count: Swift.max(0, width - text.count)) + text
    }
}
