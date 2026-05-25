public struct IIGSSpeakerToggle: Equatable, Sendable {
    public let cycle: UInt64
    public let isHigh: Bool
}

public struct IIGSAudioBuffer: Equatable, Sendable {
    public let sampleRate: Int
    public let startCycle: UInt64
    public let endCycle: UInt64
    public let channelCount: Int
    public let samples: [Int16]

    public var frameCount: Int {
        channelCount == 0 ? 0 : samples.count / channelCount
    }

    public init(sampleRate: Int, startCycle: UInt64, endCycle: UInt64, channelCount: Int, samples: [Int16]) {
        self.sampleRate = sampleRate
        self.startCycle = startCycle
        self.endCycle = endCycle
        self.channelCount = channelCount
        self.samples = samples
    }
}

public struct IIGSDOCOscillator: Equatable, Sendable {
    public var frequency: UInt16 = 0
    public var volume: UInt8 = 0
    public var data: UInt8 = 0
    public var wavePointer: UInt8 = 0
    public var control: UInt8 = 0x01
    public var waveSize: UInt8 = 0
    public var sampleOffset: Double = 0

    public var halted: Bool {
        control & 0x01 != 0
    }

    public var interruptEnabled: Bool {
        control & 0x08 != 0
    }

    public var outputChannel: Int {
        control & 0x10 != 0 ? 1 : 0
    }

    public var mode: Int {
        Int((control >> 1) & 0x03)
    }

    public var waveSizeBytes: Int {
        1 << (Int((waveSize >> 3) & 0x07) + 8)
    }

    public var resolution: Int {
        Int(waveSize & 0x07)
    }

    public var waveBaseAddress: UInt16 {
        let start = Int(wavePointer) << 8
        return UInt16(truncatingIfNeeded: start & ~(waveSizeBytes - 1))
    }
}

public final class IIGSSoundController {
    public static let defaultSampleRate = 48_000
    public static let docRAMSize = 65_536
    public static let oscillatorCount = 32
    public static let channelCount = 2
    public static let docScanRate = IIGSVideoTiming.megaIICyclesPerSecond * 7.0 / 8.0

    public private(set) var speakerLatch = false
    public private(set) var speakerToggles: [IIGSSpeakerToggle] = []
    public private(set) var audioRenderedThroughCycle: UInt64 = 0

    public private(set) var soundControl: UInt8 = 0x0F
    public private(set) var pointer: UInt16 = 0
    public private(set) var dataLatch: UInt8 = 0
    public private(set) var docRAM = Array(repeating: UInt8(0), count: IIGSSoundController.docRAMSize)
    public private(set) var oscillators = Array(repeating: IIGSDOCOscillator(), count: IIGSSoundController.oscillatorCount)
    public private(set) var enabledOscillatorCount = 1

    private var globalRegisters = Array(repeating: UInt8(0), count: 0x20)
    private var pendingInterrupts: [UInt8] = []
    private var pendingInterleavedSamples: [Int16] = []
    private var pendingAudioStartCycle: UInt64?
    private var pendingAudioEndCycle: UInt64 = 0
    private var pendingAudioSampleRate = IIGSSoundController.defaultSampleRate
    private var renderedSpeakerLatch = false
    private var renderedSpeakerToggleIndex = 0
    private var lastRenderedSpeakerToggleCycle: UInt64?

    public var masterVolume: UInt8 {
        soundControl & 0x0F
    }

    public var autoIncrementEnabled: Bool {
        soundControl & 0x20 != 0
    }

    public var ramModeEnabled: Bool {
        soundControl & 0x40 != 0
    }

    public var docIRQAsserted: Bool {
        !pendingInterrupts.isEmpty
    }

    public init() {}

    public func reset() {
        speakerLatch = false
        speakerToggles.removeAll(keepingCapacity: true)
        audioRenderedThroughCycle = 0
        soundControl = 0x0F
        pointer = 0
        dataLatch = 0
        docRAM = Array(repeating: 0, count: Self.docRAMSize)
        oscillators = Array(repeating: IIGSDOCOscillator(), count: Self.oscillatorCount)
        enabledOscillatorCount = 1
        globalRegisters = Array(repeating: 0, count: 0x20)
        pendingInterrupts.removeAll(keepingCapacity: true)
        pendingInterleavedSamples.removeAll(keepingCapacity: true)
        pendingAudioStartCycle = nil
        pendingAudioEndCycle = 0
        pendingAudioSampleRate = Self.defaultSampleRate
        renderedSpeakerLatch = false
        renderedSpeakerToggleIndex = 0
        lastRenderedSpeakerToggleCycle = nil
    }

    @discardableResult
    public func toggleSpeaker(atCycle cycle: UInt64) -> UInt8 {
        speakerLatch.toggle()
        speakerToggles.append(IIGSSpeakerToggle(cycle: cycle, isHigh: speakerLatch))
        return 0
    }

    public func readSoundControl() -> UInt8 {
        soundControl
    }

    public func writeSoundControl(_ value: UInt8) {
        soundControl = value & 0x6F
    }

    public func readPointerLow() -> UInt8 {
        UInt8(pointer & 0x00FF)
    }

    public func readPointerHigh() -> UInt8 {
        UInt8(pointer >> 8)
    }

    public func writePointerLow(_ value: UInt8) {
        pointer = (pointer & 0xFF00) | UInt16(value)
    }

    public func writePointerHigh(_ value: UInt8) {
        pointer = (pointer & 0x00FF) | (UInt16(value) << 8)
    }

    public func readDataPort() -> UInt8 {
        let oldLatch = dataLatch
        dataLatch = readAddressedByte()
        advancePointerIfNeeded()
        return oldLatch
    }

    public func writeDataPort(_ value: UInt8) {
        writeAddressedByte(value)
        dataLatch = value
        advancePointerIfNeeded()
    }

    public func docRAMByte(at address: UInt16) -> UInt8 {
        docRAM[Int(address)]
    }

    public func renderSpeakerSamples(count: Int) -> [Int16] {
        precondition(count >= 0)
        let amplitude = Int16(Int(masterVolume) * 256)
        let value = speakerLatch ? amplitude : -amplitude
        return Array(repeating: value, count: count)
    }

    public func renderDOCSamples(count: Int, sampleRate: Int = IIGSSoundController.defaultSampleRate) -> [Int16] {
        precondition(count >= 0)
        guard count > 0 else {
            return []
        }

        var samples: [Int16] = []
        samples.reserveCapacity(count)
        for _ in 0..<count {
            let frame = stepDOCFrame(sampleRate: sampleRate)
            samples.append(Int16(clamping: Int(frame.left) + Int(frame.right)))
        }
        return samples
    }

    public func queueAudio(toCycle endCycle: UInt64, sampleRate: Int = IIGSSoundController.defaultSampleRate) {
        let buffer = renderAudio(toCycle: endCycle, sampleRate: sampleRate)
        guard !buffer.samples.isEmpty else {
            return
        }

        if pendingInterleavedSamples.isEmpty || pendingAudioSampleRate != sampleRate {
            pendingAudioStartCycle = buffer.startCycle
            pendingAudioEndCycle = buffer.endCycle
            pendingAudioSampleRate = sampleRate
            pendingInterleavedSamples = buffer.samples
        } else {
            pendingAudioEndCycle = buffer.endCycle
            pendingInterleavedSamples.append(contentsOf: buffer.samples)
        }
    }

    public func drainAudio(toCycle endCycle: UInt64, sampleRate: Int = IIGSSoundController.defaultSampleRate) -> IIGSAudioBuffer {
        queueAudio(toCycle: endCycle, sampleRate: sampleRate)
        let startCycle = pendingAudioStartCycle ?? audioRenderedThroughCycle
        let samples = pendingInterleavedSamples
        let buffer = IIGSAudioBuffer(
            sampleRate: pendingAudioSampleRate,
            startCycle: startCycle,
            endCycle: pendingAudioEndCycle,
            channelCount: Self.channelCount,
            samples: samples
        )
        pendingInterleavedSamples.removeAll(keepingCapacity: true)
        pendingAudioStartCycle = nil
        pendingAudioEndCycle = endCycle
        pendingAudioSampleRate = sampleRate
        return buffer
    }

    public func renderAudio(toCycle endCycle: UInt64, sampleRate: Int = IIGSSoundController.defaultSampleRate) -> IIGSAudioBuffer {
        precondition(endCycle >= audioRenderedThroughCycle)
        let buffer = renderAudio(fromCycle: audioRenderedThroughCycle, toCycle: endCycle, sampleRate: sampleRate)
        audioRenderedThroughCycle = endCycle
        compactRenderedSpeakerToggles()
        return buffer
    }

    public func readRegister(_ register: UInt8) -> UInt8 {
        let index = Int(register & 0x1F)
        switch register & 0xE0 {
        case 0x00:
            return UInt8(oscillators[index].frequency & 0x00FF)
        case 0x20:
            return UInt8(oscillators[index].frequency >> 8)
        case 0x40:
            return oscillators[index].volume
        case 0x60:
            return oscillators[index].data
        case 0x80:
            return oscillators[index].wavePointer
        case 0xA0:
            return oscillators[index].control
        case 0xC0:
            return oscillators[index].waveSize
        case 0xE0:
            return readGlobalRegister(register & 0x1F)
        default:
            return 0xFF
        }
    }

    public func writeRegister(_ register: UInt8, value: UInt8) {
        let index = Int(register & 0x1F)
        switch register & 0xE0 {
        case 0x00:
            oscillators[index].frequency = (oscillators[index].frequency & 0xFF00) | UInt16(value)
        case 0x20:
            oscillators[index].frequency = (oscillators[index].frequency & 0x00FF) | (UInt16(value) << 8)
        case 0x40:
            oscillators[index].volume = value
        case 0x60:
            oscillators[index].data = value
        case 0x80:
            oscillators[index].wavePointer = value
            oscillators[index].sampleOffset = 0
        case 0xA0:
            oscillators[index].control = value
            if value & 0x01 == 0 {
                oscillators[index].sampleOffset = 0
            }
        case 0xC0:
            oscillators[index].waveSize = value
        case 0xE0:
            writeGlobalRegister(register & 0x1F, value: value)
        default:
            break
        }
    }

    private func readAddressedByte() -> UInt8 {
        if ramModeEnabled {
            return docRAM[Int(pointer)]
        }
        return readRegister(UInt8(pointer & 0x00FF))
    }

    private func writeAddressedByte(_ value: UInt8) {
        if ramModeEnabled {
            docRAM[Int(pointer)] = value
        } else {
            writeRegister(UInt8(pointer & 0x00FF), value: value)
        }
    }

    private func advancePointerIfNeeded() {
        if autoIncrementEnabled {
            pointer &+= 1
        }
    }

    private func readGlobalRegister(_ register: UInt8) -> UInt8 {
        if register == 0x00 {
            guard !pendingInterrupts.isEmpty else {
                return 0xFF
            }
            return pendingInterrupts.removeFirst() & 0x1F
        }
        return globalRegisters[Int(register)]
    }

    private func writeGlobalRegister(_ register: UInt8, value: UInt8) {
        globalRegisters[Int(register)] = value
        if register == 0x01 {
            enabledOscillatorCount = Int((value & 0x3E) >> 1) + 1
            for index in enabledOscillatorCount..<Self.oscillatorCount {
                stopOscillator(index)
            }
        }
    }

    private func renderAudio(fromCycle startCycle: UInt64, toCycle endCycle: UInt64, sampleRate: Int) -> IIGSAudioBuffer {
        precondition(sampleRate > 0)
        guard endCycle > startCycle else {
            return IIGSAudioBuffer(
                sampleRate: sampleRate,
                startCycle: startCycle,
                endCycle: endCycle,
                channelCount: Self.channelCount,
                samples: []
            )
        }

        let startFrame = audioFrameIndex(forCycle: startCycle, sampleRate: sampleRate)
        let endFrame = audioFrameIndex(forCycle: endCycle, sampleRate: sampleRate)
        guard endFrame > startFrame else {
            return IIGSAudioBuffer(
                sampleRate: sampleRate,
                startCycle: startCycle,
                endCycle: endCycle,
                channelCount: Self.channelCount,
                samples: []
            )
        }

        let frameCount = endFrame - startFrame
        var samples: [Int16] = []
        samples.reserveCapacity(frameCount * Self.channelCount)
        var toggleIndex = renderedSpeakerToggleIndex
        var currentSpeakerLatch = renderedSpeakerLatch
        var speakerToggleCycle = lastRenderedSpeakerToggleCycle

        for frameOffset in 0..<frameCount {
            let frameIndex = startFrame + frameOffset
            let sampleCycle = cycleForAudioFrame(frameIndex, sampleRate: sampleRate)
            while toggleIndex < speakerToggles.count, Double(speakerToggles[toggleIndex].cycle) <= sampleCycle {
                currentSpeakerLatch = speakerToggles[toggleIndex].isHigh
                speakerToggleCycle = speakerToggles[toggleIndex].cycle
                toggleIndex += 1
            }

            let speaker = speakerSample(
                atCycle: sampleCycle,
                isHigh: currentSpeakerLatch,
                lastToggleCycle: speakerToggleCycle
            )
            let doc = stepDOCFrame(sampleRate: sampleRate)
            samples.append(Int16(clamping: Int(doc.left) + Int(speaker)))
            samples.append(Int16(clamping: Int(doc.right) + Int(speaker)))
        }

        renderedSpeakerToggleIndex = toggleIndex
        renderedSpeakerLatch = currentSpeakerLatch
        lastRenderedSpeakerToggleCycle = speakerToggleCycle

        return IIGSAudioBuffer(
            sampleRate: sampleRate,
            startCycle: startCycle,
            endCycle: endCycle,
            channelCount: Self.channelCount,
            samples: samples
        )
    }

    private func stepDOCFrame(sampleRate: Int) -> (left: Int16, right: Int16) {
        var mixedLeft = 0
        var mixedRight = 0
        let activeCount = min(enabledOscillatorCount, Self.oscillatorCount)

        for index in 0..<activeCount {
            guard !oscillators[index].halted else {
                continue
            }

            let bytesPerFrame = docBytesPerFrame(for: oscillators[index], sampleRate: sampleRate)
            guard bytesPerFrame > 0 else {
                continue
            }

            let sampleAddress = (Int(oscillators[index].waveBaseAddress) + Int(oscillators[index].sampleOffset)) & 0xFFFF
            let sample = docRAM[sampleAddress]
            if sample == 0 {
                finishOscillator(index, canRepeat: false)
                continue
            }

            oscillators[index].data = sample
            let centered = Int(sample) - 128
            let mixed = centered * Int(oscillators[index].volume & 0x0F) * Int(masterVolume)
            if oscillators[index].outputChannel == 0 {
                mixedLeft += mixed
            } else {
                mixedRight += mixed
            }

            advanceOscillator(index, by: bytesPerFrame)
        }

        return (Int16(clamping: mixedLeft), Int16(clamping: mixedRight))
    }

    private func docBytesPerFrame(for oscillator: IIGSDOCOscillator, sampleRate: Int) -> Double {
        guard oscillator.frequency > 0, sampleRate > 0 else {
            return 0
        }

        let scanUpdatesPerFrame = Self.docScanRate / Double(sampleRate)
        let enabledSlots = Double(max(1, enabledOscillatorCount) + 2)
        let waveScale = Double(1 << max(0, 17 - oscillator.waveSizeBytes.trailingZeroBitCount + oscillator.resolution))
        return Double(oscillator.frequency) * scanUpdatesPerFrame / enabledSlots / waveScale
    }

    private func advanceOscillator(_ index: Int, by bytesPerFrame: Double) {
        oscillators[index].sampleOffset += bytesPerFrame
        let waveSize = Double(oscillators[index].waveSizeBytes)
        if oscillators[index].sampleOffset < waveSize {
            return
        }

        finishOscillator(index, canRepeat: true)
    }

    private func finishOscillator(_ index: Int, canRepeat: Bool) {
        let mode = oscillators[index].mode
        let partnerIndex = index ^ 1
        let partnerMode = oscillators[partnerIndex].mode

        if mode == 0, canRepeat {
            oscillators[index].sampleOffset.formTruncatingRemainder(dividingBy: Double(oscillators[index].waveSizeBytes))
            return
        }

        stopOscillator(index)

        if (mode == 3 || partnerMode == 3), canRepeat, oscillators[partnerIndex].halted {
            oscillators[partnerIndex].control &= 0xFE
            oscillators[partnerIndex].sampleOffset = 0
        }
    }

    private func stopOscillator(_ index: Int) {
        oscillators[index].control |= 0x01
        oscillators[index].sampleOffset = 0
        if oscillators[index].interruptEnabled {
            let encoded = UInt8(index & 0x1F)
            if !pendingInterrupts.contains(encoded) {
                pendingInterrupts.append(encoded)
            }
        }
    }

    private func audioFrameIndex(forCycle cycle: UInt64, sampleRate: Int) -> Int {
        Int((Double(cycle) * Double(sampleRate) / IIGSVideoTiming.megaIICyclesPerSecond).rounded(.down))
    }

    private func cycleForAudioFrame(_ frameIndex: Int, sampleRate: Int) -> Double {
        (Double(frameIndex) + 0.5) * IIGSVideoTiming.megaIICyclesPerSecond / Double(sampleRate)
    }

    private func speakerSample(atCycle cycle: Double, isHigh: Bool, lastToggleCycle: UInt64?) -> Int16 {
        guard let lastToggleCycle else {
            return 0
        }

        let fullAmplitude = Double(Int(masterVolume) * 256)
        guard fullAmplitude > 0 else {
            return 0
        }

        let decayDelay = IIGSVideoTiming.megaIICyclesPerSecond / 16.0
        let decayDuration = IIGSVideoTiming.megaIICyclesPerSecond / 16.0
        let elapsed = max(0, cycle - Double(lastToggleCycle))
        let magnitude: Double
        if elapsed <= decayDelay {
            magnitude = fullAmplitude
        } else {
            let progress = min(1.0, (elapsed - decayDelay) / decayDuration)
            magnitude = fullAmplitude * (1.0 - progress)
        }

        let signed = isHigh ? magnitude : -magnitude
        return Int16(clamping: Int(signed.rounded()))
    }

    private func compactRenderedSpeakerToggles() {
        guard renderedSpeakerToggleIndex > 4_096 else {
            return
        }

        speakerToggles.removeFirst(renderedSpeakerToggleIndex)
        renderedSpeakerToggleIndex = 0
    }
}
