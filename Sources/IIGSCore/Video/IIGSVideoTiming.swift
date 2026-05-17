public struct IIGSVideoPosition: Equatable, Sendable {
    public let line: Int
    public let cycleInLine: Int
    public let frameCycle: Int
    public let inVerticalBlank: Bool

    public init(line: Int, cycleInLine: Int, frameCycle: Int, inVerticalBlank: Bool) {
        self.line = line
        self.cycleInLine = cycleInLine
        self.frameCycle = frameCycle
        self.inVerticalBlank = inVerticalBlank
    }
}

public enum IIGSVideoTiming {
    public static let cyclesPerLine = 65
    public static let scanlinesPerFrame = 262
    public static let cyclesPerFrame = cyclesPerLine * scanlinesPerFrame
    public static let classicVisibleLines = 192
    public static let superHiresVisibleLines = 200

    public static func position(atCycle cycle: UInt64) -> IIGSVideoPosition {
        let frameCycle = Int(cycle % UInt64(cyclesPerFrame))
        let line = frameCycle / cyclesPerLine
        let cycleInLine = frameCycle % cyclesPerLine
        return IIGSVideoPosition(
            line: line,
            cycleInLine: cycleInLine,
            frameCycle: frameCycle,
            inVerticalBlank: line >= classicVisibleLines
        )
    }

    public static func verticalBlankStatus(atCycle cycle: UInt64) -> UInt8 {
        position(atCycle: cycle).inVerticalBlank ? 0x80 : 0x00
    }

    public static func verticalCounter(atCycle cycle: UInt64) -> UInt8 {
        let line = position(atCycle: cycle).line
        return UInt8(truncatingIfNeeded: 0x80 + (line / 2))
    }

    public static func horizontalCounter(atCycle cycle: UInt64) -> UInt8 {
        let position = position(atCycle: cycle)
        let horizontal: UInt8
        if position.cycleInLine == 0 {
            horizontal = 0x00
        } else {
            horizontal = 0x40 | UInt8(min(position.cycleInLine - 1, 0x3F))
        }

        let lineLowBit: UInt8 = position.line & 1 == 1 ? 0x80 : 0x00
        return lineLowBit | horizontal
    }
}
