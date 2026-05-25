import Foundation

public enum IIGSDiskImageLoaderError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedImage(name: String, byteCount: Int)
    case incompatibleTarget(image: IIGSDiskImageKind, target: IIGSDiskMountTarget)
    case invalidTarget(IIGSDiskMountTarget)

    public var description: String {
        switch self {
        case let .unsupportedImage(name, byteCount):
            return "Unsupported disk image \(name) (\(byteCount) bytes)"
        case let .incompatibleTarget(image, target):
            return "\(image.displayName) cannot be mounted at \(target.displayName)"
        case let .invalidTarget(target):
            return "Invalid disk target \(target.displayName)"
        }
    }
}

public enum IIGSDiskImageKind: Equatable, Sendable {
    case rawBlock
    case twoIMG(format: UInt32)
    case raw5_25(sectorOrder: IIGSFloppySectorOrder)
    case raw3_5
    case nib
    case woz(version: UInt8)

    public var displayName: String {
        switch self {
        case .rawBlock:
            return "Raw Block"
        case let .twoIMG(format):
            return "2IMG format \(format)"
        case let .raw5_25(sectorOrder):
            switch sectorOrder {
            case .physical:
                return "5.25 Raw"
            case .dos33:
                return "5.25 DOS 3.3"
            case .prodos:
                return "5.25 ProDOS"
            }
        case .raw3_5:
            return "3.5 Raw"
        case .nib:
            return "NIB"
        case let .woz(version):
            return "WOZ\(version)"
        }
    }
}

public enum IIGSDiskMountTarget: Hashable, Sendable {
    case smartPort(unit: UInt8)
    case floppy5_25(drive: UInt8)
    case floppy3_5(drive: UInt8)

    public var displayName: String {
        switch self {
        case let .smartPort(unit):
            return "s7u\(unit)"
        case let .floppy5_25(drive):
            return "s6d\(drive)"
        case let .floppy3_5(drive):
            return "s5d\(drive)"
        }
    }

    public var slotDescription: String {
        switch self {
        case let .smartPort(unit):
            return "Slot 7 unit \(unit)"
        case let .floppy5_25(drive):
            return "Slot 6 drive \(drive)"
        case let .floppy3_5(drive):
            return "Slot 5 drive \(drive)"
        }
    }
}

public struct IIGSMountedDiskInfo: Equatable, Sendable {
    public let target: IIGSDiskMountTarget
    public let name: String
    public let kind: IIGSDiskImageKind
    public let byteCount: Int
    public let blockCount: UInt32?
    public let isWriteProtected: Bool

    public var summary: String {
        var parts = [kind.displayName]
        if let blockCount {
            parts.append("\(blockCount) blocks")
        } else {
            parts.append("\(byteCount) bytes")
        }
        if isWriteProtected {
            parts.append("read-only")
        }
        return parts.joined(separator: " | ")
    }
}

public struct IIGSLoadedDiskImage {
    public let info: IIGSMountedDiskInfo
    fileprivate let media: Media

    fileprivate enum Media {
        case block(IIGSBlockDevice)
        case floppy(IIGSFloppyMedia)
    }
}

public enum IIGSDiskImageLoader {
    public static func load(contentsOf url: URL, target: IIGSDiskMountTarget, isWriteProtected: Bool? = nil) throws -> IIGSLoadedDiskImage {
        let data = try Data(contentsOf: url)
        return try load(
            bytes: Array(data),
            name: url.lastPathComponent,
            fileExtension: url.pathExtension,
            target: target,
            isWriteProtected: isWriteProtected ?? isHostFileReadOnly(url)
        )
    }

    public static func load(
        bytes: [UInt8],
        name: String,
        fileExtension: String = "",
        target: IIGSDiskMountTarget,
        isWriteProtected: Bool = false
    ) throws -> IIGSLoadedDiskImage {
        switch target {
        case let .smartPort(unit):
            guard (1...127).contains(unit) else {
                throw IIGSDiskImageLoaderError.invalidTarget(target)
            }
            return try loadBlockImage(bytes: bytes, name: name, fileExtension: fileExtension, target: target, isWriteProtected: isWriteProtected)
        case let .floppy5_25(drive), let .floppy3_5(drive):
            guard drive == 1 || drive == 2 else {
                throw IIGSDiskImageLoaderError.invalidTarget(target)
            }
            return try loadFloppyImage(bytes: bytes, name: name, fileExtension: fileExtension, target: target, isWriteProtected: isWriteProtected)
        }
    }

    private static func loadBlockImage(
        bytes: [UInt8],
        name: String,
        fileExtension: String,
        target: IIGSDiskMountTarget,
        isWriteProtected: Bool
    ) throws -> IIGSLoadedDiskImage {
        if is2IMG(bytes) {
            let image = try IIGS2IMGImage(bytes: bytes)
            let device = try IIGSBlockDevice(bytes: image.data, name: name, isWriteProtected: image.isWriteProtected || isWriteProtected)
            return loadedBlock(device, name: name, kind: .twoIMG(format: image.imageFormat), target: target)
        }

        guard bytes.count > 0, bytes.count % IIGSBlockDevice.blockSize == 0 else {
            throw IIGSDiskImageLoaderError.unsupportedImage(name: name, byteCount: bytes.count)
        }

        let device = try IIGSBlockDevice.raw(bytes: bytes, name: name, isWriteProtected: isWriteProtected)
        return loadedBlock(device, name: name, kind: .rawBlock, target: target)
    }

    private static func loadFloppyImage(
        bytes: [UInt8],
        name: String,
        fileExtension: String,
        target: IIGSDiskMountTarget,
        isWriteProtected: Bool
    ) throws -> IIGSLoadedDiskImage {
        if isWOZ(bytes) {
            let media = try IIGSFloppyMedia(woz: bytes, isWriteProtected: isWriteProtected)
            let version: UInt8 = bytes[3] == 0x32 ? 2 : 1
            return loadedFloppy(media, name: name, kind: .woz(version: version), target: target)
        }

        if is2IMG(bytes) {
            let image = try IIGS2IMGImage(bytes: bytes)
            return try load2IMGFloppy(image, name: name, target: target, isWriteProtected: image.isWriteProtected || isWriteProtected)
        }

        let ext = fileExtension.lowercased()
        if ext == "nib" {
            let media = try IIGSFloppyMedia(nib: bytes, isWriteProtected: isWriteProtected)
            return loadedFloppy(media, name: name, kind: .nib, target: target)
        }

        switch (target, bytes.count) {
        case (.floppy5_25(_), IIGSFloppyMedia.raw5_25ByteCount):
            let order = raw5_25SectorOrder(fileExtension: ext)
            let media = try IIGSFloppyMedia(raw5_25: bytes, sectorOrder: order, isWriteProtected: isWriteProtected)
            return loadedFloppy(media, name: name, kind: .raw5_25(sectorOrder: order), target: target)
        case (.floppy3_5(_), IIGSFloppyMedia.raw3_5ByteCount):
            let media = try IIGSFloppyMedia(raw3_5: bytes, isWriteProtected: isWriteProtected)
            return loadedFloppy(media, name: name, kind: .raw3_5, target: target)
        default:
            throw IIGSDiskImageLoaderError.unsupportedImage(name: name, byteCount: bytes.count)
        }
    }

    private static func load2IMGFloppy(
        _ image: IIGS2IMGImage,
        name: String,
        target: IIGSDiskMountTarget,
        isWriteProtected: Bool
    ) throws -> IIGSLoadedDiskImage {
        switch (target, Int(image.dataLength), image.imageFormat) {
        case (.floppy5_25(_), IIGSFloppyMedia.raw5_25ByteCount, _):
            let order: IIGSFloppySectorOrder = image.imageFormat == 1 ? .prodos : .dos33
            let media = try IIGSFloppyMedia(raw5_25: image.data, sectorOrder: order, isWriteProtected: isWriteProtected)
            return loadedFloppy(media, name: name, kind: .twoIMG(format: image.imageFormat), target: target)
        case (.floppy5_25(_), _, 2):
            let media = try IIGSFloppyMedia(nib: image.data, isWriteProtected: isWriteProtected)
            return loadedFloppy(media, name: name, kind: .twoIMG(format: image.imageFormat), target: target)
        case (.floppy3_5(_), IIGSFloppyMedia.raw3_5ByteCount, _):
            let media = try IIGSFloppyMedia(raw3_5: image.data, isWriteProtected: isWriteProtected)
            return loadedFloppy(media, name: name, kind: .twoIMG(format: image.imageFormat), target: target)
        default:
            throw IIGSDiskImageLoaderError.incompatibleTarget(image: .twoIMG(format: image.imageFormat), target: target)
        }
    }

    private static func loadedBlock(_ device: IIGSBlockDevice, name: String, kind: IIGSDiskImageKind, target: IIGSDiskMountTarget) -> IIGSLoadedDiskImage {
        IIGSLoadedDiskImage(
            info: IIGSMountedDiskInfo(
                target: target,
                name: name,
                kind: kind,
                byteCount: device.byteCount,
                blockCount: device.blockCount,
                isWriteProtected: device.isWriteProtected
            ),
            media: .block(device)
        )
    }

    private static func loadedFloppy(_ media: IIGSFloppyMedia, name: String, kind: IIGSDiskImageKind, target: IIGSDiskMountTarget) -> IIGSLoadedDiskImage {
        IIGSLoadedDiskImage(
            info: IIGSMountedDiskInfo(
                target: target,
                name: name,
                kind: kind,
                byteCount: media.byteCount,
                blockCount: nil,
                isWriteProtected: media.isWriteProtected
            ),
            media: .floppy(media)
        )
    }

    private static func is2IMG(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 4 && bytes[0] == 0x32 && bytes[1] == 0x49 && bytes[2] == 0x4D && bytes[3] == 0x47
    }

    private static func isWOZ(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 4
            && bytes[0] == 0x57
            && bytes[1] == 0x4F
            && bytes[2] == 0x5A
            && (bytes[3] == 0x31 || bytes[3] == 0x32)
    }

    private static func raw5_25SectorOrder(fileExtension: String) -> IIGSFloppySectorOrder {
        switch fileExtension {
        case "po":
            return .prodos
        case "do", "dsk":
            return .dos33
        default:
            return .physical
        }
    }

    private static func isHostFileReadOnly(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return true
        }
        return !FileManager.default.isWritableFile(atPath: url.path)
    }
}

public extension IIGSMachine {
    @discardableResult
    func mountDiskImage(_ image: IIGSLoadedDiskImage, target: IIGSDiskMountTarget? = nil) throws -> IIGSMountedDiskInfo {
        let target = target ?? image.info.target
        switch (target, image.media) {
        case let (.smartPort(unit), .block(device)):
            mountSmartPortDevice(device, unit: unit)
            mountedDiskImages[target] = image.info
        case let (.floppy5_25(drive), .floppy(media)), let (.floppy3_5(drive), .floppy(media)):
            mountFloppyMedia(media, drive: drive)
            mountedDiskImages.removeValue(forKey: .floppy5_25(drive: drive))
            mountedDiskImages.removeValue(forKey: .floppy3_5(drive: drive))
            mountedDiskImages[target] = image.info
        case (.smartPort(_), .floppy):
            throw IIGSDiskImageLoaderError.incompatibleTarget(image: image.info.kind, target: target)
        case (.floppy5_25(_), .block), (.floppy3_5(_), .block):
            throw IIGSDiskImageLoaderError.incompatibleTarget(image: image.info.kind, target: target)
        }
        return mountedDiskImages[target] ?? image.info
    }

    @discardableResult
    func mountDiskImage(contentsOf url: URL, target: IIGSDiskMountTarget, isWriteProtected: Bool? = nil) throws -> IIGSMountedDiskInfo {
        let image = try IIGSDiskImageLoader.load(contentsOf: url, target: target, isWriteProtected: isWriteProtected)
        return try mountDiskImage(image, target: target)
    }

    func ejectDisk(target: IIGSDiskMountTarget) {
        switch target {
        case let .smartPort(unit):
            smartPortController.unmount(unit: unit)
            mountedDiskImages.removeValue(forKey: target)
        case let .floppy5_25(drive), let .floppy3_5(drive):
            memory.iwmController.unmount(drive: drive)
            mountedDiskImages.removeValue(forKey: .floppy5_25(drive: drive))
            mountedDiskImages.removeValue(forKey: .floppy3_5(drive: drive))
        }
    }

    func mountedDiskInfo(for target: IIGSDiskMountTarget) -> IIGSMountedDiskInfo? {
        mountedDiskImages[target]
    }
}
