public struct IIGSSpeakerToggle: Equatable, Sendable {
    public let cycle: UInt64
    public let isHigh: Bool
}

public struct IIGSDOCOscillator: Equatable, Sendable {
    public var frequency: UInt16 = 0
    public var volume: UInt8 = 0
    public var data: UInt8 = 0
    public var wavePointer: UInt8 = 0
    public var control: UInt8 = 0x01
    public var waveSize: UInt8 = 0
    public var sampleOffset: UInt16 = 0

    public var halted: Bool {
        control & 0x01 != 0
    }

    public var interruptEnabled: Bool {
        control & 0x08 != 0
    }

    public var waveBaseAddress: UInt16 {
        UInt16(wavePointer) << 8
    }
}

public final class IIGSSoundController {
    public static let docRAMSize = 65_536
    public static let oscillatorCount = 32

    public private(set) var speakerLatch = false
    public private(set) var speakerToggles: [IIGSSpeakerToggle] = []

    public private(set) var soundControl: UInt8 = 0x0F
    public private(set) var pointer: UInt16 = 0
    public private(set) var dataLatch: UInt8 = 0
    public private(set) var docRAM = Array(repeating: UInt8(0), count: IIGSSoundController.docRAMSize)
    public private(set) var oscillators = Array(repeating: IIGSDOCOscillator(), count: IIGSSoundController.oscillatorCount)
    public private(set) var enabledOscillatorCount = 1

    private var globalRegisters = Array(repeating: UInt8(0), count: 0x20)
    private var pendingInterrupts: [UInt8] = []

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
        soundControl = 0x0F
        pointer = 0
        dataLatch = 0
        docRAM = Array(repeating: 0, count: Self.docRAMSize)
        oscillators = Array(repeating: IIGSDOCOscillator(), count: Self.oscillatorCount)
        enabledOscillatorCount = 1
        globalRegisters = Array(repeating: 0, count: 0x20)
        pendingInterrupts.removeAll(keepingCapacity: true)
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

    public func renderDOCSamples(count: Int) -> [Int16] {
        precondition(count >= 0)
        guard count > 0 else {
            return []
        }

        var samples: [Int16] = []
        samples.reserveCapacity(count)
        for _ in 0..<count {
            samples.append(stepDOCSample())
        }
        return samples
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
        }
    }

    private func stepDOCSample() -> Int16 {
        var mixed = 0
        let activeCount = min(enabledOscillatorCount, Self.oscillatorCount)

        for index in 0..<activeCount {
            guard !oscillators[index].halted else {
                continue
            }

            let sampleAddress = oscillators[index].waveBaseAddress &+ oscillators[index].sampleOffset
            let sample = docRAM[Int(sampleAddress)]
            if sample == 0 {
                stopOscillator(index)
                continue
            }

            oscillators[index].data = sample
            oscillators[index].sampleOffset &+= 1
            let centered = Int(sample) - 128
            mixed += centered * Int(oscillators[index].volume & 0x0F) * Int(masterVolume)
        }

        return Int16(clamping: mixed)
    }

    private func stopOscillator(_ index: Int) {
        oscillators[index].control |= 0x01
        if oscillators[index].interruptEnabled {
            let encoded = UInt8(index & 0x1F)
            if !pendingInterrupts.contains(encoded) {
                pendingInterrupts.append(encoded)
            }
        }
    }
}
