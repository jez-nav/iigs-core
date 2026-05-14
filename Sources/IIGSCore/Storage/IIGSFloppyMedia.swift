public enum IIGSFloppyMediaKind: Equatable, Sendable {
    case raw5_25
    case raw3_5
    case nib
    case woz(version: UInt8)
}

public enum IIGSFloppySectorOrder: Equatable, Sendable {
    case physical
    case dos33
    case prodos
}

public struct IIGSWOZImage: Equatable, Sendable {
    public let version: UInt8
    public let trackMap: [UInt8]
    public let trackData: [[UInt8]]

    public init(bytes: [UInt8]) throws {
        guard bytes.count >= 12 else {
            throw IIGSStorageError.invalidWOZ
        }

        if bytes[0] == 0x57, bytes[1] == 0x4F, bytes[2] == 0x5A, bytes[3] == 0x31 {
            version = 1
        } else if bytes[0] == 0x57, bytes[1] == 0x4F, bytes[2] == 0x5A, bytes[3] == 0x32 {
            version = 2
        } else {
            throw IIGSStorageError.invalidWOZ
        }

        var parsedTrackMap: [UInt8] = []
        var parsedTracks: [[UInt8]] = []
        var offset = 12
        while offset + 8 <= bytes.count {
            let chunkSize = Self.readLittle32(bytes, at: offset + 4)
            let chunkStart = offset + 8
            let chunkEnd = chunkStart + Int(chunkSize)
            guard chunkEnd <= bytes.count else {
                throw IIGSStorageError.invalidWOZ
            }

            let chunk = Array(bytes[chunkStart..<chunkEnd])
            if Self.chunkName(bytes, at: offset, equals: [0x54, 0x4D, 0x41, 0x50]) {
                parsedTrackMap = chunk
            } else if Self.chunkName(bytes, at: offset, equals: [0x54, 0x52, 0x4B, 0x53]) {
                parsedTracks = Self.splitTrackChunk(chunk)
            }
            offset = chunkEnd
        }

        guard !parsedTrackMap.isEmpty else {
            throw IIGSStorageError.invalidWOZ
        }

        self.trackMap = parsedTrackMap
        self.trackData = parsedTracks
    }

    public func trackIndex(forQuarterTrack quarterTrack: Int) -> UInt8? {
        guard quarterTrack >= 0, quarterTrack < trackMap.count else {
            return nil
        }
        let index = trackMap[quarterTrack]
        return index == 0xFF ? nil : index
    }

    private static func splitTrackChunk(_ chunk: [UInt8]) -> [[UInt8]] {
        guard !chunk.isEmpty else {
            return []
        }
        if chunk.count <= IIGSFloppyMedia.nibTrackSize {
            return [chunk]
        }
        var tracks: [[UInt8]] = []
        var offset = 0
        while offset < chunk.count {
            let next = min(offset + IIGSFloppyMedia.nibTrackSize, chunk.count)
            tracks.append(Array(chunk[offset..<next]))
            offset = next
        }
        return tracks
    }

    private static func chunkName(_ bytes: [UInt8], at offset: Int, equals name: [UInt8]) -> Bool {
        guard name.count == 4, offset + 4 <= bytes.count else {
            return false
        }
        return bytes[offset] == name[0]
            && bytes[offset + 1] == name[1]
            && bytes[offset + 2] == name[2]
            && bytes[offset + 3] == name[3]
    }

    private static func readLittle32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

public final class IIGSFloppyMedia {
    public static let raw5_25ByteCount = 143_360
    public static let raw3_5ByteCount = 819_200
    public static let tracks5_25 = 35
    public static let sectorsPerTrack5_25 = 16
    public static let sectorSize5_25 = 256
    public static let nibTrackSize = 0x1A00

    private static let dos33LogicalToPhysical: [Int] = [0, 7, 14, 6, 13, 5, 12, 4, 11, 3, 10, 2, 9, 1, 8, 15]
    private static let prodosLogicalToPhysical: [Int] = [0, 8, 1, 9, 2, 10, 3, 11, 4, 12, 5, 13, 6, 14, 7, 15]

    private var bytes: [UInt8]
    private var wozImage: IIGSWOZImage?

    public let kind: IIGSFloppyMediaKind
    public let sectorOrder: IIGSFloppySectorOrder
    public let isWriteProtected: Bool
    public private(set) var isDirty = false

    public var byteCount: Int {
        bytes.count
    }

    public init(raw5_25 bytes: [UInt8], sectorOrder: IIGSFloppySectorOrder = .physical, isWriteProtected: Bool = false) throws {
        guard bytes.count == Self.raw5_25ByteCount else {
            throw IIGSStorageError.invalidFloppySize(bytes.count)
        }
        self.bytes = bytes
        self.kind = .raw5_25
        self.sectorOrder = sectorOrder
        self.isWriteProtected = isWriteProtected
    }

    public init(raw3_5 bytes: [UInt8], isWriteProtected: Bool = false) throws {
        guard bytes.count == Self.raw3_5ByteCount else {
            throw IIGSStorageError.invalidFloppySize(bytes.count)
        }
        self.bytes = bytes
        self.kind = .raw3_5
        self.sectorOrder = .prodos
        self.isWriteProtected = isWriteProtected
    }

    public init(nib bytes: [UInt8], isWriteProtected: Bool = false) throws {
        guard bytes.count > 0, bytes.count % Self.nibTrackSize == 0 else {
            throw IIGSStorageError.invalidFloppySize(bytes.count)
        }
        self.bytes = bytes
        self.kind = .nib
        self.sectorOrder = .physical
        self.isWriteProtected = isWriteProtected
    }

    public init(woz bytes: [UInt8], isWriteProtected: Bool = false) throws {
        let image = try IIGSWOZImage(bytes: bytes)
        self.bytes = bytes
        self.wozImage = image
        self.kind = .woz(version: image.version)
        self.sectorOrder = .physical
        self.isWriteProtected = isWriteProtected
    }

    public var wozTrackMap: [UInt8]? {
        wozImage?.trackMap
    }

    public func readSector(track: Int, sector: Int) throws -> [UInt8] {
        let range = try sectorRange(track: track, sector: sector)
        return Array(bytes[range])
    }

    public func writeSector(track: Int, sector: Int, bytes sectorBytes: [UInt8]) throws {
        guard !isWriteProtected else {
            throw IIGSStorageError.writeProtected
        }
        guard sectorBytes.count == Self.sectorSize5_25 else {
            throw IIGSStorageError.wrongTransferSize(sectorBytes.count)
        }
        let range = try sectorRange(track: track, sector: sector)
        bytes.replaceSubrange(range, with: sectorBytes)
        isDirty = true
    }

    public func readTrackByte(quarterTrack: Int, offset: Int) -> UInt8 {
        let stream = trackStream(quarterTrack: quarterTrack)
        guard !stream.isEmpty else {
            return 0xFF
        }
        return stream[offset % stream.count]
    }

    public func writeTrackByte(_ value: UInt8, quarterTrack: Int, offset: Int) {
        guard !isWriteProtected else {
            return
        }
        switch kind {
        case .raw5_25:
            let track = clampedTrack(fromQuarterTrack: quarterTrack)
            let base = track * Self.sectorsPerTrack5_25 * Self.sectorSize5_25
            let index = base + (offset % (Self.sectorsPerTrack5_25 * Self.sectorSize5_25))
            bytes[index] = value
            isDirty = true
        case .nib:
            let track = min(max(quarterTrack / 4, 0), max((bytes.count / Self.nibTrackSize) - 1, 0))
            let index = track * Self.nibTrackSize + (offset % Self.nibTrackSize)
            bytes[index] = value
            isDirty = true
        case .raw3_5, .woz:
            break
        }
    }

    private func trackStream(quarterTrack: Int) -> [UInt8] {
        switch kind {
        case .raw5_25:
            let track = clampedTrack(fromQuarterTrack: quarterTrack)
            let start = track * Self.sectorsPerTrack5_25 * Self.sectorSize5_25
            let end = start + Self.sectorsPerTrack5_25 * Self.sectorSize5_25
            return Array(bytes[start..<end])
        case .nib:
            let track = min(max(quarterTrack / 4, 0), max((bytes.count / Self.nibTrackSize) - 1, 0))
            let start = track * Self.nibTrackSize
            return Array(bytes[start..<(start + Self.nibTrackSize)])
        case .woz:
            guard let wozImage,
                  let trackIndex = wozImage.trackIndex(forQuarterTrack: quarterTrack),
                  Int(trackIndex) < wozImage.trackData.count
            else {
                return []
            }
            return wozImage.trackData[Int(trackIndex)]
        case .raw3_5:
            return []
        }
    }

    private func sectorRange(track: Int, sector: Int) throws -> Range<Int> {
        guard track >= 0, track < Self.tracks5_25,
              sector >= 0, sector < Self.sectorsPerTrack5_25,
              kind == .raw5_25
        else {
            throw IIGSStorageError.blockOutOfRange(UInt32(max(track, 0) * Self.sectorsPerTrack5_25 + max(sector, 0)))
        }

        let physicalSector = physicalSector(forLogicalSector: sector)
        let start = ((track * Self.sectorsPerTrack5_25) + physicalSector) * Self.sectorSize5_25
        return start..<(start + Self.sectorSize5_25)
    }

    private func physicalSector(forLogicalSector sector: Int) -> Int {
        switch sectorOrder {
        case .physical:
            return sector
        case .dos33:
            return Self.dos33LogicalToPhysical[sector]
        case .prodos:
            return Self.prodosLogicalToPhysical[sector]
        }
    }

    private func clampedTrack(fromQuarterTrack quarterTrack: Int) -> Int {
        min(max(quarterTrack / 4, 0), Self.tracks5_25 - 1)
    }
}
