import XCTest
@testable import IIGSCore

final class StoragePhase9Tests: XCTestCase {
    func testRawFiveAndQuarterMediaReadsPhysicalSectors() throws {
        var bytes = Array(repeating: UInt8(0), count: IIGSFloppyMedia.raw5_25ByteCount)
        bytes[0] = 0xA5
        bytes[15 * IIGSFloppyMedia.sectorSize5_25] = 0x5A

        let media = try IIGSFloppyMedia(raw5_25: bytes)

        XCTAssertEqual(media.byteCount, 143_360)
        XCTAssertEqual(try media.readSector(track: 0, sector: 0)[0], 0xA5)
        XCTAssertEqual(try media.readSector(track: 0, sector: 15)[0], 0x5A)
    }

    func testRawThreeAndHalfMediaMountsAs800K() throws {
        let media = try IIGSFloppyMedia(raw3_5: Array(repeating: 0, count: IIGSFloppyMedia.raw3_5ByteCount))

        XCTAssertEqual(media.kind, .raw3_5)
        XCTAssertEqual(media.byteCount, 819_200)
    }

    func testNIBMediaReadsRawTrackStream() throws {
        var bytes = Array(repeating: UInt8(0), count: IIGSFloppyMedia.nibTrackSize)
        bytes[0] = 0xD5
        bytes[1] = 0xAA
        bytes[2] = 0x96
        let media = try IIGSFloppyMedia(nib: bytes)

        XCTAssertEqual(media.readTrackByte(quarterTrack: 0, offset: 0), 0xD5)
        XCTAssertEqual(media.readTrackByte(quarterTrack: 0, offset: 1), 0xAA)
        XCTAssertEqual(media.readTrackByte(quarterTrack: 0, offset: 2), 0x96)
    }

    func testWOZTrackMapChunkIsParsed() throws {
        var image: [UInt8] = [0x57, 0x4F, 0x5A, 0x32, 0xFF, 0x0A, 0x0D, 0x0A, 0, 0, 0, 0]
        var tmap = Array(repeating: UInt8(0xFF), count: 160)
        tmap[0] = 0
        appendChunk("TMAP", payload: tmap, to: &image)
        appendChunk("TRKS", payload: [0xD5, 0xAA, 0x96], to: &image)

        let media = try IIGSFloppyMedia(woz: image)

        XCTAssertEqual(media.kind, .woz(version: 2))
        XCTAssertEqual(media.wozTrackMap?[0], 0)
        XCTAssertEqual(media.wozTrackMap?[1], 0xFF)
        XCTAssertEqual(media.readTrackByte(quarterTrack: 0, offset: 0), 0xD5)
    }

    func testIWMSwitchesTrackMotorDriveAndQLatches() {
        let iwm = IIGSIWMController()

        _ = iwm.accessSwitch(offset: 0x09)
        _ = iwm.accessSwitch(offset: 0x0B)
        _ = iwm.accessSwitch(offset: 0x0D)
        _ = iwm.accessSwitch(offset: 0x0F)

        XCTAssertTrue(iwm.motorOn)
        XCTAssertEqual(iwm.selectedDriveNumber, 2)
        XCTAssertTrue(iwm.q6)
        XCTAssertTrue(iwm.q7)
    }

    func testIWMStepperMovesInAndBackOut() {
        let iwm = IIGSIWMController()

        _ = iwm.accessSwitch(offset: 0x01)
        _ = iwm.accessSwitch(offset: 0x03)
        _ = iwm.accessSwitch(offset: 0x05)
        XCTAssertEqual(iwm.drive1.quarterTrack, 2)

        _ = iwm.accessSwitch(offset: 0x03)
        XCTAssertEqual(iwm.drive1.quarterTrack, 1)
    }

    func testBusRoutesC0E0ThroughC0EFToIWMController() throws {
        let memory = FlatMemoryBus()
        var bytes = Array(repeating: UInt8(0), count: IIGSFloppyMedia.raw5_25ByteCount)
        bytes[0] = 0xD5
        bytes[1] = 0xAA
        let media = try IIGSFloppyMedia(raw5_25: bytes)
        memory.iwmController.mount(media)

        memory[0x00C0E9] = 0
        memory[0x00C0EA] = 0
        memory[0x00C0EC] = 0
        memory[0x00C0EE] = 0

        XCTAssertEqual(memory[0x00C0EC], 0xD5)
        XCTAssertEqual(memory[0x00C0EC], 0xAA)
        XCTAssertTrue(memory.iwmController.motorOn)
        XCTAssertEqual(memory.iwmController.selectedDriveNumber, 1)
    }

    func testWriteProtectStatusUsesQ6SetQ7Clear() throws {
        let memory = FlatMemoryBus()
        let media = try IIGSFloppyMedia(raw5_25: Array(repeating: 0, count: IIGSFloppyMedia.raw5_25ByteCount), isWriteProtected: true)
        memory.iwmController.mount(media)

        memory[0x00C0E9] = 0
        memory[0x00C0ED] = 0
        memory[0x00C0EE] = 0

        XCTAssertEqual(memory[0x00C0ED], 0x80)
    }

    func testIWMModeRegisterIsReflectedThroughStatusRead() {
        let memory = FlatMemoryBus()

        memory[0x00C0ED] = 0 // Q6 high
        memory[0x00C0EF] = 0x0F // Q7 high, drive off: write IWM mode

        XCTAssertEqual(memory.iwmController.modeRegister, 0x0F)
        XCTAssertEqual(memory[0x00C0EE] & 0x1F, 0x0F) // Q7 low, Q6 high: read status/mode
    }

    func testIWMWriteModeMutatesWritableRawTrack() throws {
        let memory = FlatMemoryBus()
        let media = try IIGSFloppyMedia(raw5_25: Array(repeating: 0, count: IIGSFloppyMedia.raw5_25ByteCount))
        memory.iwmController.mount(media)

        memory[0x00C0E9] = 0
        memory[0x00C0ED] = 0
        memory[0x00C0EF] = 0
        memory[0x00C0EF] = 0xA9

        XCTAssertTrue(media.isDirty)
        XCTAssertEqual(media.readTrackByte(quarterTrack: 0, offset: 0), 0xA9)
    }

    func testThreeAndHalfModeUsesC031ControlInputForMotorCommand() {
        let memory = FlatMemoryBus()

        memory[0x00C031] = 0xC0
        _ = memory[0x00C0E7]
        XCTAssertTrue(memory.iwmController.threePointFiveMotorOn)

        memory[0x00C031] = 0x40
        _ = memory[0x00C0E7]
        XCTAssertFalse(memory.iwmController.threePointFiveMotorOn)
        XCTAssertEqual(memory[0x00C031], 0x40)
    }

    private func appendChunk(_ name: String, payload: [UInt8], to image: inout [UInt8]) {
        image.append(contentsOf: name.utf8)
        appendLittle32(UInt32(payload.count), to: &image)
        image.append(contentsOf: payload)
    }

    private func appendLittle32(_ value: UInt32, to image: inout [UInt8]) {
        image.append(UInt8(value & 0xFF))
        image.append(UInt8((value >> 8) & 0xFF))
        image.append(UInt8((value >> 16) & 0xFF))
        image.append(UInt8((value >> 24) & 0xFF))
    }
}
