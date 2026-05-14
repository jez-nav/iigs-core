public enum IIGSSmartPortErrorCode {
    public static let ok: UInt8 = 0x00
    public static let badCommand: UInt8 = 0x01
    public static let ioError: UInt8 = 0x27
    public static let noDevice: UInt8 = 0x28
    public static let writeProtected: UInt8 = 0x2B
    public static let badBlock: UInt8 = 0x2D
}

public enum IIGSSmartPortFirmwareEntry {
    public static let slot7Standard: UInt16 = 0xC70A
    public static let slot7Extended: UInt16 = 0xC70D
}

public struct IIGSSmartPortResult: Equatable, Sendable {
    public let carrySet: Bool
    public let accumulator: UInt8
    public let x: UInt8
    public let y: UInt8

    public static let success = IIGSSmartPortResult(carrySet: false, accumulator: 0, x: 0, y: 0)

    public static func failure(_ errorCode: UInt8) -> IIGSSmartPortResult {
        IIGSSmartPortResult(carrySet: true, accumulator: errorCode, x: 0, y: 0)
    }
}

public final class IIGSSmartPortController {
    public private(set) var units: [UInt8: IIGSBlockDevice] = [:]

    public init() {}

    public func mount(_ device: IIGSBlockDevice, unit: UInt8 = 1) {
        precondition((1...127).contains(unit))
        units[unit] = device
    }

    public func unmount(unit: UInt8) {
        units.removeValue(forKey: unit)
    }

    public func device(unit: UInt8) -> IIGSBlockDevice? {
        units[unit]
    }

    @discardableResult
    public func execute(command: UInt8, parameterListAddress: UInt32, memory: IIGSBus) -> IIGSSmartPortResult {
        let extended = command & 0x40 != 0
        let baseCommand = command & 0x3F

        switch baseCommand {
        case 0x00:
            return performStatus(parameterListAddress: parameterListAddress, memory: memory, extended: extended)
        case 0x01:
            return performRead(parameterListAddress: parameterListAddress, memory: memory, extended: extended)
        case 0x02:
            return performWrite(parameterListAddress: parameterListAddress, memory: memory, extended: extended)
        case 0x03:
            return performFormat(parameterListAddress: parameterListAddress, memory: memory)
        case 0x04:
            return .success
        default:
            return .failure(IIGSSmartPortErrorCode.badCommand)
        }
    }

    @discardableResult
    public func executeFirmwareEntry(_ entryAddress: UInt16, command: UInt8, parameterListAddress: UInt32, memory: IIGSBus) -> IIGSSmartPortResult {
        switch entryAddress {
        case IIGSSmartPortFirmwareEntry.slot7Standard:
            return execute(command: command & 0x3F, parameterListAddress: parameterListAddress, memory: memory)
        case IIGSSmartPortFirmwareEntry.slot7Extended:
            return execute(command: command | 0x40, parameterListAddress: parameterListAddress, memory: memory)
        default:
            return .failure(IIGSSmartPortErrorCode.badCommand)
        }
    }

    private func performStatus(parameterListAddress: UInt32, memory: IIGSBus, extended: Bool) -> IIGSSmartPortResult {
        let unit = memory.read8(at: parameterListAddress &+ 1)
        let statusAddress = readPointer(parameterListAddress &+ 2, memory: memory, extended: extended)
        let statusCodeOffset: UInt32 = extended ? 5 : 4
        let statusCode = memory.read8(at: parameterListAddress &+ statusCodeOffset)

        if unit == 0 {
            writeDriverStatus(to: statusAddress, memory: memory)
            return .success
        }

        guard let device = units[unit] else {
            return .failure(IIGSSmartPortErrorCode.noDevice)
        }

        switch statusCode {
        case 0x00:
            writeUnitStatus(device, to: statusAddress, memory: memory)
            return .success
        case 0x03:
            writeDeviceInformationBlock(device, to: statusAddress, memory: memory)
            return .success
        default:
            return .failure(IIGSSmartPortErrorCode.badCommand)
        }
    }

    private func performRead(parameterListAddress: UInt32, memory: IIGSBus, extended: Bool) -> IIGSSmartPortResult {
        let unit = memory.read8(at: parameterListAddress &+ 1)
        guard let device = units[unit] else {
            return .failure(IIGSSmartPortErrorCode.noDevice)
        }

        let bufferAddress = readPointer(parameterListAddress &+ 2, memory: memory, extended: extended)
        let block = readBlockNumber(parameterListAddress: parameterListAddress, memory: memory, extended: extended)

        do {
            let bytes = try device.readBlock(block)
            for (offset, value) in bytes.enumerated() {
                memory.write8(value, at: bufferAddress &+ UInt32(offset))
            }
            return .success
        } catch IIGSStorageError.blockOutOfRange {
            return .failure(IIGSSmartPortErrorCode.badBlock)
        } catch {
            return .failure(IIGSSmartPortErrorCode.ioError)
        }
    }

    private func performWrite(parameterListAddress: UInt32, memory: IIGSBus, extended: Bool) -> IIGSSmartPortResult {
        let unit = memory.read8(at: parameterListAddress &+ 1)
        guard let device = units[unit] else {
            return .failure(IIGSSmartPortErrorCode.noDevice)
        }

        let bufferAddress = readPointer(parameterListAddress &+ 2, memory: memory, extended: extended)
        let block = readBlockNumber(parameterListAddress: parameterListAddress, memory: memory, extended: extended)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(IIGSBlockDevice.blockSize)
        for offset in 0..<IIGSBlockDevice.blockSize {
            bytes.append(memory.read8(at: bufferAddress &+ UInt32(offset)))
        }

        do {
            try device.writeBlock(block, bytes: bytes)
            return .success
        } catch IIGSStorageError.writeProtected {
            return .failure(IIGSSmartPortErrorCode.writeProtected)
        } catch IIGSStorageError.blockOutOfRange {
            return .failure(IIGSSmartPortErrorCode.badBlock)
        } catch {
            return .failure(IIGSSmartPortErrorCode.ioError)
        }
    }

    private func performFormat(parameterListAddress: UInt32, memory: IIGSBus) -> IIGSSmartPortResult {
        let unit = memory.read8(at: parameterListAddress &+ 1)
        guard let device = units[unit] else {
            return .failure(IIGSSmartPortErrorCode.noDevice)
        }

        do {
            try device.format()
            return .success
        } catch IIGSStorageError.writeProtected {
            return .failure(IIGSSmartPortErrorCode.writeProtected)
        } catch {
            return .failure(IIGSSmartPortErrorCode.ioError)
        }
    }

    private func writeDriverStatus(to address: UInt32, memory: IIGSBus) {
        memory.write8(UInt8(min(units.count, 127)), at: address)
        memory.write8(0x00, at: address &+ 1)
        memory.write8(0x00, at: address &+ 2)
        memory.write8(0x00, at: address &+ 3)
    }

    private func writeUnitStatus(_ device: IIGSBlockDevice, to address: UInt32, memory: IIGSBus) {
        memory.write8(statusByte(for: device), at: address)
        writeLittle24(device.blockCount, to: address &+ 1, memory: memory)
    }

    private func writeDeviceInformationBlock(_ device: IIGSBlockDevice, to address: UInt32, memory: IIGSBus) {
        memory.write8(statusByte(for: device), at: address)
        writeLittle32(device.blockCount, to: address &+ 1, memory: memory)
        memory.write8(0x03, at: address &+ 5)
        memory.write8(device.isWriteProtected ? 0x00 : 0x01, at: address &+ 6)

        let allNameBytes = Array(device.name.uppercased().utf8)
        let nameBytes = Array(allNameBytes.prefix(16))
        memory.write8(UInt8(nameBytes.count), at: address &+ 7)
        for offset in 0..<16 {
            let value = offset < nameBytes.count ? nameBytes[offset] : 0x20
            memory.write8(value, at: address &+ 8 &+ UInt32(offset))
        }
    }

    private func statusByte(for device: IIGSBlockDevice) -> UInt8 {
        device.isWriteProtected ? 0xF8 : 0x78
    }

    private func readPointer(_ address: UInt32, memory: IIGSBus, extended: Bool) -> UInt32 {
        let low = UInt32(memory.read8(at: address))
        let high = UInt32(memory.read8(at: address &+ 1)) << 8
        if !extended {
            return low | high
        }
        let bank = UInt32(memory.read8(at: address &+ 2)) << 16
        return bank | high | low
    }

    private func readBlockNumber(parameterListAddress: UInt32, memory: IIGSBus, extended: Bool) -> UInt32 {
        let start = parameterListAddress &+ (extended ? 5 : 4)
        let low = UInt32(memory.read8(at: start))
        let mid = UInt32(memory.read8(at: start &+ 1)) << 8
        let high = UInt32(memory.read8(at: start &+ 2)) << 16
        if !extended {
            return low | mid | high
        }
        let top = UInt32(memory.read8(at: start &+ 3)) << 24
        return top | high | mid | low
    }

    private func writeLittle24(_ value: UInt32, to address: UInt32, memory: IIGSBus) {
        memory.write8(UInt8(value & 0xFF), at: address)
        memory.write8(UInt8((value >> 8) & 0xFF), at: address &+ 1)
        memory.write8(UInt8((value >> 16) & 0xFF), at: address &+ 2)
    }

    private func writeLittle32(_ value: UInt32, to address: UInt32, memory: IIGSBus) {
        writeLittle24(value, to: address, memory: memory)
        memory.write8(UInt8((value >> 24) & 0xFF), at: address &+ 3)
    }
}
