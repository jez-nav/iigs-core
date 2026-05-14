import XCTest
@testable import IIGSCore

final class StoragePhase8Tests: XCTestCase {
    func testRaw800KImageMountsAs1600Blocks() throws {
        let bytes = Array(repeating: UInt8(0), count: 800 * 1024)

        let device = try IIGSBlockDevice.raw(bytes: bytes)

        XCTAssertEqual(device.byteCount, 819_200)
        XCTAssertEqual(device.blockCount, 1_600)
    }

    func testRaw32MBImageMountsAs65536Blocks() throws {
        let bytes = Array(repeating: UInt8(0), count: 32 * 1024 * 1024)

        let device = try IIGSBlockDevice.raw(bytes: bytes)

        XCTAssertEqual(device.blockCount, 65_536)
    }

    func test2IMGParserHonorsPayloadOffsetLengthAndWriteProtectFlag() throws {
        var image = Array(repeating: UInt8(0), count: 96 + 1_024)
        image[0] = 0x32
        image[1] = 0x49
        image[2] = 0x4D
        image[3] = 0x47
        writeLittle32(1, to: 12, in: &image)
        writeLittle32(IIGS2IMGImage.writeProtectedFlag, to: 16, in: &image)
        writeLittle32(2, to: 20, in: &image)
        writeLittle32(96, to: 24, in: &image)
        writeLittle32(1_024, to: 28, in: &image)
        image[96] = 0xA5
        image[96 + 512] = 0x5A

        let parsed = try IIGS2IMGImage(bytes: image)
        let device = try IIGSBlockDevice.twoIMG(bytes: image)

        XCTAssertTrue(parsed.isWriteProtected)
        XCTAssertEqual(parsed.dataLength, 1_024)
        XCTAssertEqual(try device.readBlock(0)[0], 0xA5)
        XCTAssertEqual(try device.readBlock(1)[0], 0x5A)
        XCTAssertTrue(device.isWriteProtected)
    }

    func testSmartPortReadBlockTransfers512BytesIntoMemory() throws {
        let machine = IIGSMachine()
        var bytes = Array(repeating: UInt8(0), count: 1_024)
        for offset in 0..<IIGSBlockDevice.blockSize {
            bytes[512 + offset] = UInt8(offset & 0xFF)
        }
        let device = try IIGSBlockDevice.raw(bytes: bytes, name: "TESTDISK")
        machine.mountSmartPortDevice(device)
        writeStandardBlockCommand(unit: 1, buffer: 0x2000, block: 1, at: 0x1000, memory: machine.memory)

        let result = machine.executeSmartPort(command: 0x01, parameterListAddress: 0x1000)

        XCTAssertFalse(result.carrySet)
        XCTAssertEqual(machine.memory.peek8(at: 0x2000), 0x00)
        XCTAssertEqual(machine.memory.peek8(at: 0x2001), 0x01)
        XCTAssertEqual(machine.memory.peek8(at: 0x20FF), 0xFF)
    }

    func testExtendedSmartPortReadUses24BitBufferAnd32BitBlock() throws {
        let machine = IIGSMachine()
        var bytes = Array(repeating: UInt8(0), count: 1_024)
        bytes[512] = 0xCD
        let device = try IIGSBlockDevice.raw(bytes: bytes)
        machine.mountSmartPortDevice(device)
        writeExtendedBlockCommand(unit: 1, buffer: 0x022000, block: 1, at: 0x1100, memory: machine.memory)

        let result = machine.executeSmartPort(command: 0x41, parameterListAddress: 0x1100)

        XCTAssertFalse(result.carrySet)
        XCTAssertEqual(machine.memory.peek8(at: 0x022000), 0xCD)
    }

    func testSlot7ExtendedFirmwareEntryDispatchesExtendedCommand() throws {
        let machine = IIGSMachine()
        var bytes = Array(repeating: UInt8(0), count: 512)
        bytes[0] = 0x7E
        let device = try IIGSBlockDevice.raw(bytes: bytes)
        machine.mountSmartPortDevice(device)
        writeExtendedBlockCommand(unit: 1, buffer: 0x032000, block: 0, at: 0x1100, memory: machine.memory)

        let result = machine.executeSmartPortFirmwareEntry(
            IIGSSmartPortFirmwareEntry.slot7Extended,
            command: 0x01,
            parameterListAddress: 0x1100
        )

        XCTAssertFalse(result.carrySet)
        XCTAssertEqual(machine.memory.peek8(at: 0x032000), 0x7E)
    }

    func testSmartPortWriteBlockCopiesFromMemoryIntoDevice() throws {
        let machine = IIGSMachine()
        let device = try IIGSBlockDevice.raw(bytes: Array(repeating: 0, count: 1_024))
        machine.mountSmartPortDevice(device)
        for offset in 0..<IIGSBlockDevice.blockSize {
            machine.memory.write8(UInt8((offset + 3) & 0xFF), at: 0x2400 + UInt32(offset))
        }
        writeStandardBlockCommand(unit: 1, buffer: 0x2400, block: 1, at: 0x1000, memory: machine.memory)

        let result = machine.executeSmartPort(command: 0x02, parameterListAddress: 0x1000)

        XCTAssertFalse(result.carrySet)
        let block = try device.readBlock(1)
        XCTAssertEqual(block[0], 0x03)
        XCTAssertEqual(block[1], 0x04)
        XCTAssertEqual(block[255], 0x02)
    }

    func testSmartPortWriteProtectedDeviceReturnsErrorAndDoesNotMutate() throws {
        let machine = IIGSMachine()
        var bytes = Array(repeating: UInt8(0), count: 512)
        bytes[0] = 0x11
        let device = try IIGSBlockDevice.raw(bytes: bytes, isWriteProtected: true)
        machine.mountSmartPortDevice(device)
        machine.memory.write8(0x99, at: 0x2400)
        writeStandardBlockCommand(unit: 1, buffer: 0x2400, block: 0, at: 0x1000, memory: machine.memory)

        let result = machine.executeSmartPort(command: 0x02, parameterListAddress: 0x1000)

        XCTAssertTrue(result.carrySet)
        XCTAssertEqual(result.accumulator, IIGSSmartPortErrorCode.writeProtected)
        XCTAssertEqual(try device.readBlock(0)[0], 0x11)
    }

    func testSmartPortStatusReportsUnitBlockCountAndProtection() throws {
        let machine = IIGSMachine()
        let device = try IIGSBlockDevice.raw(bytes: Array(repeating: 0, count: 1_600 * 512), isWriteProtected: true)
        machine.mountSmartPortDevice(device)
        writeStatusCommand(unit: 1, buffer: 0x3000, code: 0, at: 0x1000, memory: machine.memory)

        let result = machine.executeSmartPort(command: 0x00, parameterListAddress: 0x1000)

        XCTAssertFalse(result.carrySet)
        XCTAssertEqual(machine.memory.peek8(at: 0x3000), 0xF8)
        XCTAssertEqual(readLittle24(at: 0x3001, memory: machine.memory), 1_600)
    }

    func testSmartPortDeviceInformationBlockIncludesName() throws {
        let machine = IIGSMachine()
        let device = try IIGSBlockDevice.raw(bytes: Array(repeating: 0, count: 512), name: "boot")
        machine.mountSmartPortDevice(device)
        writeStatusCommand(unit: 1, buffer: 0x3100, code: 3, at: 0x1000, memory: machine.memory)

        let result = machine.executeSmartPort(command: 0x00, parameterListAddress: 0x1000)

        XCTAssertFalse(result.carrySet)
        XCTAssertEqual(machine.memory.peek8(at: 0x3105), 0x03)
        XCTAssertEqual(machine.memory.peek8(at: 0x3106), 0x01)
        XCTAssertEqual(machine.memory.peek8(at: 0x3107), 4)
        XCTAssertEqual(machine.memory.peek8(at: 0x3108), 0x42)
        XCTAssertEqual(machine.memory.peek8(at: 0x3109), 0x4F)
        XCTAssertEqual(machine.memory.peek8(at: 0x310A), 0x4F)
        XCTAssertEqual(machine.memory.peek8(at: 0x310B), 0x54)
    }

    func testSmartPortFormatZerosWritableMedia() throws {
        let machine = IIGSMachine()
        let device = try IIGSBlockDevice.raw(bytes: Array(repeating: 0xAA, count: 512))
        machine.mountSmartPortDevice(device)
        machine.memory.write8(1, at: 0x1001)

        let result = machine.executeSmartPort(command: 0x03, parameterListAddress: 0x1000)

        XCTAssertFalse(result.carrySet)
        XCTAssertEqual(try device.readBlock(0)[0], 0x00)
        XCTAssertEqual(try device.readBlock(0)[511], 0x00)
    }

    func testUnsupportedSmartPortCommandReturnsBadCommand() {
        let machine = IIGSMachine()

        let result = machine.executeSmartPort(command: 0x4B, parameterListAddress: 0x1000)

        XCTAssertTrue(result.carrySet)
        XCTAssertEqual(result.accumulator, IIGSSmartPortErrorCode.badCommand)
    }

    private func writeStatusCommand(unit: UInt8, buffer: UInt16, code: UInt8, at address: UInt32, memory: FlatMemoryBus) {
        memory.write8(3, at: address)
        memory.write8(unit, at: address + 1)
        memory.write8(UInt8(buffer & 0xFF), at: address + 2)
        memory.write8(UInt8(buffer >> 8), at: address + 3)
        memory.write8(code, at: address + 4)
    }

    private func writeStandardBlockCommand(unit: UInt8, buffer: UInt16, block: UInt32, at address: UInt32, memory: FlatMemoryBus) {
        memory.write8(3, at: address)
        memory.write8(unit, at: address + 1)
        memory.write8(UInt8(buffer & 0xFF), at: address + 2)
        memory.write8(UInt8(buffer >> 8), at: address + 3)
        memory.write8(UInt8(block & 0xFF), at: address + 4)
        memory.write8(UInt8((block >> 8) & 0xFF), at: address + 5)
        memory.write8(UInt8((block >> 16) & 0xFF), at: address + 6)
    }

    private func writeExtendedBlockCommand(unit: UInt8, buffer: UInt32, block: UInt32, at address: UInt32, memory: FlatMemoryBus) {
        memory.write8(4, at: address)
        memory.write8(unit, at: address + 1)
        memory.write8(UInt8(buffer & 0xFF), at: address + 2)
        memory.write8(UInt8((buffer >> 8) & 0xFF), at: address + 3)
        memory.write8(UInt8((buffer >> 16) & 0xFF), at: address + 4)
        memory.write8(UInt8(block & 0xFF), at: address + 5)
        memory.write8(UInt8((block >> 8) & 0xFF), at: address + 6)
        memory.write8(UInt8((block >> 16) & 0xFF), at: address + 7)
        memory.write8(UInt8((block >> 24) & 0xFF), at: address + 8)
    }

    private func writeLittle32(_ value: UInt32, to offset: Int, in bytes: inout [UInt8]) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private func readLittle24(at address: UInt32, memory: FlatMemoryBus) -> UInt32 {
        UInt32(memory.peek8(at: address))
            | (UInt32(memory.peek8(at: address + 1)) << 8)
            | (UInt32(memory.peek8(at: address + 2)) << 16)
    }
}
