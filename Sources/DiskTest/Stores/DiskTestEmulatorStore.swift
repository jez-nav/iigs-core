import AppKit
import Foundation
import IIGSCore
import UniformTypeIdentifiers

@MainActor
final class DiskTestEmulatorStore: ObservableObject {
    @Published private(set) var videoFrame = IIGSVideoFrame(width: 1, height: 1, pixels: [.black])
    @Published private(set) var emulatorFPS = "0.00 fps"
    @Published private(set) var uiFPS = "0.00 fps"
    @Published private(set) var displayHasKeyboardFocus = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var inputStatus = "Ready"
    @Published private(set) var diskStatus = "No disk mounted"
    @Published private(set) var audioStatus = "Audio starting"
    @Published private(set) var audioMuted = false
    @Published private(set) var audioVolume = 1.0
    @Published private(set) var mountedDisks: [IIGSDiskMountTarget: IIGSMountedDiskInfo] = [:]

    private let runner = DiskTestEmulatorRunner()
    private let audioPlayer = DiskTestAudioPlayer()
    private var started = false
    private var audioAvailable = false
    private var statsDate = Date()
    private var statsCycleCount: UInt64 = 0
    private var uiFrameTicks = 0
    private var lastDisplayMouseX: Int?
    private var lastDisplayMouseY: Int?
    private var lastMouseButtonDown = false
    private var classicDeskAccessoryTask: Task<Void, Never>?

    var windowTitle: String {
        "DiskTest - EM \(emulatorFPS) - UI \(uiFPS)"
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
            startAudio()
            resetStats()
            runner.start(
                romBytes: romBytes,
                batteryRAM: Self.loadBatteryRAM(),
                frameHandler: { [weak self] frame, cycleCount in
                    self?.publish(frame: frame, cycleCount: cycleCount)
                },
                audioHandler: { [audioPlayer] buffer in
                    audioPlayer.enqueue(buffer)
                },
                audioResetHandler: { [audioPlayer] in
                    audioPlayer.clear()
                },
                statusHandler: { [weak self] mountedDisks in
                    self?.publish(mountedDisks: mountedDisks)
                },
                batteryRAMHandler: { bytes in
                    Self.persistBatteryRAM(bytes)
                },
                errorHandler: { [weak self] message in
                    self?.errorMessage = message
                    self?.diskStatus = message
                }
            )
        } catch {
            errorMessage = "ROM1 load failed: \(error)"
        }
    }

    func stop() {
        classicDeskAccessoryTask?.cancel()
        classicDeskAccessoryTask = nil
        runner.stop()
        audioPlayer.stop()
        audioAvailable = false
    }

    func setDisplayFocus(_ focused: Bool) {
        if !focused {
            runner.releaseKeyboard()
            releaseMouseButtonIfNeeded()
            clearDisplayMouse()
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

    func handleMouse(displayX: Int, displayY: Int, buttonDown: Bool, syncToHostPosition: Bool) {
        if syncToHostPosition {
            runner.syncMouse(displayX: displayX, displayY: displayY, buttonDown: buttonDown)
        } else {
            let deltaX = lastDisplayMouseX.map { displayX - $0 } ?? 0
            let deltaY = lastDisplayMouseY.map { displayY - $0 } ?? 0
            let buttonChanged = buttonDown != lastMouseButtonDown
            let events = IIGSHostMouseEvent.events(
                deltaX: deltaX,
                deltaY: deltaY,
                buttonDown: buttonDown,
                includeStationaryEvent: buttonChanged
            )

            for event in events {
                runner.enqueue(event)
            }
        }

        lastDisplayMouseX = displayX
        lastDisplayMouseY = displayY
        lastMouseButtonDown = buttonDown
    }

    func clearDisplayMouse() {
        lastDisplayMouseX = nil
        lastDisplayMouseY = nil
    }

    func handleMouseExit() {
        releaseMouseButtonIfNeeded()
        clearDisplayMouse()
    }

    func sendColdReset() {
        runner.powerCycle()
        inputStatus = "Cold reset requested"
    }

    func sendWarmReset() {
        runner.reset(.warm)
        inputStatus = "Warm reset requested"
    }

    func sendControlResetKey() {
        runner.keyboardReset()
        inputStatus = "Control-Reset requested"
    }

    func sendControlPanelResetKey() {
        runner.keyboardReset(modifiers: .option)
        inputStatus = "Option-Reset requested"
    }

    func sendClassicDeskAccessoryKey() {
        inputStatus = "Classic Desk Accessory requested"
        classicDeskAccessoryTask?.cancel()
        runner.releaseKeyboard()
        classicDeskAccessoryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            let groups = MacKeyboardInputMapper.classicDeskAccessoryEventGroups()
            for (index, events) in groups.enumerated() {
                guard let self, !Task.isCancelled else {
                    return
                }
                self.enqueue(events)
                if index < groups.count - 1 {
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
            }
            self?.inputStatus = "Classic Desk Accessory sent"
        }
    }

    func typeBasicSmokeTest() {
        runner.keyboardReset()
        inputStatus = "Control-Reset requested; typing shortly"
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.typeText(Self.basicSmokeTest)
        }
    }

    func chooseDisk(for target: IIGSDiskMountTarget) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.data]
        panel.title = "Mount \(target.displayName)"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        mountDisk(at: url, target: target)
    }

    func mountDisk(at url: URL, target: IIGSDiskMountTarget) {
        runner.mountDisk(url: url, target: target)
        diskStatus = "Mounting \(url.lastPathComponent) on \(target.displayName)"
    }

    func ejectDisk(target: IIGSDiskMountTarget) {
        runner.ejectDisk(target: target)
        diskStatus = "Ejecting \(target.displayName)"
    }

    func setAudioEnabled(_ enabled: Bool) {
        audioMuted = !enabled
        audioPlayer.setMuted(audioMuted)
        updateAudioStatus()
    }

    func setAudioVolume(_ volume: Double) {
        audioVolume = min(max(volume, 0), 1)
        audioPlayer.setVolume(audioVolume)
        updateAudioStatus()
    }

    func handleDrop(_ providers: [NSItemProvider], target: IIGSDiskMountTarget) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                let url: URL?
                if let itemURL = item as? URL {
                    url = itemURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }

                guard let url else {
                    return
                }

                Task { @MainActor [weak self] in
                    self?.mountDisk(at: url, target: target)
                }
            }
            return true
        }
        return false
    }

    private func publish(frame: IIGSVideoFrame, cycleCount: UInt64) {
        videoFrame = frame
        uiFrameTicks += 1
        updateStats(cycleCount: cycleCount)
    }

    private func publish(mountedDisks: [IIGSDiskMountTarget: IIGSMountedDiskInfo]) {
        self.mountedDisks = mountedDisks
        if mountedDisks.isEmpty {
            diskStatus = "No disk mounted"
        } else {
            let mountedList = mountedDisks.values
                .sorted { $0.target.displayName < $1.target.displayName }
                .map { "\($0.target.displayName): \($0.name)" }
                .joined(separator: "  ")
            diskStatus = mountedList
        }
    }

    private func resetStats() {
        let now = Date()
        statsDate = now
        statsCycleCount = 0
        uiFrameTicks = 0
        lastDisplayMouseX = nil
        lastDisplayMouseY = nil
        lastMouseButtonDown = false
        emulatorFPS = "0.00 fps"
        uiFPS = "0.00 fps"
        errorMessage = nil
        inputStatus = "Ready"
        diskStatus = "No disk mounted"
        updateAudioStatus()
        mountedDisks = [:]
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

    private func startAudio() {
        do {
            try audioPlayer.start()
            audioAvailable = true
            audioPlayer.setMuted(audioMuted)
            audioPlayer.setVolume(audioVolume)
        } catch {
            audioAvailable = false
            audioStatus = "Audio unavailable: \(error.localizedDescription)"
        }
    }

    private func updateAudioStatus() {
        guard audioAvailable else {
            return
        }

        if audioMuted {
            audioStatus = "Muted"
        } else {
            audioStatus = "Volume \(Int((audioVolume * 100).rounded()))%"
        }
    }

    private func releaseMouseButtonIfNeeded() {
        guard lastMouseButtonDown else {
            return
        }

        runner.enqueue(IIGSHostMouseEvent(dx: 0, dy: 0, buttonDown: false))
        lastMouseButtonDown = false
    }

    private static let basicSmokeTest = """
    10 TEXT
    20 HOME
    30 PRINT "DISK TEST"
    40 PRINT "READY"
    RUN

    """

    private static var batteryRAMURL: URL? {
        guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return applicationSupport
            .appendingPathComponent("IIGSCore", isDirectory: true)
            .appendingPathComponent("DiskTest-BatteryRAM.bin")
    }

    private static func loadBatteryRAM() -> [UInt8]? {
        guard let url = batteryRAMURL,
              let data = try? Data(contentsOf: url),
              data.count == 256
        else {
            return nil
        }
        let bytes = Array(data)
        return isLegacyMutedDefaultBatteryRAM(bytes) ? nil : bytes
    }

    private static func persistBatteryRAM(_ bytes: [UInt8]) {
        guard bytes.count == 256,
              let url = batteryRAMURL
        else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(bytes).write(to: url, options: [.atomic])
        } catch {
            // Battery RAM persistence should never stop the emulator loop.
        }
    }

    private static func isLegacyMutedDefaultBatteryRAM(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 256 else {
            return false
        }

        return bytes[0x1A] == 0x0F
            && bytes[0x1B] == 0x06
            && bytes[0x1C] == 0x06
            && bytes[0x1E] == 0x00
            && bytes[0x20] == 0x01
            && bytes[0x25] == 0x00
            && bytes[0x26] == 0x00
            && bytes[0x27] == 0x01
            && bytes[0x28] == 0x00
    }
}
