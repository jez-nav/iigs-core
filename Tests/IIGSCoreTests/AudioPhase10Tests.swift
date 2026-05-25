import Foundation
import XCTest
@testable import IIGSCore

final class AudioPhase10Tests: XCTestCase {
    func testSpeakerReadAndWriteToggleLatchAndRecordCycles() {
        let memory = FlatMemoryBus()

        memory[0x00C030] = 0
        _ = memory[0x00C030]

        XCTAssertFalse(memory.soundController.speakerLatch)
        XCTAssertEqual(memory.soundController.speakerToggles.count, 2)
        XCTAssertEqual(memory.soundController.speakerToggles[0].cycle, 1)
        XCTAssertEqual(memory.soundController.speakerToggles[1].cycle, 2)
    }

    func testSpeakerSamplesFollowMasterVolume() {
        let memory = FlatMemoryBus()
        memory[0x00C03C] = 0x00
        memory[0x00C030] = 0
        XCTAssertEqual(memory.soundController.renderSpeakerSamples(count: 3), [0, 0, 0])

        memory[0x00C03C] = 0x0F
        XCTAssertEqual(memory.soundController.renderSpeakerSamples(count: 2), [3_840, 3_840])
    }

    func testRawAudioSpeakerIsSilentUntilFirstToggle() {
        let sound = IIGSSoundController()

        let buffer = sound.renderAudio(toCycle: 40, sampleRate: 102_300)

        XCTAssertEqual(buffer.channelCount, 2)
        XCTAssertEqual(buffer.frameCount, 4)
        XCTAssertEqual(buffer.samples, Array(repeating: 0, count: 8))
    }

    func testRawAudioSpeakerUsesCyclePositionedToggles() {
        let sound = IIGSSoundController()
        sound.writeSoundControl(0x0F)
        _ = sound.toggleSpeaker(atCycle: 10)
        _ = sound.toggleSpeaker(atCycle: 20)

        let buffer = sound.renderAudio(toCycle: 40, sampleRate: 102_300)

        XCTAssertEqual(buffer.frameCount, 4)
        XCTAssertEqual(buffer.samples, [
            0, 0,
            3_840, 3_840,
            -3_840, -3_840,
            -3_840, -3_840
        ])
    }

    func testMemoryBusDrainsSamplesAcrossAudioStateChanges() {
        let memory = FlatMemoryBus()
        memory[0x00C03C] = 0x0F
        memory[0x00C030] = 0
        memory.idle(cycles: 38)

        let buffer = memory.drainAudio(sampleRate: 102_300)

        XCTAssertEqual(buffer.frameCount, 4)
        XCTAssertTrue(buffer.samples.contains(3_840))
    }

    func testDOCRAMAutoIncrementWritesAdvancePointer() {
        let memory = FlatMemoryBus()
        memory[0x00C03E] = 0x34
        memory[0x00C03F] = 0x12
        memory[0x00C03C] = 0x60

        memory[0x00C03D] = 0x56
        memory[0x00C03D] = 0x78

        XCTAssertEqual(memory.soundController.docRAMByte(at: 0x1234), 0x56)
        XCTAssertEqual(memory.soundController.docRAMByte(at: 0x1235), 0x78)
        XCTAssertEqual(memory[0x00C03E], 0x36)
        XCTAssertEqual(memory[0x00C03F], 0x12)
    }

    func testDOCRegisterModeProgramsOscillatorFrequency() {
        let memory = FlatMemoryBus()
        memory[0x00C03C] = 0x00

        memory[0x00C03E] = 0x00
        memory[0x00C03F] = 0x00
        memory[0x00C03D] = 0x34
        memory[0x00C03E] = 0x20
        memory[0x00C03F] = 0x00
        memory[0x00C03D] = 0x12

        XCTAssertEqual(memory.soundController.oscillators[0].frequency, 0x1234)
    }

    func testDOCDataPortReadsAreDelayed() {
        let memory = FlatMemoryBus()
        memory[0x00C03E] = 0x00
        memory[0x00C03F] = 0x20
        memory[0x00C03C] = 0x40
        memory[0x00C03D] = 0x9A
        memory[0x00C03E] = 0x00
        memory[0x00C03F] = 0x20

        XCTAssertEqual(memory[0x00C03D], 0x9A)
        XCTAssertEqual(memory[0x00C03D], 0x9A)
    }

    func testDOCDataPortDelayedReadReturnsPreviousLatchFirst() {
        let sound = IIGSSoundController()
        sound.writeSoundControl(0x40)
        sound.writePointerLow(0x00)
        sound.writePointerHigh(0x10)
        sound.writeDataPort(0x44)
        sound.writePointerLow(0x01)
        sound.writeDataPort(0x55)
        sound.writePointerLow(0x00)

        XCTAssertEqual(sound.readDataPort(), 0x55)
        XCTAssertEqual(sound.readDataPort(), 0x44)
    }

    func testDOCInterruptRegisterReportsAndClearsOldestPendingOscillator() {
        let sound = IIGSSoundController()
        sound.writeSoundControl(0x40)
        sound.writePointerLow(0)
        sound.writePointerHigh(0)
        sound.writeDataPort(0)
        sound.writeSoundControl(0)
        sound.writeRegister(0x00, value: 0x00)
        sound.writeRegister(0x20, value: 0x80)
        sound.writeRegister(0x80, value: 0x00)
        sound.writeRegister(0x40, value: 0x0F)
        sound.writeRegister(0xA0, value: 0x08)

        _ = sound.renderDOCSamples(count: 1)

        XCTAssertTrue(sound.docIRQAsserted)
        XCTAssertEqual(sound.readRegister(0xE0), 0x00)
        XCTAssertFalse(sound.docIRQAsserted)
        XCTAssertEqual(sound.readRegister(0xE0), 0xFF)
    }

    func testDOCInterruptQueuePreservesOscillatorOrder() {
        let sound = IIGSSoundController()
        sound.writeSoundControl(0)
        sound.writeRegister(0xE1, value: 0x02)
        sound.writeRegister(0x00, value: 0x00)
        sound.writeRegister(0x20, value: 0x80)
        sound.writeRegister(0x01, value: 0x00)
        sound.writeRegister(0x21, value: 0x80)
        sound.writeRegister(0xA0, value: 0x08)
        sound.writeRegister(0xA1, value: 0x08)

        _ = sound.renderDOCSamples(count: 1)

        XCTAssertEqual(sound.readRegister(0xE0), 0x00)
        XCTAssertEqual(sound.readRegister(0xE0), 0x01)
        XCTAssertEqual(sound.readRegister(0xE0), 0xFF)
    }

    func testDOCEnableRegisterSupportsThirtyTwoOscillators() {
        let sound = IIGSSoundController()

        sound.writeRegister(0xE1, value: 0x3E)

        XCTAssertEqual(sound.enabledOscillatorCount, 32)
    }

    func testDOCMixerUsesWaveRAMOscillatorVolumeAndMasterVolume() {
        let sound = IIGSSoundController()
        sound.writeSoundControl(0x6F)
        sound.writePointerLow(0)
        sound.writePointerHigh(0)
        sound.writeDataPort(0x90)
        sound.writeSoundControl(0x0F)
        sound.writeRegister(0x40, value: 0x02)
        sound.writeRegister(0x80, value: 0x00)
        sound.writeRegister(0x00, value: 0x00)
        sound.writeRegister(0x20, value: 0x01)
        sound.writeRegister(0xA0, value: 0x00)

        XCTAssertEqual(sound.renderDOCSamples(count: 1), [480])
        XCTAssertEqual(sound.oscillators[0].data, 0x90)
    }

    func testRawAudioDOCUsesFrequencyDerivedStepping() {
        let sound = IIGSSoundController()
        sound.writeSoundControl(0x6F)
        sound.writePointerLow(0)
        sound.writePointerHigh(0)
        sound.writeDataPort(0x90)
        sound.writeDataPort(0xA0)
        sound.writeSoundControl(0x0F)
        sound.writeRegister(0x00, value: 0x00)
        sound.writeRegister(0x20, value: 0x01)
        sound.writeRegister(0x40, value: 0x02)
        sound.writeRegister(0x80, value: 0x00)
        sound.writeRegister(0xA0, value: 0x00)

        let buffer = sound.renderAudio(toCycle: 100, sampleRate: 48_000)

        XCTAssertEqual(buffer.channelCount, 2)
        XCTAssertGreaterThan(buffer.frameCount, 0)
        XCTAssertTrue(buffer.samples.contains(480))
        XCTAssertEqual(sound.oscillators[0].data, 0x90)
    }

    func testROM01BootSpeakerBeepHasStableToneWhenLocalROMIsAvailable() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let romURL = repoRoot.appendingPathComponent("LocalAssets/ROMs/Apple_IIGS_ROM01.bin")
        guard FileManager.default.fileExists(atPath: romURL.path) else {
            throw XCTSkip("Local ROM 01 fixture is not available")
        }

        let rom = try IIGSROMImage(bytes: Array(Data(contentsOf: romURL)))
        let machine = IIGSMachine(romImage: rom)
        machine.powerCycle()

        for _ in 0..<200 {
            _ = try machine.runForCycles(25_000, instructionLimit: 200_000)
            if machine.memory.soundController.speakerToggles.count >= 20 {
                break
            }
        }

        let toggles = machine.memory.soundController.speakerToggles
        XCTAssertGreaterThanOrEqual(toggles.count, 12, "ROM boot should produce the startup beep through $C030 toggles")

        let deltas = zip(toggles.dropFirst(), toggles).map { Int($0.cycle - $1.cycle) }
        let positiveDeltas = deltas.filter { $0 > 0 }
        XCTAssertFalse(positiveDeltas.isEmpty, "ROM boot beep should include positive speaker-toggle deltas")
        guard !positiveDeltas.isEmpty else {
            return
        }

        let medianDelta = positiveDeltas.sorted()[positiveDeltas.count / 2]
        let stableDeltas = positiveDeltas.filter {
            abs(Double($0 - medianDelta)) <= max(2.0, Double(medianDelta) * 0.05)
        }
        XCTAssertGreaterThanOrEqual(stableDeltas.count, 8, "ROM boot beep should include a stable tone period")
        guard !stableDeltas.isEmpty else {
            return
        }

        let averageDelta = Double(stableDeltas.reduce(0, +)) / Double(stableDeltas.count)
        let squareWaveFrequency = IIGSVideoTiming.megaIICyclesPerSecond / averageDelta / 2.0
        print("ROM 01 startup beep measured at \(squareWaveFrequency) Hz from average toggle delta \(averageDelta) cycles")

        XCTAssertGreaterThan(squareWaveFrequency, 240, "Measured ROM 01 startup beep at \(squareWaveFrequency) Hz")
        XCTAssertLessThan(squareWaveFrequency, 260, "Measured ROM 01 startup beep at \(squareWaveFrequency) Hz")
    }
}
