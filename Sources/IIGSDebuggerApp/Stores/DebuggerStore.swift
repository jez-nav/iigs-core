import Foundation
import IIGSCore

@MainActor
final class DebuggerStore: ObservableObject {
    @Published var snapshot: IIGSDebuggerSnapshot
    @Published var memoryBank = "00"
    @Published var memoryRows: [IIGSDebuggerMemoryRow] = []
    @Published var binaryLoadAddress = "008000"
    @Published var stepCount = "1"
    @Published var runLimit = "1000"
    @Published var breakpointAddress = "008000"
    @Published var breakpoints = "No breakpoints"
    @Published var commandText = ""
    @Published private(set) var logText = ""
    @Published private(set) var emulatorFPS = "0.00 fps"
    @Published private(set) var uiFPS = "0.00 fps"
    @Published private(set) var elapsedSinceReset = "00:00:00.0"
    @Published private(set) var hostMouseX: Int?
    @Published private(set) var hostMouseY: Int?
    @Published private(set) var displayMouseX: Int?
    @Published private(set) var displayMouseY: Int?

    private let parser: IIGSDebuggerCommandParser
    private let session: IIGSDebuggerSession
    private var resetDate: Date
    private var statsDate: Date
    private var statsCycleCount: UInt64
    private var uiFrameTicks = 0

    init(session: IIGSDebuggerSession = IIGSDebuggerSession()) {
        self.parser = IIGSDebuggerCommandParser()
        self.session = session
        self.snapshot = session.snapshot()
        let now = Date()
        self.resetDate = now
        self.statsDate = now
        self.statsCycleCount = session.snapshot().timing.cycles
        refreshMemoryRows()
        append("IIGSDebugger ready")
    }

    func loadROM(from url: URL) {
        do {
            let bytes = try Data(contentsOf: url)
            try session.loadROM(bytes: Array(bytes))
            let output = try session.execute(.reset(.cold))
            resetDate = Date()
            resetStatsWindow()
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
        resetDate = Date()
        resetStatsWindow()
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

    func refreshMemoryRows() {
        guard let bank = parseBank(memoryBank) else {
            return
        }
        memoryRows = session.memoryRows(bank: bank, startOffset: 0, rowCount: 0x10000 / IIGSDebuggerMemoryRow.bytesPerRow)
    }

    func updateMemoryBank() {
        guard let bank = parseBank(memoryBank) else {
            return
        }
        memoryBank = String(formatHex: UInt32(bank), width: 2)
        refreshMemoryRows()
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
        snapshot = session.snapshot()
        refreshMemoryRows()
        breakpoints = (try? session.execute(.listBreakpoints)) ?? "No breakpoints"
    }

    func noteUIRefresh() {
        uiFrameTicks += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(statsDate)
        elapsedSinceReset = Self.formatElapsed(now.timeIntervalSince(resetDate))
        guard elapsed >= 1 else {
            return
        }

        snapshot = session.snapshot()
        let cycleDelta = snapshot.timing.cycles - statsCycleCount
        let emulatedFrames = Double(cycleDelta) / Double(IIGSVideoTiming.cyclesPerFrame)
        emulatorFPS = String(format: "%.2f fps", emulatedFrames / elapsed)
        uiFPS = String(format: "%.2f fps", Double(uiFrameTicks) / elapsed)
        statsDate = now
        statsCycleCount = snapshot.timing.cycles
        uiFrameTicks = 0
    }

    func updateHostMouse(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let clampedX = min(max(0, x), max(0, width))
        let clampedY = min(max(0, y), max(0, height))
        hostMouseX = Int(clampedX.rounded())
        hostMouseY = Int(clampedY.rounded())
        displayMouseX = width > 0 ? Int((clampedX / width * 639).rounded()) : nil
        displayMouseY = height > 0 ? Int((clampedY / height * 199).rounded()) : nil
    }

    func clearHostMouse() {
        hostMouseX = nil
        hostMouseY = nil
        displayMouseX = nil
        displayMouseY = nil
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

    private func parseBank(_ text: String) -> UInt8? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "0X", with: "")
        return UInt8(value, radix: 16)
    }

    private func resetStatsWindow() {
        let now = Date()
        statsDate = now
        statsCycleCount = session.snapshot().timing.cycles
        uiFrameTicks = 0
        emulatorFPS = "0.00 fps"
        uiFPS = "0.00 fps"
        elapsedSinceReset = "00:00:00.0"
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
        "$" + String(formatHex: address & 0x00FF_FFFF, width: 6)
    }

    private static func formatElapsed(_ interval: TimeInterval) -> String {
        let tenths = Int((interval * 10).rounded(.down))
        let hours = tenths / 36_000
        let minutes = (tenths / 600) % 60
        let seconds = (tenths / 10) % 60
        let fraction = tenths % 10
        return String(format: "%02d:%02d:%02d.%d", hours, minutes, seconds, fraction)
    }
}

private extension String {
    init(formatHex value: UInt32, width: Int) {
        let text = String(value, radix: 16, uppercase: true)
        self = String(repeating: "0", count: Swift.max(0, width - text.count)) + text
    }
}
