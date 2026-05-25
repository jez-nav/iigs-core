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

    func testRawThreeAndHalfMediaProvidesEncodedTrackStream() throws {
        var bytes = Array(repeating: UInt8(0), count: IIGSFloppyMedia.raw3_5ByteCount)
        bytes[0] = 0xA5
        let media = try IIGSFloppyMedia(raw3_5: bytes)
        let stream = (0..<1_400).map { media.readTrackByte(quarterTrack: 0, offset: $0) }

        XCTAssertNotNil(indexOf([0xD5, 0xAA, 0x96], in: stream))
        let dataHeader = try XCTUnwrap(indexOf([0xD5, 0xAA, 0xAD], in: stream))
        XCTAssertEqual(stream[dataHeader + 3], 0x96)

        var alteredBytes = bytes
        alteredBytes[0] = 0x5A
        let alteredMedia = try IIGSFloppyMedia(raw3_5: alteredBytes)
        let alteredStream = (0..<1_400).map { alteredMedia.readTrackByte(quarterTrack: 0, offset: $0) }
        XCTAssertNotEqual(stream, alteredStream)
    }

    func testRawThreeAndHalfEncodedTracksRoundTripSectorDataAndTags() throws {
        var bytes = Array(repeating: UInt8(0), count: IIGSFloppyMedia.raw3_5ByteCount)
        for block in 0..<(bytes.count / IIGSFloppyMedia.blockSize3_5) {
            let offset = block * IIGSFloppyMedia.blockSize3_5
            bytes[offset] = UInt8(truncatingIfNeeded: block)
            bytes[offset + 1] = UInt8(truncatingIfNeeded: block >> 8)
            bytes[offset + 2] = UInt8(truncatingIfNeeded: block ^ 0xA5)
        }
        let media = try IIGSFloppyMedia(raw3_5: bytes)

        let track0Side0 = decodedRaw3_5Track(quarterTrack: 0, sectorCount: 12, media: media)
        XCTAssertEqual(Array(track0Side0[0]?[0..<12] ?? []), Array(repeating: UInt8(0), count: 12))
        XCTAssertEqual(Array(track0Side0[0]?[12..<15] ?? []), [0x00, 0x00, 0xA5])
        XCTAssertEqual(Array(track0Side0[6]?[12..<15] ?? []), [0x06, 0x00, 0xA3])

        let track20Side1 = decodedRaw3_5Track(quarterTrack: 41, sectorCount: 11, media: media)
        let startBlock = (16 * 12 * 2) + (4 * 11 * 2) + 11
        XCTAssertEqual(Array(track20Side1[0]?[12..<15] ?? []), [
            UInt8(truncatingIfNeeded: startBlock),
            UInt8(truncatingIfNeeded: startBlock >> 8),
            UInt8(truncatingIfNeeded: startBlock ^ 0xA5)
        ])
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
        memory.idle(cycles: 32)
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
        XCTAssertEqual(memory[0x00C0EE] & 0x80, 0x80)
    }

    func testOddIWMReadsOnlyTouchLatchAndReturnZero() throws {
        let memory = FlatMemoryBus()
        var bytes = Array(repeating: UInt8(0), count: IIGSFloppyMedia.raw5_25ByteCount)
        bytes[0] = 0xD5
        let media = try IIGSFloppyMedia(raw5_25: bytes)
        memory.iwmController.mount(media)

        memory[0x00C0E9] = 0

        XCTAssertEqual(memory[0x00C0EF], 0x00)
        XCTAssertTrue(memory.iwmController.q7)
        XCTAssertEqual(memory[0x00C0EC] & 0x80, 0x80)
    }

    func testIWMModeRegisterIsReflectedThroughStatusRead() {
        let memory = FlatMemoryBus()

        memory[0x00C0ED] = 0 // Q6 high
        memory[0x00C0EF] = 0x0F // Q7 high, drive off: write IWM mode

        XCTAssertEqual(memory.iwmController.modeRegister, 0x0F)
        XCTAssertEqual(memory[0x00C0EE] & 0x1F, 0x0F) // Q7 low, Q6 high: read status/mode
    }

    func testIWMHandshakeReportsReadyWhenQ7HighAndQ6Low() {
        let memory = FlatMemoryBus()

        memory[0x00C0EF] = 0 // Q7 high
        memory[0x00C0EC] = 0 // Q6 low

        XCTAssertEqual(memory[0x00C0EC] & 0x80, 0x80)
        XCTAssertEqual(memory[0x00C0EC] & 0x40, 0x40)
        _ = memory[0x00C0EC]
        _ = memory[0x00C0EC]
        XCTAssertEqual(memory[0x00C0EC] & 0x80, 0x80)
        XCTAssertEqual(memory[0x00C0EC] & 0x40, 0x00)
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

    func testIWMWriteModeDoesNotMutateModeRegisterWhileThreeAndHalfDriveIsOn() throws {
        let memory = FlatMemoryBus()
        let media = try IIGSFloppyMedia(raw3_5: Array(repeating: 0, count: IIGSFloppyMedia.raw3_5ByteCount))
        memory.iwmController.mount(media)

        memory[0x00C0ED] = 0
        memory[0x00C0EF] = 0x0F
        memory[0x00C031] = 0x40
        memory[0x00C0E9] = 0
        memory[0x00C0EF] = 0
        memory[0x00C0EF] = 0x03

        XCTAssertEqual(memory.iwmController.modeRegister, 0x0F)
    }

    func testThreeAndHalfModeUsesC031ControlInputForMotorCommand() {
        let memory = FlatMemoryBus()

        memory[0x00C031] = 0x40
        memory[0x00C0E9] = 0
        select3_5Function(0x08, memory: memory, strobe: true)
        XCTAssertTrue(memory.iwmController.threePointFiveMotorOn)

        select3_5Function(0x09, memory: memory, strobe: true)
        XCTAssertFalse(memory.iwmController.threePointFiveMotorOn)
        XCTAssertEqual(memory[0x00C031], 0x40)
    }

    func testThreeAndHalfActionsAreIgnoredWhenMainMotorIsOff() {
        let memory = FlatMemoryBus()

        memory[0x00C031] = 0x40
        select3_5Function(0x08, memory: memory, strobe: true)

        XCTAssertFalse(memory.iwmController.threePointFiveMotorOn)
    }

    func testThreeAndHalfStatusReadsHighWhenMainMotorIsOff() throws {
        let memory = FlatMemoryBus()
        let media = try IIGSFloppyMedia(raw3_5: Array(repeating: 0, count: IIGSFloppyMedia.raw3_5ByteCount))
        memory.iwmController.mount(media)

        memory[0x00C031] = 0x40
        memory[0x00C0ED] = 0

        XCTAssertEqual(memory[0x00C0EE] & 0x80, 0x80)
    }

    func testThreeAndHalfModeReadsMountedEncodedMedia() throws {
        let memory = FlatMemoryBus()
        let media = try IIGSFloppyMedia(raw3_5: Array(repeating: 0, count: IIGSFloppyMedia.raw3_5ByteCount))
        memory.iwmController.mount(media)

        memory[0x00C031] = 0x40
        memory[0x00C0E9] = 0
        select3_5Function(0x08, memory: memory, strobe: true)
        memory[0x00C0EC] = 0
        memory[0x00C0EE] = 0

        let stream = (0..<430).map { _ -> UInt8 in
            defer { memory.idle(cycles: 16) }
            return memory[0x00C0EC]
        }

        XCTAssertNotNil(indexOf([0xD5, 0xAA, 0x96], in: stream))
    }

    func testThreeAndHalfCommandsStepAndSelectHeads() throws {
        let memory = FlatMemoryBus()
        let media = try IIGSFloppyMedia(raw3_5: Array(repeating: 0, count: IIGSFloppyMedia.raw3_5ByteCount))
        memory.iwmController.mount(media)

        memory[0x00C031] = 0x40
        memory[0x00C0E9] = 0
        select3_5Function(0x00, memory: memory, strobe: true)
        select3_5Function(0x04, memory: memory, strobe: true)
        XCTAssertEqual(memory.iwmController.drive1.quarterTrack, 2)

        _ = read3_5Status(selector: 0x03, memory: memory)
        XCTAssertEqual(memory.iwmController.drive1.quarterTrack, 3)

        select3_5Function(0x01, memory: memory, strobe: true)
        select3_5Function(0x04, memory: memory, strobe: true)
        XCTAssertEqual(memory.iwmController.drive1.quarterTrack, 1)
        XCTAssertEqual(read3_5Status(selector: 0x0A, memory: memory) & 0x80, 0x00)
    }

    func testThreeAndHalfStatusReportsMountedDriveAndDiskPresence() throws {
        let memory = FlatMemoryBus()
        let media = try IIGSFloppyMedia(
            raw3_5: Array(repeating: 0, count: IIGSFloppyMedia.raw3_5ByteCount),
            isWriteProtected: true
        )
        memory.iwmController.mount(media)

        XCTAssertEqual(read3_5Status(selector: 0x0F, memory: memory) & 0x80, 0x00)
        XCTAssertEqual(read3_5Status(selector: 0x02, memory: memory) & 0x80, 0x00)
        XCTAssertEqual(read3_5Status(selector: 0x06, memory: memory) & 0x80, 0x00)
        XCTAssertEqual(read3_5Status(selector: 0x0C, memory: memory) & 0x80, 0x00)
    }

    func testThreeAndHalfDiskSwitchedStatusTracksEjectAndClear() throws {
        let memory = FlatMemoryBus()
        let media = try IIGSFloppyMedia(raw3_5: Array(repeating: 0, count: IIGSFloppyMedia.raw3_5ByteCount))
        memory.iwmController.mount(media)

        XCTAssertEqual(read3_5Status(selector: 0x0C, memory: memory) & 0x80, 0x00)

        memory.iwmController.unmount(drive: 1)
        XCTAssertEqual(read3_5Status(selector: 0x0C, memory: memory) & 0x80, 0x80)

        select3_5Function(0x03, memory: memory, strobe: true)
        XCTAssertEqual(read3_5Status(selector: 0x0C, memory: memory) & 0x80, 0x00)
    }

    func testThreeAndHalfDiskSwitchedStatusClearsOnControllerReset() throws {
        let memory = FlatMemoryBus()
        let media = try IIGSFloppyMedia(raw3_5: Array(repeating: 0, count: IIGSFloppyMedia.raw3_5ByteCount))
        memory.iwmController.mount(media)

        memory.iwmController.unmount(drive: 1)
        XCTAssertEqual(read3_5Status(selector: 0x0C, memory: memory) & 0x80, 0x80)

        memory.iwmController.reset()
        XCTAssertEqual(read3_5Status(selector: 0x0C, memory: memory) & 0x80, 0x00)
    }

    func testThreeAndHalfStatusReportsEmptyDriveAsConnectedButEmpty() {
        let memory = FlatMemoryBus()

        XCTAssertEqual(read3_5Status(selector: 0x0F, memory: memory) & 0x80, 0x00)
        XCTAssertEqual(read3_5Status(selector: 0x02, memory: memory) & 0x80, 0x80)
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

    private func read3_5Status(selector: UInt8, memory: FlatMemoryBus) -> UInt8 {
        select3_5Function(selector, memory: memory, strobe: false)
        memory[0x00C0E9] = 0
        memory[0x00C0ED] = 0
        return memory[0x00C0EE]
    }

    private func select3_5Function(_ selector: UInt8, memory: FlatMemoryBus, strobe: Bool) {
        memory[0x00C031] = 0x40 | ((selector & 0x02) != 0 ? 0x80 : 0x00)
        setPhase(0, enabled: selector & 0x04 != 0, memory: memory)
        setPhase(1, enabled: selector & 0x08 != 0, memory: memory)
        setPhase(2, enabled: selector & 0x01 != 0, memory: memory)
        if strobe {
            memory[0x00C0E6] = 0
            memory[0x00C0E7] = 0
        }
    }

    private func setPhase(_ phase: Int, enabled: Bool, memory: FlatMemoryBus) {
        memory[UInt32(0x00C0E0 + (phase * 2) + (enabled ? 1 : 0))] = 0
    }

    private func decodedRaw3_5Track(quarterTrack: Int, sectorCount: Int, media: IIGSFloppyMedia) -> [Int: [UInt8]] {
        let stream = (0..<12_000).map { media.readTrackByte(quarterTrack: quarterTrack, offset: $0) }
        let decodeTable = raw3_5DecodeTable()
        var sectors: [Int: [UInt8]] = [:]
        var index = 0

        while index + 720 < stream.count, sectors.count < sectorCount {
            defer { index += 1 }
            guard stream[index] == 0xD5,
                  stream[index + 1] == 0xAA,
                  stream[index + 2] == 0xAD,
                  let sector = decodeTable[stream[index + 3]],
                  sector < sectorCount
            else {
                continue
            }

            let dataStart = index + 4
            let dataEnd = dataStart + 703
            guard dataEnd + 2 <= stream.count,
                  let decoded = decodeRaw3_5DataField(stream[dataStart..<dataEnd], table: decodeTable),
                  stream[dataEnd] == 0xDE,
                  stream[dataEnd + 1] == 0xAA
            else {
                continue
            }

            sectors[Int(sector)] = decoded
        }

        return sectors
    }

    private func decodeRaw3_5DataField(_ encoded: ArraySlice<UInt8>, table: [UInt8: UInt8]) -> [UInt8]? {
        let bytes = Array(encoded)
        guard bytes.count == 703 else {
            return nil
        }

        var cursor = 0
        func decodedByte() -> UInt8? {
            guard cursor < bytes.count else {
                return nil
            }
            defer { cursor += 1 }
            return table[bytes[cursor]]
        }

        var scratch0 = Array(repeating: UInt8(0), count: 175)
        var scratch1 = Array(repeating: UInt8(0), count: 175)
        var scratch2 = Array(repeating: UInt8(0), count: 175)

        for index in 0..<175 {
            guard let high = decodedByte(),
                  let low0 = decodedByte(),
                  let low1 = decodedByte()
            else {
                return nil
            }
            let low2: UInt8
            if index < 174 {
                guard let decodedLow2 = decodedByte() else {
                    return nil
                }
                low2 = decodedLow2
            } else {
                low2 = 0
            }

            scratch0[index] = ((high << 2) & 0xC0) | low0
            scratch1[index] = ((high << 4) & 0xC0) | low1
            scratch2[index] = ((high << 6) & 0xC0) | low2
        }

        var checksum0: UInt16 = 0
        var checksum1: UInt16 = 0
        var checksum2: UInt16 = 0
        var decoded = [UInt8]()
        decoded.reserveCapacity(524)

        for index in 0..<175 {
            checksum0 = (checksum0 & 0x00FF) << 1
            if checksum0 & 0x0100 != 0 {
                checksum0 += 1
            }

            let value0 = scratch0[index] ^ UInt8(truncatingIfNeeded: checksum0)
            checksum2 += UInt16(value0)
            if checksum0 & 0x0100 != 0 {
                checksum2 += 1
                checksum0 &= 0x00FF
            }
            decoded.append(value0)

            let value1 = scratch1[index] ^ UInt8(truncatingIfNeeded: checksum2)
            checksum1 += UInt16(value1)
            if checksum2 > 0x00FF {
                checksum1 += 1
                checksum2 &= 0x00FF
            }
            decoded.append(value1)

            if decoded.count == 524 {
                break
            }

            let value2 = scratch2[index] ^ UInt8(truncatingIfNeeded: checksum1)
            checksum0 += UInt16(value2)
            if checksum1 > 0x00FF {
                checksum0 += 1
                checksum1 &= 0x00FF
            }
            decoded.append(value2)
        }

        guard let checksumHigh = decodedByte(),
              let checksum2Low = decodedByte(),
              let checksum1Low = decodedByte(),
              let checksum0Low = decodedByte()
        else {
            return nil
        }

        let onDisk0 = ((checksumHigh << 6) & 0xC0) | checksum0Low
        let onDisk1 = ((checksumHigh << 4) & 0xC0) | checksum1Low
        let onDisk2 = ((checksumHigh << 2) & 0xC0) | checksum2Low
        guard onDisk0 == UInt8(truncatingIfNeeded: checksum0),
              onDisk1 == UInt8(truncatingIfNeeded: checksum1),
              onDisk2 == UInt8(truncatingIfNeeded: checksum2)
        else {
            return nil
        }

        return decoded
    }

    private func raw3_5DecodeTable() -> [UInt8: UInt8] {
        let encoded: [UInt8] = [
            0x96, 0x97, 0x9A, 0x9B, 0x9D, 0x9E, 0x9F, 0xA6,
            0xA7, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF, 0xB2, 0xB3,
            0xB4, 0xB5, 0xB6, 0xB7, 0xB9, 0xBA, 0xBB, 0xBC,
            0xBD, 0xBE, 0xBF, 0xCB, 0xCD, 0xCE, 0xCF, 0xD3,
            0xD6, 0xD7, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE,
            0xDF, 0xE5, 0xE6, 0xE7, 0xE9, 0xEA, 0xEB, 0xEC,
            0xED, 0xEE, 0xEF, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6,
            0xF7, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF
        ]
        return Dictionary(uniqueKeysWithValues: encoded.enumerated().map { (UInt8($0.element), UInt8($0.offset)) })
    }

    private func indexOf(_ needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else {
            return nil
        }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle {
                return start
            }
        }
        return nil
    }
}
