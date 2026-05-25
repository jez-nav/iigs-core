import Foundation

enum ROMLocator {
    static func locateROM1(fileManager: FileManager = .default) -> URL? {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let candidates = [
            repositoryRoot.appendingPathComponent("LocalAssets/ROMs/Apple_IIGS_ROM01.bin"),
            repositoryRoot.appendingPathComponent("ROM01"),
            repositoryRoot.appendingPathComponent("ROM1"),
            repositoryRoot.appendingPathComponent("Apple_IIGS_ROM01.bin"),
            home.appendingPathComponent("Desktop/AppleIIGS/ROM1"),
        ]

        return candidates.first { fileManager.isReadableFile(atPath: $0.path) }
    }
}
