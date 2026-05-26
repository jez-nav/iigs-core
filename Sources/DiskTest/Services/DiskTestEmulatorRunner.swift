import Foundation
import IIGSCore

private final class DiskTestRunControl: @unchecked Sendable {
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

private final class DiskTestInputQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [DiskTestEmulatorCommand] = []

    func enqueue(_ event: IIGSHostKeyEvent) {
        enqueue(.keyEvent(event))
    }

    func enqueue(_ event: IIGSHostMouseEvent) {
        enqueue(.mouseEvent(event))
    }

    func syncMouse(displayX: Int, displayY: Int, buttonDown: Bool) {
        enqueue(.mouseSync(displayX: displayX, displayY: displayY, buttonDown: buttonDown))
    }

    func enqueue(_ command: DiskTestEmulatorCommand) {
        lock.lock()
        pending.append(command)
        lock.unlock()
    }

    func drain() -> [DiskTestEmulatorCommand] {
        lock.lock()
        defer { lock.unlock() }
        let commands = pending
        pending.removeAll(keepingCapacity: true)
        return commands
    }
}

private final class DiskTestFrameDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingFrame: (frame: IIGSVideoFrame, cycleCount: UInt64)?
    private var deliveryScheduled = false

    func deliver(
        frame: IIGSVideoFrame,
        cycleCount: UInt64,
        unlessCancelled control: DiskTestRunControl,
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

private enum DiskTestEmulatorCommand: Sendable {
    case keyEvent(IIGSHostKeyEvent)
    case mouseEvent(IIGSHostMouseEvent)
    case mouseSync(displayX: Int, displayY: Int, buttonDown: Bool)
    case powerCycle
    case reset(IIGSResetKind)
    case keyboardReset(modifiers: IIGSADBModifiers)
    case releaseKeyboard
    case mountDisk(url: URL, target: IIGSDiskMountTarget)
    case ejectDisk(target: IIGSDiskMountTarget)
}

final class DiskTestEmulatorRunner {
    private let queue = DispatchQueue(label: "dev.local.DiskTest.emulator", qos: .userInteractive)
    private let inputQueue = DiskTestInputQueue()
    private var control: DiskTestRunControl?

    func enqueue(_ event: IIGSHostKeyEvent) {
        inputQueue.enqueue(event)
    }

    func enqueue(_ event: IIGSHostMouseEvent) {
        inputQueue.enqueue(event)
    }

    func syncMouse(displayX: Int, displayY: Int, buttonDown: Bool) {
        inputQueue.syncMouse(displayX: displayX, displayY: displayY, buttonDown: buttonDown)
    }

    func reset(_ kind: IIGSResetKind) {
        inputQueue.enqueue(.reset(kind))
    }

    func powerCycle() {
        inputQueue.enqueue(.powerCycle)
    }

    func keyboardReset(modifiers: IIGSADBModifiers = .control) {
        inputQueue.enqueue(.keyboardReset(modifiers: modifiers))
    }

    func releaseKeyboard() {
        inputQueue.enqueue(.releaseKeyboard)
    }

    func mountDisk(url: URL, target: IIGSDiskMountTarget) {
        inputQueue.enqueue(.mountDisk(url: url, target: target))
    }

    func ejectDisk(target: IIGSDiskMountTarget) {
        inputQueue.enqueue(.ejectDisk(target: target))
    }

    func start(
        romBytes: [UInt8],
        batteryRAM: [UInt8]?,
        frameHandler: @escaping @MainActor @Sendable (IIGSVideoFrame, UInt64) -> Void,
        audioHandler: @escaping @Sendable (IIGSAudioBuffer) -> Void,
        audioResetHandler: @escaping @Sendable () -> Void,
        statusHandler: @escaping @MainActor @Sendable ([IIGSDiskMountTarget: IIGSMountedDiskInfo]) -> Void,
        batteryRAMHandler: @escaping @MainActor @Sendable ([UInt8]) -> Void,
        errorHandler: @escaping @MainActor @Sendable (String) -> Void
    ) {
        stop()
        let control = DiskTestRunControl()
        self.control = control

        queue.async { [inputQueue] in
            let machine = IIGSMachine()
            let frameDelivery = DiskTestFrameDelivery()
            var pressedKeyCodes = Set<UInt8>()

            do {
                try machine.installROM(bytes: romBytes)
                if let batteryRAM {
                    machine.memory.loadBatteryRAM(batteryRAM)
                }
                machine.reset(.cold)
                publishStatus(machine.mountedDiskImages, unlessCancelled: control, to: statusHandler)
                publishBatteryRAM(machine.memory.batteryRAMSnapshot, unlessCancelled: control, to: batteryRAMHandler)

                let cycleBudget = IIGSVideoTiming.cyclesPerFrame
                let instructionLimit = 2_000_000
                let frameInterval = 1.0 / IIGSVideoTiming.nominalFramesPerSecond
                var nextFrameDeadline = Date().addingTimeInterval(frameInterval)
                var lastBatteryRAMRevision = machine.memory.batteryRAMRevision
                #if DEBUG
                var diagnosticFrameIndex = 0
                #endif

                while !control.isCancelled {
                    for command in inputQueue.drain() {
                        switch command {
                        case let .keyEvent(event):
                            if event.isControlResetKeyDown {
                                machine.reset(.warm)
                                machine.memory.adbController.setModifiers(event.modifiers)
                                audioResetHandler()
                                pressedKeyCodes.removeAll()
                                nextFrameDeadline = Date().addingTimeInterval(frameInterval)
                            } else {
                                updatePressedKeys(&pressedKeyCodes, for: event)
                                event.apply(to: machine)
                            }
                        case let .mouseEvent(event):
                            event.apply(to: machine)
                        case let .mouseSync(displayX, displayY, buttonDown):
                            syncMachineMouse(displayX: displayX, displayY: displayY, buttonDown: buttonDown, in: machine)
                        case .powerCycle:
                            machine.powerCycle()
                            audioResetHandler()
                            publishStatus(machine.mountedDiskImages, unlessCancelled: control, to: statusHandler)
                            pressedKeyCodes.removeAll()
                            nextFrameDeadline = Date().addingTimeInterval(frameInterval)
                        case let .reset(kind):
                            machine.reset(kind)
                            audioResetHandler()
                            pressedKeyCodes.removeAll()
                            nextFrameDeadline = Date().addingTimeInterval(frameInterval)
                        case let .keyboardReset(modifiers):
                            machine.reset(.warm)
                            machine.memory.adbController.setModifiers(modifiers)
                            audioResetHandler()
                            pressedKeyCodes.removeAll()
                            nextFrameDeadline = Date().addingTimeInterval(frameInterval)
                        case .releaseKeyboard:
                            releasePressedKeys(&pressedKeyCodes, in: machine)
                        case let .mountDisk(url, target):
                            do {
                                _ = try machine.mountDiskImage(contentsOf: url, target: target)
                                publishStatus(machine.mountedDiskImages, unlessCancelled: control, to: statusHandler)
                            } catch {
                                publishError("Mount failed: \(error)", unlessCancelled: control, to: errorHandler)
                            }
                        case let .ejectDisk(target):
                            machine.ejectDisk(target: target)
                            publishStatus(machine.mountedDiskImages, unlessCancelled: control, to: statusHandler)
                        }
                    }

                    let result = try machine.runForCycles(cycleBudget, instructionLimit: instructionLimit)
                    let frame = IIGSVideoRenderer.renderFrame(from: machine.memory)
                    let audioBuffer = machine.memory.drainAudio()
                    if !audioBuffer.samples.isEmpty {
                        audioHandler(audioBuffer)
                    }
                    let cycleCount = machine.memory.cycleCount
                    #if DEBUG
                    diagnosticFrameIndex += 1
                    if diagnosticFrameIndex % 30 == 0 {
                        writeDiskTestDiagnostic(machine: machine, frame: frame, cycleCount: cycleCount)
                    }
                    #endif
                    let batteryRAMRevision = machine.memory.batteryRAMRevision
                    if batteryRAMRevision != lastBatteryRAMRevision {
                        lastBatteryRAMRevision = batteryRAMRevision
                        publishBatteryRAM(machine.memory.batteryRAMSnapshot, unlessCancelled: control, to: batteryRAMHandler)
                    }

                    frameDelivery.deliver(
                        frame: frame,
                        cycleCount: cycleCount,
                        unlessCancelled: control,
                        to: frameHandler
                    )

                    if result.stopReason != .cycleLimitReached && result.stopReason != .instructionLimitReached {
                        publishError("Emulator stopped: \(result.stopReason)", unlessCancelled: control, to: errorHandler)
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
                publishError("Emulator failed: \(error)", unlessCancelled: control, to: errorHandler)
            }
        }
    }

    func stop() {
        control?.cancel()
        control = nil
    }
}

private func syncMachineMouse(displayX: Int, displayY: Int, buttonDown: Bool, in machine: IIGSMachine) {
    let deltaX = displayX - Int(machine.memory.adbController.mouseX)
    let deltaY = displayY - Int(machine.memory.adbController.mouseY)
    let events = IIGSHostMouseEvent.events(
        deltaX: deltaX,
        deltaY: deltaY,
        buttonDown: buttonDown,
        includeStationaryEvent: true
    )

    for event in events {
        event.apply(to: machine)
    }
}

private func publishStatus(
    _ mountedDisks: [IIGSDiskMountTarget: IIGSMountedDiskInfo],
    unlessCancelled control: DiskTestRunControl,
    to statusHandler: @escaping @MainActor @Sendable ([IIGSDiskMountTarget: IIGSMountedDiskInfo]) -> Void
) {
    Task { @MainActor in
        guard !control.isCancelled else {
            return
        }
        statusHandler(mountedDisks)
    }
}

private func publishBatteryRAM(
    _ bytes: [UInt8],
    unlessCancelled control: DiskTestRunControl,
    to batteryRAMHandler: @escaping @MainActor @Sendable ([UInt8]) -> Void
) {
    Task { @MainActor in
        guard !control.isCancelled else {
            return
        }
        batteryRAMHandler(bytes)
    }
}

private func publishError(
    _ message: String,
    unlessCancelled control: DiskTestRunControl,
    to errorHandler: @escaping @MainActor @Sendable (String) -> Void
) {
    Task { @MainActor in
        guard !control.isCancelled else {
            return
        }
        errorHandler(message)
    }
}

#if DEBUG
private func writeDiskTestDiagnostic(machine: IIGSMachine, frame: IIGSVideoFrame, cycleCount: UInt64) {
    let textBytes = (0..<8)
        .map { String(format: "%02X", machine.memory.peek8(at: 0xE00400 + UInt32($0))) }
        .joined(separator: " ")
    let shrBytes = (0..<8)
        .map { String(format: "%02X", machine.memory.peek8(at: 0xE12000 + UInt32($0))) }
        .joined(separator: " ")
    let softSwitches = machine.memory.softSwitches
    let mode = softSwitches.videoControl & 0x80 != 0
        ? "shr"
        : (softSwitches.textMode ? "text" : (softSwitches.hires ? "hires" : "lores"))
    let registers = machine.cpu.registers
    let pc = String(format: "%02X:%04X", registers.programBank, registers.programCounter)
    let recentPCs = machine.recentProgramCounters.suffix(12)
        .map { String(format: "%06X", $0) }
        .joined(separator: " ")
    let iwmCounts = machine.memory.iwmController.debugAccessCounts
        .filter { key, _ in
            key.hasPrefix("data") || key.hasPrefix("status35") || key.hasPrefix("action35")
        }
        .sorted { lhs, rhs in lhs.key < rhs.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: " ")
    let line = String(
        format: """
        cycle=%llu pc=%@ a=%04X x=%04X y=%04X s=%04X d=%04X db=%02X p=%02X emu=%d wait=%d irq=%d
        mode=%@ text=%d mix=%d page2=%d hires=%d 80=%d vc=%02X txt=%02X border=%02X c035=%02X c036=%02X c041=%02X c046=%02X c023=%02X c023p=%02X frame=%dx%d
        recent=%@
        text0=%@
        shr0=%@
        iwm=%@
        
        """,
        cycleCount,
        pc,
        registers.accumulator,
        registers.x,
        registers.y,
        registers.stackPointer,
        registers.directPage,
        registers.dataBank,
        registers.status.rawValue,
        registers.emulationMode ? 1 : 0,
        machine.cpu.isWaiting ? 1 : 0,
        machine.memory.irqLineAsserted ? 1 : 0,
        mode,
        softSwitches.textMode ? 1 : 0,
        softSwitches.mixedMode ? 1 : 0,
        softSwitches.page2 ? 1 : 0,
        softSwitches.hires ? 1 : 0,
        softSwitches.eightyColumnVideo ? 1 : 0,
        softSwitches.videoControl,
        softSwitches.textColor,
        softSwitches.borderColor,
        softSwitches.shadowInhibit,
        softSwitches.speedRegister,
        machine.memory.interruptState.enableRegister,
        machine.memory.interruptState.videoStatusRegister,
        machine.memory.interruptState.c023StatusRegister,
        machine.memory.interruptState.c023PendingRegister,
        frame.width,
        frame.height,
        recentPCs,
        textBytes,
        shrBytes,
        iwmCounts
    )
    let url = URL(fileURLWithPath: "/private/tmp/disk-test-video-diagnostic.txt")
    try? line.write(to: url, atomically: true, encoding: String.Encoding.utf8)
}
#endif

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
