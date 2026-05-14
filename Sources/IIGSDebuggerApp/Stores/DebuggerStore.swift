import Foundation
import IIGSCore

@MainActor
final class DebuggerStore: ObservableObject {
    @Published var registers: String
    @Published var memoryAddress = "000000"
    @Published var memoryCount = "16"
    @Published var memoryDump = ""
    @Published var binaryLoadAddress = "008000"
    @Published var stepCount = "1"
    @Published var runLimit = "1000"
    @Published var breakpointAddress = "008000"
    @Published var breakpoints = "No breakpoints"
    @Published var commandText = ""
    @Published private(set) var logText = ""

    private let parser = IIGSDebuggerCommandParser()
    private let session = IIGSDebuggerSession()

    init() {
        self.registers = session.formatRegisters()
        refreshMemory()
        append("IIGSDebugger ready")
    }

    func loadROM(from url: URL) {
        do {
            let bytes = try Data(contentsOf: url)
            try session.loadROM(bytes: Array(bytes))
            let output = try session.execute(.reset(.cold))
            append("Loaded ROM \(url.lastPathComponent)")
            append(output)
            refreshAll()
        } catch {
            append(error, prefix: "ROM load failed")
        }
    }

    func loadBinary(from url: URL) {
        do {
            let address = try parser.parseAddress(binaryLoadAddress)
            let bytes = try Data(contentsOf: url)
            session.loadBinary(Array(bytes), at: address)
            append("Loaded \(bytes.count) byte(s) at \(formatAddress(address)) from \(url.lastPathComponent)")
            refreshAll()
        } catch {
            append(error, prefix: "Binary load failed")
        }
    }

    func reset(_ kind: IIGSResetKind = .cold) {
        perform(.reset(kind))
    }

    func step() {
        perform(.step(parsedPositiveInt(stepCount, defaultValue: 1)))
    }

    func run() {
        perform(.run(parsedPositiveInt(runLimit, defaultValue: 1_000)))
    }

    func runCycles() {
        perform(.runCycles(parsedPositiveInt(runLimit, defaultValue: 1_000)))
    }

    func addBreakpoint() {
        do {
            perform(.addBreakpoint(try parser.parseAddress(breakpointAddress)))
        } catch {
            append(error, prefix: "Breakpoint failed")
        }
    }

    func clearBreakpoint() {
        do {
            perform(.removeBreakpoint(try parser.parseAddress(breakpointAddress)))
        } catch {
            append(error, prefix: "Breakpoint failed")
        }
    }

    func clearAllBreakpoints() {
        for address in session.breakpoints {
            perform(.removeBreakpoint(address), shouldLog: false)
        }
        append("Cleared all breakpoints")
        refreshAll()
    }

    func refreshMemory() {
        do {
            let address = try parser.parseAddress(memoryAddress)
            let count = parsedPositiveInt(memoryCount, defaultValue: 16)
            memoryDump = try session.execute(.readMemory(address, count))
        } catch {
            memoryDump = "Memory read failed: \(describe(error))"
        }
    }

    func runCommand() {
        let line = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        commandText = ""

        do {
            guard let command = try parser.parse(line) else { return }
            if command == .quit {
                append("quit is handled by IIGSDebuggerCLI")
                return
            }
            perform(command)
        } catch {
            append(error, prefix: "Command failed")
        }
    }

    func refreshAll() {
        registers = session.formatRegisters()
        refreshMemory()
        breakpoints = (try? session.execute(.listBreakpoints)) ?? "No breakpoints"
    }

    private func perform(_ command: IIGSDebuggerCommand, shouldLog: Bool = true) {
        do {
            let output = try session.execute(command)
            if shouldLog {
                append(output)
            }
            refreshAll()
        } catch {
            append(error, prefix: "Command failed")
            refreshAll()
        }
    }

    private func parsedPositiveInt(_ text: String, defaultValue: Int) -> Int {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines), radix: 10), value > 0 else {
            return defaultValue
        }
        return value
    }

    private func append(_ line: String) {
        if logText.isEmpty {
            logText = line
        } else {
            logText += "\n" + line
        }
    }

    private func append(_ error: Error, prefix: String) {
        append("\(prefix): \(describe(error))")
    }

    private func describe(_ error: Error) -> String {
        if let debuggerError = error as? IIGSDebuggerError {
            return debuggerError.description
        }
        if let romError = error as? IIGSROMError {
            return romError.description
        }
        if let cpuError = error as? CPUError {
            return cpuError.description
        }
        return String(describing: error)
    }

    private func formatAddress(_ address: UInt32) -> String {
        let text = String(address & 0x00FF_FFFF, radix: 16, uppercase: true)
        return "$" + String(repeating: "0", count: Swift.max(0, 6 - text.count)) + text
    }
}
