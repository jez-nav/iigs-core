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
    public static let tracks3_5 = 80
    public static let sectorsPerTrack5_25 = 16
    public static let sectorSize5_25 = 256
    public static let blockSize3_5 = 512
    public static let nibTrackSize = 0x1A00

    private static let dos33LogicalToPhysical: [Int] = [0, 7, 14, 6, 13, 5, 12, 4, 11, 3, 10, 2, 9, 1, 8, 15]
    private static let prodosLogicalToPhysical: [Int] = [0, 8, 1, 9, 2, 10, 3, 11, 4, 12, 5, 13, 6, 14, 7, 15]
    private static let sectorsPerTrack3_5ByZone = [12, 11, 10, 9, 8]
    private static let diskByte6And2: [UInt8] = [
        0x96, 0x97, 0x9A, 0x9B, 0x9D, 0x9E, 0x9F, 0xA6,
        0xA7, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF, 0xB2, 0xB3,
        0xB4, 0xB5, 0xB6, 0xB7, 0xB9, 0xBA, 0xBB, 0xBC,
        0xBD, 0xBE, 0xBF, 0xCB, 0xCD, 0xCE, 0xCF, 0xD3,
        0xD6, 0xD7, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE,
        0xDF, 0xE5, 0xE6, 0xE7, 0xE9, 0xEA, 0xEB, 0xEC,
        0xED, 0xEE, 0xEF, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6,
        0xF7, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF
    ]

    private var bytes: [UInt8]
    private var wozImage: IIGSWOZImage?
    private var raw3_5TrackCache: [Int: [UInt8]] = [:]

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
        raw3_5TrackCache.removeAll(keepingCapacity: true)
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
            return raw3_5TrackStream(trackIndex: clampedRaw3_5TrackIndex(from: quarterTrack))
        }
    }

    private func raw3_5TrackStream(trackIndex: Int) -> [UInt8] {
        if let stream = raw3_5TrackCache[trackIndex] {
            return stream
        }

        let cylinder = trackIndex / 2
        let side = trackIndex & 1
        let sectors = Self.sectorsPerRaw3_5Track(cylinder)
        let trackStartBlock = Self.raw3_5StartBlock(track: cylinder, side: side)
        let logicalSectorByPhysical = Self.physicalToLogicalSectorMap(sectorCount: sectors, interleave: 2)
        var stream: [UInt8] = []
        stream.reserveCapacity(max(1, sectors) * 820)

        for physicalSector in 0..<sectors {
            let logicalSector = logicalSectorByPhysical[physicalSector]
            let blockOffset = (trackStartBlock + logicalSector) * Self.blockSize3_5
            let sectorEnd = blockOffset + Self.blockSize3_5
            let sectorBytes = blockOffset >= 0 && sectorEnd <= bytes.count
                ? Array(bytes[blockOffset..<sectorEnd])
                : Array(repeating: 0, count: Self.blockSize3_5)

            appendRaw3_5Sync(to: &stream, count: physicalSector == 0 ? 400 : 54)
            appendRaw3_5AddressField(
                to: &stream,
                track: cylinder,
                side: side,
                sector: logicalSector,
                format: 0x22
            )

            appendRaw3_5Sync(to: &stream, count: 5)
            stream.append(contentsOf: [0xD5, 0xAA, 0xAD, Self.encode6And2(logicalSector)])
            appendRaw3_5DataField(sectorBytes, to: &stream)
            stream.append(contentsOf: [0xDE, 0xAA, 0xFF])
        }

        raw3_5TrackCache[trackIndex] = stream
        return stream
    }

    private func appendRaw3_5AddressField(
        to stream: inout [UInt8],
        track: Int,
        side: Int,
        sector: Int,
        format: UInt8
    ) {
        let lowTrack = UInt8(track & 0x3F)
        let sideAndTrack = UInt8((side << 5) | (track >> 6))
        let sectorByte = UInt8(sector & 0x3F)
        let checksum = lowTrack ^ sectorByte ^ sideAndTrack ^ format
        stream.append(contentsOf: [
            0xD5, 0xAA, 0x96,
            Self.encode6And2(Int(lowTrack)),
            Self.encode6And2(Int(sectorByte)),
            Self.encode6And2(Int(sideAndTrack)),
            Self.encode6And2(Int(format)),
            Self.encode6And2(Int(checksum)),
            0xDE, 0xAA
        ])
    }

    private func appendRaw3_5DataField(_ sourceBytes: [UInt8], to stream: inout [UInt8]) {
        let dataByteCount = 12 + Self.blockSize3_5
        var decodedBytes = Array(repeating: UInt8(0), count: dataByteCount)
        let payloadCount = min(sourceBytes.count, Self.blockSize3_5)
        decodedBytes.replaceSubrange(12..<(12 + payloadCount), with: sourceBytes.prefix(payloadCount))

        var scratch0 = Array(repeating: UInt8(0), count: 175)
        var scratch1 = Array(repeating: UInt8(0), count: 175)
        var scratch2 = Array(repeating: UInt8(0), count: 175)
        var checksum0: UInt16 = 0
        var checksum1: UInt16 = 0
        var checksum2: UInt16 = 0
        var sourceIndex = 0
        var scratchIndex = 0

        while sourceIndex < dataByteCount {
            checksum0 = (checksum0 & 0x00FF) << 1
            if checksum0 & 0x0100 != 0 {
                checksum0 += 1
            }

            var value = decodedBytes[sourceIndex]
            sourceIndex += 1
            checksum2 += UInt16(value)
            if checksum0 & 0x0100 != 0 {
                checksum2 += 1
                checksum0 &= 0x00FF
            }
            scratch0[scratchIndex] = value ^ UInt8(truncatingIfNeeded: checksum0)

            value = decodedBytes[sourceIndex]
            sourceIndex += 1
            checksum1 += UInt16(value)
            if checksum2 > 0x00FF {
                checksum1 += 1
                checksum2 &= 0x00FF
            }
            scratch1[scratchIndex] = value ^ UInt8(truncatingIfNeeded: checksum2)

            if sourceIndex < dataByteCount {
                value = decodedBytes[sourceIndex]
                sourceIndex += 1
                checksum0 += UInt16(value)
                if checksum1 > 0x00FF {
                    checksum0 += 1
                    checksum1 &= 0x00FF
                }
                scratch2[scratchIndex] = value ^ UInt8(truncatingIfNeeded: checksum1)
                scratchIndex += 1
            }
        }
        scratch2[scratchIndex] = 0
        scratchIndex += 1

        for index in 0..<scratchIndex {
            var highBits = (scratch0[index] & 0xC0) >> 2
            highBits |= (scratch1[index] & 0xC0) >> 4
            highBits |= (scratch2[index] & 0xC0) >> 6
            stream.append(Self.encode6And2(Int(highBits)))
            stream.append(Self.encode6And2(Int(scratch0[index] & 0x3F)))
            stream.append(Self.encode6And2(Int(scratch1[index] & 0x3F)))
            if index < scratchIndex - 1 {
                stream.append(Self.encode6And2(Int(scratch2[index] & 0x3F)))
            }
        }

        var checksumHigh = UInt8((checksum0 & 0x00C0) >> 6)
        checksumHigh |= UInt8((checksum1 & 0x00C0) >> 4)
        checksumHigh |= UInt8((checksum2 & 0x00C0) >> 2)
        stream.append(Self.encode6And2(Int(checksumHigh)))
        stream.append(Self.encode6And2(Int(checksum2 & 0x003F)))
        stream.append(Self.encode6And2(Int(checksum1 & 0x003F)))
        stream.append(Self.encode6And2(Int(checksum0 & 0x003F)))
    }

    private func appendRaw3_5Sync(to stream: inout [UInt8], count: Int) {
        stream.append(contentsOf: repeatElement(UInt8(0xFF), count: count))
    }

    private static func encode6And2(_ value: Int) -> UInt8 {
        diskByte6And2[value & 0x3F]
    }

    private static func physicalToLogicalSectorMap(sectorCount: Int, interleave: Int) -> [Int] {
        var map = Array(repeating: -1, count: sectorCount)
        var physicalSector = 0
        for logicalSector in 0..<sectorCount {
            while map[physicalSector] >= 0 {
                physicalSector = (physicalSector + 1) % sectorCount
            }
            map[physicalSector] = logicalSector
            physicalSector = (physicalSector + interleave) % sectorCount
        }
        return map
    }

    private static func sectorsPerRaw3_5Track(_ track: Int) -> Int {
        sectorsPerTrack3_5ByZone[min(max(track / 16, 0), sectorsPerTrack3_5ByZone.count - 1)]
    }

    private static func raw3_5StartBlock(track: Int, side: Int) -> Int {
        let clampedTrack = min(max(track, 0), tracks3_5 - 1)
        var blocks = 0
        for priorTrack in 0..<clampedTrack {
            blocks += sectorsPerRaw3_5Track(priorTrack) * 2
        }
        return blocks + (min(max(side, 0), 1) * sectorsPerRaw3_5Track(clampedTrack))
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

    private func clampedRaw3_5TrackIndex(from quarterTrack: Int) -> Int {
        min(max(quarterTrack, 0), (Self.tracks3_5 * 2) - 1)
    }
}
