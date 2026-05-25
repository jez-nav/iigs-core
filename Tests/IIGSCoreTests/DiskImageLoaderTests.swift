import XCTest
@testable import IIGSCore

final class DiskImageLoaderTests: XCTestCase {
    func test2IMGLoadsAndMountsAsSmartPortDevice() throws {
        let image = make2IMG(payload: Array(repeating: 0xA5, count: 1_024), format: 1, writeProtected: true)
        let loaded = try IIGSDiskImageLoader.load(
            bytes: image,
            name: "boot.2mg",
            fileExtension: "2mg",
            target: .smartPort(unit: 1)
        )
        let machine = IIGSMachine()

        let info = try machine.mountDiskImage(loaded)

        XCTAssertEqual(info.target, .smartPort(unit: 1))
        XCTAssertEqual(info.kind, .twoIMG(format: 1))
        XCTAssertEqual(info.blockCount, 2)
        XCTAssertTrue(info.isWriteProtected)
        XCTAssertEqual(machine.smartPortController.device(unit: 1)?.blockCount, 2)
        XCTAssertEqual(machine.mountedDiskInfo(for: .smartPort(unit: 1))?.name, "boot.2mg")
    }

    func testRawPO140KLoadsAndMountsAsSlot6Drive() throws {
        let bytes = Array(repeating: UInt8(0), count: IIGSFloppyMedia.raw5_25ByteCount)
        let loaded = try IIGSDiskImageLoader.load(
            bytes: bytes,
            name: "tools.po",
            fileExtension: "po",
            target: .floppy5_25(drive: 1)
        )
        let machine = IIGSMachine()

        let info = try machine.mountDiskImage(loaded)

        XCTAssertEqual(info.target, .floppy5_25(drive: 1))
        XCTAssertEqual(info.kind, .raw5_25(sectorOrder: .prodos))
        XCTAssertNotNil(machine.memory.iwmController.drive1.media)
        XCTAssertEqual(machine.mountedDiskInfo(for: .floppy5_25(drive: 1))?.name, "tools.po")
    }

    func testEjectRemovesSmartPortAndFloppyMedia() throws {
        let machine = IIGSMachine()
        let block = try IIGSDiskImageLoader.load(
            bytes: Array(repeating: 0, count: 512),
            name: "hard.po",
            fileExtension: "po",
            target: .smartPort(unit: 1)
        )
        let floppy = try IIGSDiskImageLoader.load(
            bytes: Array(repeating: 0, count: IIGSFloppyMedia.raw5_25ByteCount),
            name: "boot.do",
            fileExtension: "do",
            target: .floppy5_25(drive: 2)
        )

        try machine.mountDiskImage(block)
        try machine.mountDiskImage(floppy)
        machine.ejectDisk(target: .smartPort(unit: 1))
        machine.ejectDisk(target: .floppy5_25(drive: 2))

        XCTAssertNil(machine.smartPortController.device(unit: 1))
        XCTAssertNil(machine.memory.iwmController.drive2.media)
        XCTAssertNil(machine.mountedDiskInfo(for: .smartPort(unit: 1)))
        XCTAssertNil(machine.mountedDiskInfo(for: .floppy5_25(drive: 2)))
    }

    func testWOZLoadsForSlot6Drive() throws {
        var image: [UInt8] = [0x57, 0x4F, 0x5A, 0x32, 0xFF, 0x0A, 0x0D, 0x0A, 0, 0, 0, 0]
        var tmap = Array(repeating: UInt8(0xFF), count: 160)
        tmap[0] = 0
        appendChunk("TMAP", payload: tmap, to: &image)
        appendChunk("TRKS", payload: [0xD5, 0xAA, 0x96], to: &image)

        let loaded = try IIGSDiskImageLoader.load(
            bytes: image,
            name: "game.woz",
            fileExtension: "woz",
            target: .floppy5_25(drive: 1)
        )

        XCTAssertEqual(loaded.info.kind, .woz(version: 2))
        XCTAssertEqual(loaded.info.byteCount, image.count)
    }

    private func make2IMG(payload: [UInt8], format: UInt32, writeProtected: Bool = false) -> [UInt8] {
        var image = Array(repeating: UInt8(0), count: 64 + payload.count)
        image[0] = 0x32
        image[1] = 0x49
        image[2] = 0x4D
        image[3] = 0x47
        writeLittle32(format, to: 12, in: &image)
        writeLittle32(writeProtected ? IIGS2IMGImage.writeProtectedFlag : 0, to: 16, in: &image)
        writeLittle32(UInt32(payload.count / IIGSBlockDevice.blockSize), to: 20, in: &image)
        writeLittle32(64, to: 24, in: &image)
        writeLittle32(UInt32(payload.count), to: 28, in: &image)
        image.replaceSubrange(64..<image.count, with: payload)
        return image
    }

    private func appendChunk(_ name: String, payload: [UInt8], to image: inout [UInt8]) {
        image.append(contentsOf: name.utf8)
        writeLittle32(UInt32(payload.count), to: image.count, appendingTo: &image)
        image.append(contentsOf: payload)
    }

    private func writeLittle32(_ value: UInt32, to offset: Int, in bytes: inout [UInt8]) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private func writeLittle32(_ value: UInt32, to offset: Int, appendingTo bytes: inout [UInt8]) {
        precondition(offset == bytes.count)
        bytes.append(UInt8(value & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8((value >> 16) & 0xFF))
        bytes.append(UInt8((value >> 24) & 0xFF))
    }
}
