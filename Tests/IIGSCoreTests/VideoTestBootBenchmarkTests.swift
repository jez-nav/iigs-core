import Foundation
import XCTest
@testable import IIGSCore

final class VideoTestBootBenchmarkTests: XCTestCase {
    func testLocalROM1ReachesBlueBootFrameUnderEightSeconds() throws {
        guard let romURL = locateROM1() else {
            throw XCTSkip("Local ROM1 is not available for VideoTest boot benchmark")
        }

        let machine = IIGSMachine()
        let romBytes = try Array(Data(contentsOf: romURL))
        try machine.installROM(bytes: romBytes)
        machine.reset(.cold)

        let start = Date()
        let timeout: TimeInterval = 8
        let maxFrames = Int((IIGSVideoTiming.nominalFramesPerSecond * timeout).rounded(.up))
        var reachedBlueBootFrame = false

        for _ in 0..<maxFrames {
            _ = try machine.runForCycles(IIGSVideoTiming.cyclesPerFrame, instructionLimit: 2_000_000)
            let frame = IIGSVideoRenderer.renderFrame(from: machine.memory)
            if isBlueBootFrame(frame) {
                reachedBlueBootFrame = true
                break
            }

            if Date().timeIntervalSince(start) >= timeout {
                break
            }
        }

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertTrue(reachedBlueBootFrame, "ROM1 did not render a blue boot frame before the eight-second wall")
        XCTAssertLessThan(elapsed, timeout)
    }

    private func locateROM1(fileManager: FileManager = .default) -> URL? {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
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

    private func isBlueBootFrame(_ frame: IIGSVideoFrame) -> Bool {
        guard frame.width > 0, frame.height > 0 else {
            return false
        }

        var blueDominantPixels = 0
        var whitePixels = 0
        let sampleStride = max(1, frame.pixels.count / 4_000)

        for index in stride(from: 0, to: frame.pixels.count, by: sampleStride) {
            let pixel = frame.pixels[index]
            if pixel.blue > 0xB0, pixel.red < 0x60, pixel.green < 0x80 {
                blueDominantPixels += 1
            }
            if pixel.red > 0xD0, pixel.green > 0xD0, pixel.blue > 0xD0 {
                whitePixels += 1
            }
        }

        let samples = max(1, frame.pixels.count / sampleStride)
        return Double(blueDominantPixels) / Double(samples) > 0.45 && whitePixels > 16
    }
}
