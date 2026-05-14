public struct IIGS2IMGImage: Equatable, Sendable {
    public static let writeProtectedFlag: UInt32 = 0x8000_0000

    public let creator: UInt32
    public let imageFormat: UInt32
    public let flags: UInt32
    public let declaredBlockCount: UInt32
    public let dataOffset: UInt32
    public let dataLength: UInt32
    public let data: [UInt8]

    public var isWriteProtected: Bool {
        flags & Self.writeProtectedFlag != 0
    }

    public init(bytes: [UInt8]) throws {
        guard bytes.count >= 64,
              bytes[0] == 0x32,
              bytes[1] == 0x49,
              bytes[2] == 0x4D,
              bytes[3] == 0x47
        else {
            throw IIGSStorageError.invalid2IMG
        }

        self.creator = Self.readLittle32(bytes, at: 4)
        self.imageFormat = Self.readLittle32(bytes, at: 12)
        self.flags = Self.readLittle32(bytes, at: 16)
        self.declaredBlockCount = Self.readLittle32(bytes, at: 20)
        self.dataOffset = Self.readLittle32(bytes, at: 24)

        let declaredLength = Self.readLittle32(bytes, at: 28)
        let offset = Int(dataOffset)
        let length = Self.usableDataLength(declaredLength, offset: offset, totalSize: bytes.count)

        guard length > 0,
              length % IIGSBlockDevice.blockSize == 0,
              offset >= 0,
              offset <= bytes.count,
              offset + length <= bytes.count
        else {
            throw IIGSStorageError.dataOutOfBounds(offset: offset, length: length)
        }

        self.dataLength = UInt32(length)
        self.data = Array(bytes[offset..<(offset + length)])
    }

    private static func usableDataLength(_ declaredLength: UInt32, offset: Int, totalSize: Int) -> Int {
        let length = Int(declaredLength)
        if offset >= 0, offset + length <= totalSize {
            return length
        }

        let swapped = Int(byteSwapped(declaredLength))
        if offset >= 0, offset + swapped <= totalSize {
            return swapped
        }

        return length
    }

    private static func readLittle32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func byteSwapped(_ value: UInt32) -> UInt32 {
        ((value & 0x0000_00FF) << 24)
            | ((value & 0x0000_FF00) << 8)
            | ((value & 0x00FF_0000) >> 8)
            | ((value & 0xFF00_0000) >> 24)
    }
}
