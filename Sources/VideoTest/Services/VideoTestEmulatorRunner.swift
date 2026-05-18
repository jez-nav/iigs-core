import Foundation
import IIGSCore

private final class VideoTestRunControl: @unchecked Sendable {
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

final class VideoTestEmulatorRunner {
    private let queue = DispatchQueue(label: "dev.local.VideoTest.emulator", qos: .userInteractive)
    private var control: VideoTestRunControl?

    func start(
        romBytes: [UInt8],
        frameHandler: @escaping @MainActor @Sendable (IIGSVideoFrame, UInt64) -> Void,
        errorHandler: @escaping @MainActor @Sendable (String) -> Void
    ) {
        stop()
        let control = VideoTestRunControl()
        self.control = control

        queue.async {
            let machine = IIGSMachine()

            do {
                try machine.installROM(bytes: romBytes)
                machine.reset(.cold)

                let cycleBudget = IIGSVideoTiming.cyclesPerFrame
                let instructionLimit = 2_000_000
                let frameInterval = 1.0 / IIGSVideoTiming.nominalFramesPerSecond
                var nextFrameDeadline = Date().addingTimeInterval(frameInterval)

                while !control.isCancelled {
                    let result = try machine.runForCycles(cycleBudget, instructionLimit: instructionLimit)
                    let frame = IIGSVideoRenderer.renderFrame(from: machine.memory)
                    let cycleCount = machine.memory.cycleCount

                    Task { @MainActor in
                        frameHandler(frame, cycleCount)
                    }

                    if result.stopReason != .cycleLimitReached && result.stopReason != .instructionLimitReached {
                        Task { @MainActor in
                            errorHandler("Emulator stopped: \(result.stopReason)")
                        }
                        return
                    }

                    let sleepDuration = nextFrameDeadline.timeIntervalSinceNow
                    if sleepDuration > 0 {
                        Thread.sleep(forTimeInterval: sleepDuration)
                        nextFrameDeadline = nextFrameDeadline.addingTimeInterval(frameInterval)
                    } else {
                        nextFrameDeadline = Date().addingTimeInterval(frameInterval)
                    }
                }
            } catch {
                Task { @MainActor in
                    errorHandler("Emulator failed: \(error)")
                }
            }
        }
    }

    func stop() {
        control?.cancel()
        control = nil
    }
}
