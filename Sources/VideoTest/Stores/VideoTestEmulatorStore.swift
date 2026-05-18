import Foundation
import IIGSCore

@MainActor
final class VideoTestEmulatorStore: ObservableObject {
    @Published private(set) var videoFrame = IIGSVideoFrame(width: 1, height: 1, pixels: [.black])
    @Published private(set) var emulatorFPS = "0.00 fps"
    @Published private(set) var uiFPS = "0.00 fps"
    @Published private(set) var errorMessage: String?

    private let runner = VideoTestEmulatorRunner()
    private var started = false
    private var statsDate = Date()
    private var statsCycleCount: UInt64 = 0
    private var uiFrameTicks = 0

    var windowTitle: String {
        "VideoTest - EM \(emulatorFPS) - UI \(uiFPS)"
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
    }

    private func updateStats(cycleCount: UInt64) {
        let now = Date()
        let elapsed = now.timeIntervalSince(statsDate)
        guard elapsed >= 1 else {
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
}
