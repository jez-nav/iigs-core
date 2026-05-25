import Foundation
import IIGSCore

@MainActor
final class ADBTestEmulatorStore: ObservableObject {
    @Published private(set) var videoFrame = IIGSVideoFrame(width: 1, height: 1, pixels: [.black])
    @Published private(set) var emulatorFPS = "0.00 fps"
    @Published private(set) var uiFPS = "0.00 fps"
    @Published private(set) var displayHasKeyboardFocus = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var inputStatus = "Ready"

    private let runner = ADBTestEmulatorRunner()
    private var started = false
    private var statsDate = Date()
    private var statsCycleCount: UInt64 = 0
    private var uiFrameTicks = 0

    var windowTitle: String {
        "ADBTest - EM \(emulatorFPS) - UI \(uiFPS)"
    }

    func start() {
        guard !started else {
            return
        }
        started = true

        guard let romURL = ROMLocator.locateROM1() else {
            errorMessage = "ROM1 not found"
            return
        }

        do {
            let romBytes = try Array(Data(contentsOf: romURL))
            resetStats()
            runner.start(
                romBytes: romBytes,
                frameHandler: { [weak self] frame, cycleCount in
                    self?.publish(frame: frame, cycleCount: cycleCount)
                },
                errorHandler: { [weak self] message in
                    self?.errorMessage = message
                }
            )
        } catch {
            errorMessage = "ROM1 load failed: \(error)"
        }
    }

    func stop() {
        runner.stop()
    }

    func setDisplayFocus(_ focused: Bool) {
        if !focused {
            runner.releaseKeyboard()
        }
        displayHasKeyboardFocus = focused
    }

    func appBecameActive() {
        displayHasKeyboardFocus = true
    }

    func appBecameInactive() {
        setDisplayFocus(false)
    }

    func handleKeyEvent(_ event: IIGSHostKeyEvent) {
        runner.enqueue(event)
    }

    func sendResetKey() {
        runner.keyboardReset()
        inputStatus = "Control-Reset requested"
    }

    func sendControlResetKey() {
        runner.keyboardReset()
        inputStatus = "Control-Reset requested"
    }

    func sendControlPanelResetKey() {
        runner.keyboardReset(modifiers: .option)
        inputStatus = "Option-Reset requested"
    }

    func typeBasicSmokeTest() {
        runner.keyboardReset()
        inputStatus = "Control-Reset requested; typing shortly"
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.typeText(Self.basicSmokeTest)
        }
    }

    private func publish(frame: IIGSVideoFrame, cycleCount: UInt64) {
        videoFrame = frame
        uiFrameTicks += 1
        updateStats(cycleCount: cycleCount)
    }

    private func resetStats() {
        let now = Date()
        statsDate = now
        statsCycleCount = 0
        uiFrameTicks = 0
        emulatorFPS = "0.00 fps"
        uiFPS = "0.00 fps"
        errorMessage = nil
        inputStatus = "Ready"
    }

    private func updateStats(cycleCount: UInt64) {
        let now = Date()
        let elapsed = now.timeIntervalSince(statsDate)
        guard elapsed >= 1 else {
            return
        }

        guard cycleCount >= statsCycleCount else {
            statsDate = now
            statsCycleCount = cycleCount
            uiFrameTicks = 0
            emulatorFPS = "0.00 fps"
            uiFPS = "0.00 fps"
            return
        }

        let cycleDelta = cycleCount - statsCycleCount
        let emulatedFrames = Double(cycleDelta) / Double(IIGSVideoTiming.cyclesPerFrame)
        emulatorFPS = String(format: "%.2f fps", emulatedFrames / elapsed)
        uiFPS = String(format: "%.2f fps", Double(uiFrameTicks) / elapsed)
        statsDate = now
        statsCycleCount = cycleCount
        uiFrameTicks = 0
    }

    private func typeText(_ text: String) {
        let groups = MacKeyboardInputMapper.textInputEventGroups(for: text)
        guard !groups.isEmpty else {
            inputStatus = "No text to type"
            return
        }

        inputStatus = "Typing BASIC smoke test"

        Task { @MainActor [weak self] in
            for events in groups {
                guard let self else {
                    return
                }
                self.enqueue(events)
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            self?.inputStatus = "BASIC smoke test sent"
        }
    }

    private func enqueue(_ events: [IIGSHostKeyEvent]) {
        for event in events {
            handleKeyEvent(event)
        }
    }

    private static let basicSmokeTest = """
    10 TEXT
    20 HOME
    30 PRINT "ADB OK"
    40 FOR I = 1 TO 3
    50 PRINT I
    60 NEXT I
    RUN

    """
}
