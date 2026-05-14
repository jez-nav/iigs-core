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
        sound.writeSoundControl(0x4F)
        sound.writePointerLow(0)
        sound.writePointerHigh(0)
        sound.writeDataPort(0x90)
        sound.writeSoundControl(0x0F)
        sound.writeRegister(0x40, value: 0x02)
        sound.writeRegister(0x80, value: 0x00)
        sound.writeRegister(0xA0, value: 0x00)

        XCTAssertEqual(sound.renderDOCSamples(count: 1), [480])
        XCTAssertEqual(sound.oscillators[0].data, 0x90)
    }
}
