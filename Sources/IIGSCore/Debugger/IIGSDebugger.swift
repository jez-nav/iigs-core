import Foundation

public enum IIGSDebuggerError: Error, Equatable, CustomStringConvertible {
    case unknownCommand(String)
    case missingArgument(String)
    case invalidArgument(String)
    case invalidNumber(String)
    case assertionFailed(String)

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
        case let .assertionFailed(message):
            "Assertion failed: \(message)"
        }
    }
}

public enum IIGSDebuggerComparison: Equatable, Sendable {
    case equal
    case greaterThanOrEqual
    case lessThanOrEqual
}

public enum IIGSDebuggerAssertion: Equatable, Sendable {
    case programCounter(UInt32)
    case register(String, UInt32)
    case flag(String, Bool)
    case status(String, Bool)
    case memory(UInt32, UInt8)
    case cycles(IIGSDebuggerComparison, UInt64)
}

public enum IIGSDebuggerCommand: Equatable, Sendable {
    case help
    case quit
    case reset(IIGSResetKind)
    case registers
    case snapshot
    case events
    case scheduleEvent(IIGSEventKind, UInt64, UInt32)
    case step(Int)
    case run(Int)
    case runCycles(Int)
    case runUntilPC(UInt32, Int)
    case addBreakpoint(UInt32)
    case removeBreakpoint(UInt32)
    case listBreakpoints
    case readMemory(UInt32, Int)
    case disassemble(UInt32, Int)
    case writeMemory(UInt32, UInt8)
    case writeRegister(String, UInt32)
    case assertion(IIGSDebuggerAssertion)
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
        case "snapshot", "state":
            return .snapshot
        case "events":
            return .events
        case "schedule":
            return try parseScheduleEvent(parts.dropFirst())
        case "s", "step":
            return .step(try parseOptionalCount(parts.dropFirst(), defaultValue: 1))
        case "run", "g", "go":
            return .run(try parseOptionalCount(parts.dropFirst(), defaultValue: 1_000))
        case "cycles":
            return .runCycles(try parseRequiredInt(parts.dropFirst(), name: "cycle count"))
        case "runpc":
            return try parseRunUntilPC(parts.dropFirst())
        case "bp", "break", "breakpoint":
            return .addBreakpoint(try parseRequiredAddress(parts.dropFirst(), name: "breakpoint address"))
        case "bc", "clear":
            return .removeBreakpoint(try parseRequiredAddress(parts.dropFirst(), name: "breakpoint address"))
        case "bl", "breakpoints":
            return .listBreakpoints
        case "m", "mem", "memory":
            return try parseReadMemory(parts.dropFirst())
        case "d", "dis", "disasm", "disassemble":
            return try parseDisassemble(parts.dropFirst())
        case "set", "write":
            return try parseWriteMemory(parts.dropFirst())
        case "setreg", "regset":
            return try parseWriteRegister(parts.dropFirst())
        case "assert":
            return .assertion(try parseAssertion(parts.dropFirst()))
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

    public func parseBool(_ text: String) throws -> Bool {
        switch text.lowercased() {
        case "1", "true", "yes", "on", "set":
            return true
        case "0", "false", "no", "off", "clear":
            return false
        default:
            throw IIGSDebuggerError.invalidArgument(text)
        }
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

    private func parseRunUntilPC(_ parts: ArraySlice<String>) throws -> IIGSDebuggerCommand {
        let address = try parseRequiredAddress(parts, name: "program counter")
        let limit = try parseOptionalCount(parts.dropFirst(), defaultValue: 10_000)
        return .runUntilPC(address, limit)
    }

    private func parseDisassemble(_ parts: ArraySlice<String>) throws -> IIGSDebuggerCommand {
        let address = try parseRequiredAddress(parts, name: "disassembly address")
        let count = try parseOptionalCount(parts.dropFirst(), defaultValue: 12)
        return .disassemble(address, count)
    }

    private func parseScheduleEvent(_ parts: ArraySlice<String>) throws -> IIGSDebuggerCommand {
        guard let kindText = parts.first else {
            throw IIGSDebuggerError.missingArgument("event kind")
        }
        let kind = try parseEventKind(kindText)
        let cycleDelay = try parseRequiredInt(parts.dropFirst(), name: "cycle delay")
        let payload = try parts.dropFirst(2).first.map { try parseRequiredAddress([$0], name: "payload") } ?? 0
        return .scheduleEvent(kind, UInt64(cycleDelay), payload)
    }

    private func parseEventKind(_ text: String) throws -> IIGSEventKind {
        switch text.lowercased() {
        case "paddle", "paddletimeout":
            return .paddleTimeout
        case "doc", "docoscillator":
            return .docOscillator
        case "disk":
            return .disk
        case "scc":
            return .scc
        case "clock", "clocktick":
            return .clockTick
        case "custom":
            return .custom
        default:
            throw IIGSDebuggerError.invalidArgument(text)
        }
    }

    private func parseAssertion(_ parts: ArraySlice<String>) throws -> IIGSDebuggerAssertion {
        guard let target = parts.first?.lowercased() else {
            throw IIGSDebuggerError.missingArgument("assertion target")
        }

        switch target {
        case "pc":
            return .programCounter(try parseRequiredAddress(parts.dropFirst(), name: "program counter"))
        case "reg", "register":
            guard let name = parts.dropFirst().first else {
                throw IIGSDebuggerError.missingArgument("register name")
            }
            let value = try parseRequiredAddress(parts.dropFirst(2), name: "register value")
            return .register(name, value)
        case "flag":
            guard let name = parts.dropFirst().first else {
                throw IIGSDebuggerError.missingArgument("flag name")
            }
            guard let value = parts.dropFirst(2).first else {
                throw IIGSDebuggerError.missingArgument("flag value")
            }
            return .flag(name, try parseBool(value))
        case "status":
            guard let name = parts.dropFirst().first else {
                throw IIGSDebuggerError.missingArgument("status name")
            }
            guard let value = parts.dropFirst(2).first else {
                throw IIGSDebuggerError.missingArgument("status value")
            }
            return .status(name, try parseBool(value))
        case "irq", "nmi", "waiting", "stopped", "ready":
            guard let value = parts.dropFirst().first else {
                throw IIGSDebuggerError.missingArgument("status value")
            }
            return .status(target, try parseBool(value))
        case "mem", "memory":
            let address = try parseRequiredAddress(parts.dropFirst(), name: "memory address")
            guard let value = parts.dropFirst(2).first else {
                throw IIGSDebuggerError.missingArgument("memory byte")
            }
            return .memory(address, try parseByte(value))
        case "cycles":
            let remainder = parts.dropFirst()
            guard let first = remainder.first else {
                throw IIGSDebuggerError.missingArgument("cycle count")
            }
            if let comparison = parseComparison(first) {
                let value = try parseRequiredInt(remainder.dropFirst(), name: "cycle count")
                return .cycles(comparison, UInt64(value))
            }
            return .cycles(.equal, UInt64(try parseRequiredInt(remainder, name: "cycle count")))
        default:
            throw IIGSDebuggerError.invalidArgument(target)
        }
    }

    private func parseComparison(_ text: String) -> IIGSDebuggerComparison? {
        switch text {
        case "=", "==":
            return .equal
        case ">=":
            return .greaterThanOrEqual
        case "<=":
            return .lessThanOrEqual
        default:
            return nil
        }
    }

    private func parseWriteMemory(_ parts: ArraySlice<String>) throws -> IIGSDebuggerCommand {
        let address = try parseRequiredAddress(parts, name: "memory address")
        guard let value = parts.dropFirst().first else {
            throw IIGSDebuggerError.missingArgument("byte value")
        }
        return .writeMemory(address, try parseByte(value))
    }

    private func parseWriteRegister(_ parts: ArraySlice<String>) throws -> IIGSDebuggerCommand {
        guard let name = parts.first else {
            throw IIGSDebuggerError.missingArgument("register name")
        }
        let value = try parseRequiredAddress(parts.dropFirst(), name: "register value")
        return .writeRegister(name, value)
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
    private let disassembler = IIGSDisassembler()

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

    public func disassemblyRows(startingAt address: UInt32, count: Int) -> [IIGSDisassembledInstruction] {
        disassembler.decode(
            at: address,
            count: count,
            readByte: { [machine] address in machine.memory.debugRead8(at: address) },
            options: IIGSDisassemblyOptions(registers: machine.cpu.registers)
        )
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
        case .snapshot:
            return formatSnapshot()
        case .events:
            return formatEvents()
        case let .scheduleEvent(kind, cycles, payload):
            scheduleEvent(kind, afterCycles: cycles, payload: payload)
            return "Scheduled \(formatEventKind(kind)) after \(cycles) cycle(s) payload=\(formatHex(payload, width: 6))"
        case let .step(count):
            return try step(count: count)
        case let .run(limit):
            return try describe(machine.runUntilStop(instructionLimit: limit, breakpoints: breakpoints))
        case let .runCycles(cycles):
            return try describe(machine.runForCycles(cycles))
        case let .runUntilPC(address, limit):
            return try describe(machine.runUntilBreakpoint(address, instructionLimit: limit))
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
        case let .disassemble(address, count):
            return disassemble(at: address, count: count)
        case let .writeMemory(address, value):
            machine.memory.write8(value, at: address)
            return "\(formatAddress(address)) <- \(formatByte(value))"
        case let .writeRegister(name, value):
            try writeRegister(named: name, value: value)
            return "\(name.uppercased()) <- $\(formatHex(value, width: registerWidth(named: name)))"
        case let .assertion(assertion):
            try evaluate(assertion)
            return "ASSERT OK \(formatAssertion(assertion))"
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
      snapshot              Show registers, flags, status, timing, and event summary
      step [count]          Step one or more instructions
      run [limit]           Run until breakpoint, WAI/STP, or instruction limit
      runpc <addr> [limit]  Run until PC reaches addr
      cycles <count>        Run until at least count bus cycles elapse
      events                Show pending and serviced scheduler events
      schedule <kind> <cycles> [payload]
                            Schedule paddle, doc, disk, scc, clock, or custom event
      bp <addr>             Add breakpoint
      bc <addr>             Clear breakpoint
      bl                    List breakpoints
      mem <addr> [count]    Read memory
      disasm <addr> [count] Disassemble memory using current CPU widths
      set <addr> <byte>     Write memory
      setreg <name> <value> Write CPU register
      assert pc <addr>
      assert reg <name> <value>
      assert flag <name> <0|1>
      assert status <name> <0|1>
      assert mem <addr> <byte>
      assert cycles [=|>=|<=] <count>
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

    private func disassemble(at address: UInt32, count: Int) -> String {
        let rows = disassemblyRows(startingAt: address, count: count)
        guard !rows.isEmpty else {
            return "No disassembly"
        }
        return rows.map { row in
            let byteText = row.bytes.map(formatByte).joined(separator: " ")
            return "\(formatAddress(row.address)): \(byteText.padding(toLength: 14, withPad: " ", startingAt: 0)) \(row.text)"
        }.joined(separator: "\n")
    }

    private func scheduleEvent(_ kind: IIGSEventKind, afterCycles cycles: UInt64, payload: UInt32) {
        switch kind {
        case .paddleTimeout:
            machine.schedulePaddleTimeout(paddle: UInt8(truncatingIfNeeded: payload), afterCycles: cycles)
        case .docOscillator:
            machine.scheduleDOCEvent(oscillator: UInt8(truncatingIfNeeded: payload), afterCycles: cycles)
        case .disk:
            machine.scheduleDiskEvent(drive: UInt8(truncatingIfNeeded: payload), afterCycles: cycles)
        case .scc, .clockTick, .custom:
            machine.scheduler.schedule(kind: kind, at: machine.memory.cycleCount &+ cycles, payload: payload)
        case .videoScanline, .verticalBlankStart, .verticalBlankEnd, .videoFrame:
            machine.scheduler.schedule(kind: kind, at: machine.memory.cycleCount &+ cycles, payload: payload)
        }
    }

    private func formatSnapshot() -> String {
        let snapshot = snapshot()
        return [
            formatRegisters(),
            "flags=N\(bit(snapshot.flags.negative)) V\(bit(snapshot.flags.overflow)) M\(bit(snapshot.flags.accumulator8Bit)) X\(bit(snapshot.flags.index8Bit)) D\(bit(snapshot.flags.decimal)) I\(bit(snapshot.flags.interruptDisable)) Z\(bit(snapshot.flags.zero)) C\(bit(snapshot.flags.carry))",
            "status=RDY\(bit(snapshot.status.ready)) IRQ\(bit(snapshot.status.irqPending)) NMI\(bit(snapshot.status.nmiPending)) WAI\(bit(snapshot.status.waiting)) STP\(bit(snapshot.status.stopped))",
            "timing=cycles:\(snapshot.timing.cycles) line:\(snapshot.timing.videoLine) dot:\(snapshot.timing.videoCycleInLine) frameCycle:\(snapshot.timing.videoFrameCycle) vbl:\(bit(snapshot.timing.inVerticalBlank))",
            "events=pending:\(machine.scheduler.pendingEvents().count) serviced:\(machine.servicedDeviceEvents.count)"
        ].joined(separator: "\n")
    }

    private func formatEvents() -> String {
        let pending = machine.scheduler.pendingEvents().prefix(8).map {
            "pending id=\($0.id) cycle=\($0.cycle) kind=\(formatEventKind($0.kind)) payload=\(formatHex($0.payload, width: 6))"
        }
        let serviced = machine.servicedDeviceEvents.prefix(8).map {
            "serviced id=\($0.id) cycle=\($0.cycle) kind=\(formatEventKind($0.kind)) payload=\(formatHex($0.payload, width: 6))"
        }
        let rows = Array(pending) + Array(serviced)
        return rows.isEmpty ? "No events" : rows.joined(separator: "\n")
    }

    private func evaluate(_ assertion: IIGSDebuggerAssertion) throws {
        switch assertion {
        case let .programCounter(expected):
            let actual = machine.currentProgramAddress
            try assertEqual(actual, masked24(expected), label: "PC", width: 6)
        case let .register(name, expected):
            let actual = try registerValue(named: name)
            try assertEqual(actual, expected, label: name.uppercased(), width: registerWidth(named: name))
        case let .flag(name, expected):
            let actual = try flagValue(named: name)
            if actual != expected {
                throw IIGSDebuggerError.assertionFailed("flag \(name.uppercased()) expected \(bit(expected)) got \(bit(actual))")
            }
        case let .status(name, expected):
            let actual = try statusValue(named: name)
            if actual != expected {
                throw IIGSDebuggerError.assertionFailed("status \(name.uppercased()) expected \(bit(expected)) got \(bit(actual))")
            }
        case let .memory(address, expected):
            let actual = machine.memory.read8(at: address)
            if actual != expected {
                throw IIGSDebuggerError.assertionFailed("memory \(formatAddress(address)) expected \(formatByte(expected)) got \(formatByte(actual))")
            }
        case let .cycles(comparison, expected):
            let actual = machine.memory.cycleCount
            let passed: Bool
            switch comparison {
            case .equal:
                passed = actual == expected
            case .greaterThanOrEqual:
                passed = actual >= expected
            case .lessThanOrEqual:
                passed = actual <= expected
            }
            if !passed {
                throw IIGSDebuggerError.assertionFailed("cycles expected \(formatComparison(comparison)) \(expected) got \(actual)")
            }
        }
    }

    private func assertEqual(_ actual: UInt32, _ expected: UInt32, label: String, width: Int) throws {
        let mask: UInt32 = width <= 2 ? 0xFF : width <= 4 ? 0xFFFF : 0xFF_FFFF
        if actual & mask != expected & mask {
            throw IIGSDebuggerError.assertionFailed("\(label) expected $\(formatHex(expected & mask, width: width)) got $\(formatHex(actual & mask, width: width))")
        }
    }

    private func registerValue(named name: String) throws -> UInt32 {
        let r = machine.cpu.registers
        switch name.lowercased() {
        case "pc":
            return UInt32(r.programCounter)
        case "pbr":
            return UInt32(r.programBank)
        case "addr", "address":
            return machine.currentProgramAddress
        case "a":
            return UInt32(r.accumulator)
        case "x":
            return UInt32(r.x)
        case "y":
            return UInt32(r.y)
        case "s", "sp":
            return UInt32(r.stackPointer)
        case "d", "dp":
            return UInt32(r.directPage)
        case "dbr":
            return UInt32(r.dataBank)
        case "p":
            return UInt32(r.status.rawValue)
        case "e":
            return r.emulationMode ? 1 : 0
        default:
            throw IIGSDebuggerError.invalidArgument(name)
        }
    }

    private func writeRegister(named name: String, value: UInt32) throws {
        let normalized = name.lowercased()
        switch normalized {
        case "pc":
            machine.cpu.updateRegisters { $0.programCounter = UInt16(truncatingIfNeeded: value) }
        case "pbr":
            machine.cpu.updateRegisters { $0.programBank = UInt8(truncatingIfNeeded: value) }
        case "addr", "address":
            machine.cpu.updateRegisters {
                $0.programBank = UInt8(truncatingIfNeeded: value >> 16)
                $0.programCounter = UInt16(truncatingIfNeeded: value)
            }
        case "a":
            machine.cpu.updateRegisters { $0.accumulator = UInt16(truncatingIfNeeded: value) }
        case "x":
            machine.cpu.updateRegisters { $0.x = UInt16(truncatingIfNeeded: value) }
        case "y":
            machine.cpu.updateRegisters { $0.y = UInt16(truncatingIfNeeded: value) }
        case "s", "sp":
            machine.cpu.updateRegisters { $0.stackPointer = UInt16(truncatingIfNeeded: value) }
        case "d", "dp":
            machine.cpu.updateRegisters { $0.directPage = UInt16(truncatingIfNeeded: value) }
        case "dbr":
            machine.cpu.updateRegisters { $0.dataBank = UInt8(truncatingIfNeeded: value) }
        case "p":
            machine.cpu.updateRegisters { $0.status = ProcessorStatus(rawValue: UInt8(truncatingIfNeeded: value)) }
        case "e":
            machine.cpu.updateRegisters { $0.emulationMode = value & 1 != 0 }
        default:
            throw IIGSDebuggerError.invalidArgument(name)
        }
    }

    private func registerWidth(named name: String) -> Int {
        switch name.lowercased() {
        case "pbr", "dbr", "p", "e":
            return 2
        case "addr", "address":
            return 6
        default:
            return 4
        }
    }

    private func flagValue(named name: String) throws -> Bool {
        let status = machine.cpu.registers.status
        switch name.lowercased() {
        case "n", "negative":
            return status.contains(.negative)
        case "v", "overflow":
            return status.contains(.overflow)
        case "m":
            return status.contains(.accumulator8Bit)
        case "x":
            return status.contains(.indexRegister8Bit)
        case "d", "decimal":
            return status.contains(.decimal)
        case "i", "interrupt":
            return status.contains(.interruptDisable)
        case "z", "zero":
            return status.contains(.zero)
        case "c", "carry":
            return status.contains(.carry)
        default:
            throw IIGSDebuggerError.invalidArgument(name)
        }
    }

    private func statusValue(named name: String) throws -> Bool {
        let snapshot = snapshot().status
        switch name.lowercased() {
        case "rdy", "ready":
            return snapshot.ready
        case "irq":
            return snapshot.irqPending
        case "nmi":
            return snapshot.nmiPending
        case "abort":
            return snapshot.abortPending
        case "wai", "waiting":
            return snapshot.waiting
        case "stp", "stopped":
            return snapshot.stopped
        case "e", "emulation":
            return snapshot.emulationMode
        default:
            throw IIGSDebuggerError.invalidArgument(name)
        }
    }

    private func formatAssertion(_ assertion: IIGSDebuggerAssertion) -> String {
        switch assertion {
        case let .programCounter(address):
            return "pc \(formatAddress(address))"
        case let .register(name, value):
            return "reg \(name.uppercased()) $\(formatHex(value, width: registerWidth(named: name)))"
        case let .flag(name, value):
            return "flag \(name.uppercased()) \(bit(value))"
        case let .status(name, value):
            return "status \(name.uppercased()) \(bit(value))"
        case let .memory(address, value):
            return "mem \(formatAddress(address)) \(formatByte(value))"
        case let .cycles(comparison, value):
            return "cycles \(formatComparison(comparison)) \(value)"
        }
    }

    private func formatComparison(_ comparison: IIGSDebuggerComparison) -> String {
        switch comparison {
        case .equal:
            return "=="
        case .greaterThanOrEqual:
            return ">="
        case .lessThanOrEqual:
            return "<="
        }
    }

    private func formatEventKind(_ kind: IIGSEventKind) -> String {
        switch kind {
        case .videoScanline:
            return "videoScanline"
        case .verticalBlankStart:
            return "verticalBlankStart"
        case .verticalBlankEnd:
            return "verticalBlankEnd"
        case .videoFrame:
            return "videoFrame"
        case .paddleTimeout:
            return "paddleTimeout"
        case .docOscillator:
            return "docOscillator"
        case .disk:
            return "disk"
        case .scc:
            return "scc"
        case .clockTick:
            return "clockTick"
        case .custom:
            return "custom"
        }
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
        "$" + formatHex(masked24(address), width: 6)
    }

    private func formatWord(_ value: UInt16) -> String {
        "$" + formatHex(UInt32(value), width: 4)
    }

    private func formatByte(_ value: UInt8) -> String {
        "$" + formatHex(UInt32(value), width: 2)
    }

    private func formatHex(_ value: UInt32, width: Int) -> String {
        String(formatHex: value, width: width)
    }

    private func bit(_ value: Bool) -> String {
        value ? "1" : "0"
    }
}

private extension String {
    init(formatHex value: UInt32, width: Int) {
        let text = String(value, radix: 16, uppercase: true)
        self = String(repeating: "0", count: Swift.max(0, width - text.count)) + text
    }
}
