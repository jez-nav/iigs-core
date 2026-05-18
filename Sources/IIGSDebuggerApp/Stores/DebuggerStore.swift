import AppKit
import Dispatch
import Foundation
import IIGSCore

enum DebuggerRunState: Equatable {
    case paused
    case running
    case stopped(String)
}

private final class LiveDebuggerSessionBox: @unchecked Sendable {
    let session: IIGSDebuggerSession

    init(_ session: IIGSDebuggerSession) {
        self.session = session
    }
}

private final class LiveRunControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

@MainActor
final class DebuggerStore: ObservableObject {
    @Published var snapshot: IIGSDebuggerSnapshot
    @Published private(set) var runState: DebuggerRunState = .paused
    @Published private(set) var videoFrame: IIGSVideoFrame
    @Published var memoryBank = "00"
    @Published var memoryRows: [IIGSDebuggerMemoryRow] = []
    @Published var memoryWriteAddress = "002000"
    @Published var memoryWriteValue = "00"
    @Published var disassemblyStart = "008000"
    @Published var disassemblyRows: [IIGSDisassembledInstruction] = []
    @Published var binaryLoadAddress = "008000"
    @Published var stepCount = "1"
    @Published var runLimit = "1000"
    @Published var breakpointAddress = "008000"
    @Published var registerName = "PC"
    @Published var registerValue = "8000"
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
    @Published private(set) var displayHasKeyboardFocus = false

    private let parser: IIGSDebuggerCommandParser
    private let session: IIGSDebuggerSession
    private let liveSession: LiveDebuggerSessionBox
    private var resetDate: Date
    private var statsDate: Date
    private var statsCycleCount: UInt64
    private var uiFrameTicks = 0
    private var liveRunControl: LiveRunControl?
    private let liveRunQueue = DispatchQueue(label: "dev.local.IIGSDebugger.liveRun", qos: .userInitiated)
    private var lastDisplayMouseX: Int?
    private var lastDisplayMouseY: Int?
    private var lastMouseButtonDown = false
    private static let livePublishInterval: TimeInterval = 1.0 / 30.0
    private static let liveRunInstructionLimit = 2_000_000
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    init(session: IIGSDebuggerSession = IIGSDebuggerSession()) {
        self.parser = IIGSDebuggerCommandParser()
        self.session = session
        self.liveSession = LiveDebuggerSessionBox(session)
        self.snapshot = session.snapshot()
        self.videoFrame = session.renderVideoFrame()
        let now = Date()
        self.resetDate = now
        self.statsDate = now
        self.statsCycleCount = session.snapshot().timing.cycles
        refreshMemoryRows()
        refreshDisassemblyRows()
        append("IIGSDebugger ready")
    }

    var localROM1URL: URL? {
        let candidates = [
            Self.repositoryRoot.appendingPathComponent("LocalAssets/ROMs/Apple_IIGS_ROM01.bin"),
            Self.repositoryRoot.appendingPathComponent("ROM01"),
            Self.repositoryRoot.appendingPathComponent("ROM1"),
            Self.repositoryRoot.appendingPathComponent("Apple_IIGS_ROM01.bin"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop/AppleIIGS/ROM1"),
        ]
        return candidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    var canLoadLocalROM1: Bool {
        localROM1URL != nil
    }

    func loadLocalROM1() {
        guard let url = localROM1URL else {
            append("Local ROM1 not found")
            return
        }
        loadROM(from: url)
    }

    func bootLocalROM1() {
        guard let url = localROM1URL else {
            append("Local ROM1 not found")
            return
        }
        loadROM(from: url)
        run()
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
        pause()
        perform(.reset(kind))
        resetDate = Date()
        resetStatsWindow()
    }

    func step() {
        pause()
        perform(.step(parsedPositiveInt(stepCount, defaultValue: 1)))
    }

    func run() {
        startContinuousRun()
    }

    func startContinuousRun() {
        if case .running = runState {
            return
        }
        let control = LiveRunControl()
        liveRunControl = control
        runState = .running
        append("Running")
        startLiveRunLoop(control: control)
    }

    func pause() {
        if case .running = runState {
            append("Paused")
        }
        liveRunControl?.cancel()
        liveRunControl = nil
        runState = .paused
    }

    func runContinuousTick(now: Date = Date()) {
        // Continuous execution is owned by startLiveRunLoop(control:).  The UI timer calls
        // this to preserve the old view contract, but emulation no longer depends on UI ticks.
    }

    func runCycles() {
        pause()
        perform(.runCycles(parsedPositiveInt(runLimit, defaultValue: 1_000)))
    }

    func writeMemoryByte() {
        do {
            let address = try parser.parseAddress(memoryWriteAddress)
            let value = try parser.parseByte(memoryWriteValue)
            perform(.writeMemory(address, value))
        } catch {
            append(error, prefix: "Memory write failed")
        }
    }

    func writeRegister() {
        do {
            let value = try parser.parseAddress(registerValue)
            perform(.writeRegister(registerName, value))
        } catch {
            append(error, prefix: "Register write failed")
        }
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

    func refreshDisassemblyRows() {
        do {
            let address = try parser.parseAddress(disassemblyStart)
            disassemblyStart = formatAddress(address).replacingOccurrences(of: "$", with: "")
            disassemblyRows = session.disassemblyRows(startingAt: address, count: 48)
        } catch {
            append(error, prefix: "Disassembly failed")
        }
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
        videoFrame = session.renderVideoFrame()
        refreshMemoryRows()
        refreshDisassemblyRows()
        breakpoints = (try? session.execute(.listBreakpoints)) ?? "No breakpoints"
    }

    func refreshLive() {
        snapshot = session.snapshot()
        videoFrame = session.renderVideoFrame()
    }

    func noteUIRefresh() {
        let now = Date()
        let elapsed = now.timeIntervalSince(statsDate)
        elapsedSinceReset = Self.formatElapsed(now.timeIntervalSince(resetDate))
        guard elapsed >= 1 else {
            return
        }

        let cycleDelta = snapshot.timing.cycles - statsCycleCount
        let emulatedFrames = Double(cycleDelta) / Double(IIGSVideoTiming.cyclesPerFrame)
        emulatorFPS = String(format: "%.2f fps", emulatedFrames / elapsed)
        uiFPS = String(format: "%.2f fps", Double(uiFrameTicks) / elapsed)
        statsDate = now
        statsCycleCount = snapshot.timing.cycles
        uiFrameTicks = 0
    }

    private func startLiveRunLoop(control: LiveRunControl) {
        let sessionBox = liveSession
        let cycleBudget = IIGSVideoTiming.cyclesPerFrame
        let instructionLimit = Self.liveRunInstructionLimit
        let publishInterval = Self.livePublishInterval
        let frameInterval = 1.0 / IIGSVideoTiming.nominalFramesPerSecond

        liveRunQueue.async {
            let session = sessionBox.session
            var nextPublish = Date()
            var nextFrameDeadline = Date().addingTimeInterval(frameInterval)

            while !control.isCancelled {
                let outcome: Result<IIGSMachineRunResult, Error>
                do {
                    outcome = .success(try session.runLiveCycleBatch(cycleLimit: cycleBudget, instructionLimit: instructionLimit))
                } catch {
                    outcome = .failure(error)
                }

                switch outcome {
                case let .success(result):
                    if result.stopReason != .cycleLimitReached && result.stopReason != .instructionLimitReached {
                        let latestSnapshot = session.snapshot()
                        let latestFrame = session.renderVideoFrame()
                        DispatchQueue.main.async { [weak self] in
                            self?.finishLiveRunStop(result, snapshot: latestSnapshot, frame: latestFrame)
                        }
                        return
                    }
                case let .failure(error):
                    DispatchQueue.main.async { [weak self] in
                        self?.finishLiveRunFailure(error)
                    }
                    return
                }

                let now = Date()
                if now >= nextPublish {
                    let latestSnapshot = session.snapshot()
                    let latestFrame = session.renderVideoFrame()
                    DispatchQueue.main.async { [weak self] in
                        self?.publishLiveFrame(snapshot: latestSnapshot, frame: latestFrame)
                    }
                    nextPublish = now.addingTimeInterval(publishInterval)
                }

                let sleepDuration = nextFrameDeadline.timeIntervalSinceNow
                if sleepDuration > 0 {
                    Thread.sleep(forTimeInterval: sleepDuration)
                    nextFrameDeadline = nextFrameDeadline.addingTimeInterval(frameInterval)
                } else {
                    nextFrameDeadline = Date().addingTimeInterval(frameInterval)
                }
            }
        }
    }

    private func publishLiveFrame(snapshot latestSnapshot: IIGSDebuggerSnapshot, frame latestFrame: IIGSVideoFrame) {
        guard case .running = runState else {
            return
        }
        snapshot = latestSnapshot
        videoFrame = latestFrame
        uiFrameTicks += 1
    }

    private func finishLiveRunStop(_ result: IIGSMachineRunResult, snapshot latestSnapshot: IIGSDebuggerSnapshot, frame latestFrame: IIGSVideoFrame) {
        guard case .running = runState else {
            return
        }
        snapshot = latestSnapshot
        videoFrame = latestFrame
        runState = .stopped(describe(result.stopReason))
        liveRunControl?.cancel()
        liveRunControl = nil
        append("Stopped: \(describe(result.stopReason)) PC=\(formatAddress(result.finalAddress))")
        refreshAll()
    }

    private func finishLiveRunFailure(_ error: Error) {
        runState = .stopped("error")
        liveRunControl?.cancel()
        liveRunControl = nil
        append(error, prefix: "Run failed")
        refreshAll()
    }

    func updateDisplayMouse(hostX: Int, hostY: Int, displayX: Int, displayY: Int, buttonDown: Bool) {
        hostMouseX = hostX
        hostMouseY = hostY
        displayMouseX = displayX
        displayMouseY = displayY

        if let lastDisplayMouseX, let lastDisplayMouseY {
            let dx = clampMouseDelta(displayX - lastDisplayMouseX)
            let dy = clampMouseDelta(displayY - lastDisplayMouseY)
            if dx != 0 || dy != 0 || buttonDown != lastMouseButtonDown {
                session.moveMouse(dx: dx, dy: dy, buttonDown: buttonDown)
                snapshot = session.snapshot()
            }
        }

        lastDisplayMouseX = displayX
        lastDisplayMouseY = displayY
        lastMouseButtonDown = buttonDown
    }

    func clearHostMouse() {
        hostMouseX = nil
        hostMouseY = nil
        displayMouseX = nil
        displayMouseY = nil
        lastDisplayMouseX = nil
        lastDisplayMouseY = nil
        lastMouseButtonDown = false
    }

    func setDisplayFocus(_ focused: Bool) {
        displayHasKeyboardFocus = focused
    }

    func handleKeyDown(characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        if let ascii = appleIIASCII(from: characters, keyCode: keyCode) {
            session.injectKeyboardInput(
                ascii: ascii,
                keyCode: UInt8(truncatingIfNeeded: keyCode),
                modifiers: adbModifiers(from: modifiers),
                isKeyUp: false
            )
        } else {
            session.injectKeyboardInput(
                ascii: nil,
                keyCode: UInt8(truncatingIfNeeded: keyCode),
                modifiers: adbModifiers(from: modifiers),
                isKeyUp: false
            )
        }
        snapshot = session.snapshot()
    }

    func handleKeyUp(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        session.injectKeyboardInput(
            ascii: nil,
            keyCode: UInt8(truncatingIfNeeded: keyCode),
            modifiers: adbModifiers(from: modifiers),
            isKeyUp: true
        )
        snapshot = session.snapshot()
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

    private func describe(_ reason: IIGSMachineStopReason) -> String {
        switch reason {
        case .instructionLimitReached:
            return "instruction limit"
        case .cycleLimitReached:
            return "cycle limit"
        case let .breakpoint(address):
            return "breakpoint \(formatAddress(address))"
        case .stopped:
            return "stopped"
        case .waiting:
            return "waiting"
        }
    }

    private func clampMouseDelta(_ value: Int) -> Int8 {
        Int8(max(Int(Int8.min), min(Int(Int8.max), value)))
    }

    private func appleIIASCII(from characters: String, keyCode: UInt16) -> UInt8? {
        switch keyCode {
        case 36, 76:
            return 0x0D
        case 48:
            return 0x09
        case 51, 117:
            return 0x7F
        case 53:
            return 0x1B
        case 123:
            return 0x08
        case 124:
            return 0x15
        case 125:
            return 0x0A
        case 126:
            return 0x0B
        default:
            guard let scalar = characters.unicodeScalars.first, scalar.value <= 0x7F else {
                return nil
            }
            return UInt8(scalar.value)
        }
    }

    private func adbModifiers(from flags: NSEvent.ModifierFlags) -> IIGSADBModifiers {
        var modifiers: IIGSADBModifiers = []
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.capsLock) {
            modifiers.insert(.capsLock)
        }
        return modifiers
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
