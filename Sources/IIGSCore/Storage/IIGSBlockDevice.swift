public enum IIGSStorageError: Error, Equatable, Sendable {
    case invalidBlockSize(Int)
    case invalid2IMG
    case invalidFloppySize(Int)
    case invalidWOZ
    case dataOutOfBounds(offset: Int, length: Int)
    case blockOutOfRange(UInt32)
    case wrongTransferSize(Int)
    case writeProtected
    case noDevice(UInt8)
    case unsupportedCommand(UInt8)
}

public final class IIGSBlockDevice {
    public static let blockSize = 512

    private var storage: [UInt8]

    public let name: String
    public let isWriteProtected: Bool

    public var byteCount: Int {
        storage.count
    }

    public var blockCount: UInt32 {
        UInt32(storage.count / Self.blockSize)
    }

    public init(bytes: [UInt8], name: String = "BLOCK DEVICE", isWriteProtected: Bool = false) throws {
        guard bytes.count > 0, bytes.count % Self.blockSize == 0 else {
            throw IIGSStorageError.invalidBlockSize(bytes.count)
        }
        self.storage = bytes
        self.name = name
        self.isWriteProtected = isWriteProtected
    }

    public static func raw(bytes: [UInt8], name: String = "RAW BLOCK DEVICE", isWriteProtected: Bool = false) throws -> IIGSBlockDevice {
        try IIGSBlockDevice(bytes: bytes, name: name, isWriteProtected: isWriteProtected)
    }

    public static func twoIMG(bytes: [UInt8], name: String = "2IMG BLOCK DEVICE") throws -> IIGSBlockDevice {
        let image = try IIGS2IMGImage(bytes: bytes)
        return try IIGSBlockDevice(bytes: image.data, name: name, isWriteProtected: image.isWriteProtected)
    }

    public func readBlock(_ block: UInt32) throws -> [UInt8] {
        let range = try byteRange(for: block)
        return Array(storage[range])
    }

    public func writeBlock(_ block: UInt32, bytes: [UInt8]) throws {
        guard !isWriteProtected else {
            throw IIGSStorageError.writeProtected
        }
        guard bytes.count == Self.blockSize else {
            throw IIGSStorageError.wrongTransferSize(bytes.count)
        }
        let range = try byteRange(for: block)
        storage.replaceSubrange(range, with: bytes)
    }

    public func format(fillByte: UInt8 = 0) throws {
        guard !isWriteProtected else {
            throw IIGSStorageError.writeProtected
        }
        storage.replaceSubrange(storage.indices, with: repeatElement(fillByte, count: storage.count))
    }

    private func byteRange(for block: UInt32) throws -> Range<Int> {
        guard block < blockCount else {
            throw IIGSStorageError.blockOutOfRange(block)
        }
        let start = Int(block) * Self.blockSize
        return start..<(start + Self.blockSize)
    }
}
