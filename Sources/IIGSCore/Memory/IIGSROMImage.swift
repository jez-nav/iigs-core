public enum IIGSROMVersion: Equatable, Sendable {
    case rom01
    case rom03

    public var expectedSize: Int {
        switch self {
        case .rom01:
            0x020000
        case .rom03:
            0x040000
        }
    }

    public var mappedStartBank: UInt8 {
        switch self {
        case .rom01:
            0xFE
        case .rom03:
            0xFC
        }
    }

    var mappedStartAddress: UInt32 {
        UInt32(mappedStartBank) << 16
    }
}

public enum IIGSROMError: Error, Equatable, CustomStringConvertible {
    case invalidSize(Int)

    public var description: String {
        switch self {
        case let .invalidSize(size):
            return "Unsupported Apple IIgs ROM size: \(size) bytes"
        }
    }
}

public struct IIGSROMImage: Equatable, Sendable {
    public let version: IIGSROMVersion
    private let bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        switch bytes.count {
        case IIGSROMVersion.rom01.expectedSize:
            try self.init(bytes: bytes, version: .rom01)
        case IIGSROMVersion.rom03.expectedSize:
            try self.init(bytes: bytes, version: .rom03)
        default:
            throw IIGSROMError.invalidSize(bytes.count)
        }
    }

    public init(bytes: [UInt8], version: IIGSROMVersion) throws {
        guard bytes.count == version.expectedSize else {
            throw IIGSROMError.invalidSize(bytes.count)
        }
        self.version = version
        self.bytes = bytes
    }

    public var size: Int {
        bytes.count
    }

    public func byte(at offset: Int) -> UInt8 {
        precondition(offset >= 0 && offset < bytes.count)
        return bytes[offset]
    }

    func byte(mappedAt address: UInt32) -> UInt8? {
        let address = masked24(address)
        guard address >= version.mappedStartAddress else {
            return nil
        }
        let offset = Int(address - version.mappedStartAddress)
        guard offset < bytes.count else {
            return nil
        }
        return bytes[offset]
    }

    func contains(mappedAddress address: UInt32) -> Bool {
        byte(mappedAt: address) != nil
    }

    func byte(languageCardAddress lowAddress: UInt16) -> UInt8 {
        bytes[bytes.count - 0x10000 + Int(lowAddress)]
    }
}
