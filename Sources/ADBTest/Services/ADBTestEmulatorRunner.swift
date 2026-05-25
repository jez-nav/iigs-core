import Foundation
import IIGSCore

private final class ADBTestRunControl: @unchecked Sendable {
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

private final class ADBTestInputQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [ADBTestEmulatorCommand] = []

    func enqueue(_ event: IIGSHostKeyEvent) {
        enqueue(.keyEvent(event))
    }

    func enqueue(_ command: ADBTestEmulatorCommand) {
        lock.lock()
        pending.append(command)
        lock.unlock()
    }

    func drain() -> [ADBTestEmulatorCommand] {
        lock.lock()
        defer { lock.unlock() }
        let commands = pending
        pending.removeAll(keepingCapacity: true)
        return commands
    }
}

private final class ADBTestFrameDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingFrame: (frame: IIGSVideoFrame, cycleCount: UInt64)?
    private var deliveryScheduled = false

    func deliver(
        frame: IIGSVideoFrame,
        cycleCount: UInt64,
        unlessCancelled control: ADBTestRunControl,
        to frameHandler: @escaping @MainActor @Sendable (IIGSVideoFrame, UInt64) -> Void
    ) {
        lock.lock()
        pendingFrame = (frame, cycleCount)
        guard !deliveryScheduled else {
            lock.unlock()
            return
        }
        deliveryScheduled = true
        lock.unlock()

        Task { @MainActor [weak self] in
            guard let self,
                  let pendingFrame = self.takePendingFrame(),
                  !control.isCancelled
            else {
                return
            }
            frameHandler(pendingFrame.frame, pendingFrame.cycleCount)
        }
    }

    private func takePendingFrame() -> (frame: IIGSVideoFrame, cycleCount: UInt64)? {
        lock.lock()
        defer { lock.unlock() }
        let frame = pendingFrame
        pendingFrame = nil
        deliveryScheduled = false
        return frame
    }
}

private enum ADBTestEmulatorCommand: Sendable {
    case keyEvent(IIGSHostKeyEvent)
    case reset(IIGSResetKind)
    case keyboardReset(modifiers: IIGSADBModifiers)
    case releaseKeyboard
}

final class ADBTestEmulatorRunner {
    private let queue = DispatchQueue(label: "dev.local.ADBTest.emulator", qos: .userInteractive)
    private let inputQueue = ADBTestInputQueue()
    private var control: ADBTestRunControl?

    func enqueue(_ event: IIGSHostKeyEvent) {
        inputQueue.enqueue(event)
    }

    func reset(_ kind: IIGSResetKind) {
        inputQueue.enqueue(.reset(kind))
    }

    func keyboardReset(modifiers: IIGSADBModifiers = .control) {
        inputQueue.enqueue(.keyboardReset(modifiers: modifiers))
    }

    func releaseKeyboard() {
        inputQueue.enqueue(.releaseKeyboard)
    }

    func start(
        romBytes: [UInt8],
        frameHandler: @escaping @MainActor @Sendable (IIGSVideoFrame, UInt64) -> Void,
        errorHandler: @escaping @MainActor @Sendable (String) -> Void
    ) {
        stop()
        let control = ADBTestRunControl()
        self.control = control

        queue.async { [inputQueue] in
            let machine = IIGSMachine()
            let frameDelivery = ADBTestFrameDelivery()
            var pressedKeyCodes = Set<UInt8>()

            do {
                try machine.installROM(bytes: romBytes)
                machine.reset(.cold)

                let cycleBudget = IIGSVideoTiming.cyclesPerFrame
                let instructionLimit = 2_000_000
                let frameInterval = 1.0 / IIGSVideoTiming.nominalFramesPerSecond
                var nextFrameDeadline = Date().addingTimeInterval(frameInterval)

                while !control.isCancelled {
                    for command in inputQueue.drain() {
                        switch command {
                        case let .keyEvent(event):
                            if event.isControlResetKeyDown {
                                machine.reset(.warm)
                                machine.memory.adbController.setModifiers(event.modifiers)
                                pressedKeyCodes.removeAll()
                                nextFrameDeadline = Date().addingTimeInterval(frameInterval)
                            } else {
                                updatePressedKeys(&pressedKeyCodes, for: event)
                                event.apply(to: machine)
                            }
                        case let .reset(kind):
                            machine.reset(kind)
                            pressedKeyCodes.removeAll()
                            nextFrameDeadline = Date().addingTimeInterval(frameInterval)
                        case let .keyboardReset(modifiers):
                            machine.reset(.warm)
                            machine.memory.adbController.setModifiers(modifiers)
                            pressedKeyCodes.removeAll()
                            nextFrameDeadline = Date().addingTimeInterval(frameInterval)
                        case .releaseKeyboard:
                            releasePressedKeys(&pressedKeyCodes, in: machine)
                        }
                    }

                    let result = try machine.runForCycles(cycleBudget, instructionLimit: instructionLimit)
                    let frame = IIGSVideoRenderer.renderFrame(from: machine.memory)
                    let cycleCount = machine.memory.cycleCount

                    frameDelivery.deliver(
                        frame: frame,
                        cycleCount: cycleCount,
                        unlessCancelled: control,
                        to: frameHandler
                    )

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

private func updatePressedKeys(_ pressedKeyCodes: inout Set<UInt8>, for event: IIGSHostKeyEvent) {
    if event.isKeyUp {
        pressedKeyCodes.remove(event.keyCode)
    } else {
        pressedKeyCodes.insert(event.keyCode)
    }
}

private func releasePressedKeys(_ pressedKeyCodes: inout Set<UInt8>, in machine: IIGSMachine) {
    machine.memory.adbController.setModifiers([])
    for keyCode in pressedKeyCodes.sorted() {
        machine.queueKeyboardEvent(keyCode: keyCode, isKeyUp: true)
    }
    pressedKeyCodes.removeAll()
}
