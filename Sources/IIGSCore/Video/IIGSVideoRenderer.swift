public struct IIGSRGBColor: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let black = IIGSRGBColor(red: 0, green: 0, blue: 0)
    public static let white = IIGSRGBColor(red: 0xFF, green: 0xFF, blue: 0xFF)
}

public struct IIGSVideoFrame: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var pixels: [IIGSRGBColor]

    public init(width: Int, height: Int, pixels: [IIGSRGBColor]) {
        precondition(width >= 0)
        precondition(height >= 0)
        precondition(pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public subscript(x: Int, y: Int) -> IIGSRGBColor {
        get {
            precondition((0..<width).contains(x))
            precondition((0..<height).contains(y))
            return pixels[y * width + x]
        }
        set {
            precondition((0..<width).contains(x))
            precondition((0..<height).contains(y))
            pixels[y * width + x] = newValue
        }
    }
}

public enum IIGSVideoRenderer {
    public static let superHiresWidth = 640
    public static let superHiresHeight = 200
    public static let classicGraphicsWidth = 280
    public static let classicGraphicsHeight = 192
    public static let classicTextCellWidth = 7
    public static let classicTextCellHeight = 8

    private static let superHiresPixelBase: UInt32 = 0xE12000
    private static let superHiresSCBBase: UInt32 = 0xE19D00
    private static let superHiresPaletteBase: UInt32 = 0xE19E00

    public static func renderFrame(from memory: FlatMemoryBus) -> IIGSVideoFrame {
        if memory.softSwitches.videoControl & 0x80 != 0 {
            return renderSuperHires(from: memory)
        }
        if !memory.softSwitches.textMode {
            if memory.softSwitches.hires {
                return renderClassicHires(from: memory)
            }
            return renderClassicLores(from: memory)
        }
        return renderClassicText(from: memory)
    }

    public static func renderSuperHires(from memory: FlatMemoryBus) -> IIGSVideoFrame {
        var frame = blankFrame(width: superHiresWidth, height: superHiresHeight)

        for line in 0..<superHiresHeight {
            let scb = memory.peek8(at: superHiresSCBBase + UInt32(line))
            let palette = Int(scb & 0x0F)
            let is640Mode = scb & 0x80 != 0
            let fillMode = scb & 0x20 != 0
            let lineBase = superHiresPixelBase + UInt32(line * 160)

            if is640Mode {
                renderSuperHires640Line(from: memory, lineBase: lineBase, line: line, palette: palette, into: &frame)
            } else {
                renderSuperHires320Line(
                    from: memory,
                    lineBase: lineBase,
                    line: line,
                    palette: palette,
                    fillMode: fillMode,
                    into: &frame
                )
            }
        }

        return frame
    }

    public static func renderClassicLores(from memory: FlatMemoryBus) -> IIGSVideoFrame {
        var frame = blankFrame(width: classicGraphicsWidth, height: classicGraphicsHeight)
        let pageBase: UInt32 = memory.softSwitches.page2 ? 0xE00800 : 0xE00400

        for y in 0..<classicGraphicsHeight {
            if memory.softSwitches.mixedMode && y >= 160 {
                continue
            }

            let loresRow = y / 4
            let textRow = loresRow / 2
            let highNibble = loresRow & 1 == 1

            for column in 0..<40 {
                let byte = memory.peek8(at: pageBase + UInt32(classicTextOffset(row: textRow, column: column)))
                let colorIndex = highNibble ? byte >> 4 : byte & 0x0F
                drawLoresCell(column: column, y: y, color: classicColor(colorIndex), into: &frame)
            }
        }

        if memory.softSwitches.mixedMode {
            drawClassicTextRows(from: memory, rows: 20..<24, destinationStartY: 160, columns: 40, into: &frame)
        }

        return frame
    }

    public static func renderClassicHires(from memory: FlatMemoryBus) -> IIGSVideoFrame {
        var frame = blankFrame(width: classicGraphicsWidth, height: classicGraphicsHeight)
        let pageBase: UInt32 = memory.softSwitches.page2 ? 0xE04000 : 0xE02000
        let foreground = classicColor(memory.softSwitches.textColor >> 4)
        let background = classicColor(memory.softSwitches.textColor & 0x0F)

        for y in 0..<classicGraphicsHeight {
            if memory.softSwitches.mixedMode && y >= 160 {
                continue
            }

            let rowOffset = classicHiresRowOffset(y)
            for byteColumn in 0..<40 {
                let byte = memory.peek8(at: pageBase + UInt32(rowOffset + byteColumn))
                for bit in 0..<7 {
                    let color = byte & (1 << UInt8(bit)) == 0 ? background : foreground
                    frame[byteColumn * 7 + bit, y] = color
                }
            }
        }

        if memory.softSwitches.mixedMode {
            drawClassicTextRows(from: memory, rows: 20..<24, destinationStartY: 160, columns: 40, into: &frame)
        }

        return frame
    }

    public static func renderClassicText(from memory: FlatMemoryBus) -> IIGSVideoFrame {
        let columns = memory.softSwitches.eightyColumnVideo ? 80 : 40
        let rows = 24
        var frame = blankFrame(
            width: columns * classicTextCellWidth,
            height: rows * classicTextCellHeight
        )

        let pageBase: UInt32 = memory.softSwitches.page2 ? 0xE00800 : 0xE00400
        let foreground = classicColor(memory.softSwitches.textColor >> 4)
        let background = classicColor(memory.softSwitches.textColor & 0x0F)

        for y in 0..<frame.height {
            for x in 0..<frame.width {
                frame[x, y] = background
            }
        }

        for row in 0..<rows {
            for column in 0..<columns {
                let byte = classicTextByte(from: memory, pageBase: pageBase, row: row, column: column, columns: columns)
                drawTextCell(byte: byte, column: column, row: row, foreground: foreground, background: background, into: &frame)
            }
        }

        return frame
    }

    public static func classicHiresAddressOffset(forScanline y: Int, byteColumn: Int) -> Int {
        precondition((0..<classicGraphicsHeight).contains(y))
        precondition((0..<40).contains(byteColumn))
        return classicHiresRowOffset(y) + byteColumn
    }

    private static func renderSuperHires320Line(
        from memory: FlatMemoryBus,
        lineBase: UInt32,
        line: Int,
        palette: Int,
        fillMode: Bool,
        into frame: inout IIGSVideoFrame
    ) {
        var x = 0
        var lastNonzeroNibble: UInt8 = 0

        for byteOffset in 0..<160 {
            let byte = memory.peek8(at: lineBase + UInt32(byteOffset))
            let nibbles = [byte >> 4, byte & 0x0F]
            for rawNibble in nibbles {
                var nibble = rawNibble
                if fillMode && nibble == 0 {
                    nibble = lastNonzeroNibble
                } else if rawNibble != 0 {
                    lastNonzeroNibble = rawNibble
                }

                let color = superHiresColor(from: memory, palette: palette, entry: Int(nibble))
                frame[x, line] = color
                frame[x + 1, line] = color
                x += 2
            }
        }
    }

    private static func renderSuperHires640Line(
        from memory: FlatMemoryBus,
        lineBase: UInt32,
        line: Int,
        palette: Int,
        into frame: inout IIGSVideoFrame
    ) {
        var x = 0

        for byteOffset in 0..<160 {
            let byte = memory.peek8(at: lineBase + UInt32(byteOffset))
            for shift in stride(from: 6, through: 0, by: -2) {
                let colorIndex = Int((byte >> UInt8(shift)) & 0x03)
                frame[x, line] = superHiresColor(from: memory, palette: palette, entry: colorIndex)
                x += 1
            }
        }
    }

    private static func superHiresColor(from memory: FlatMemoryBus, palette: Int, entry: Int) -> IIGSRGBColor {
        let address = superHiresPaletteBase + UInt32((palette * 16 + entry) * 2)
        let low = UInt16(memory.peek8(at: address))
        let high = UInt16(memory.peek8(at: address + 1))
        let raw = low | (high << 8)

        let red = UInt8(((raw >> 8) & 0x0F) * 17)
        let green = UInt8(((raw >> 4) & 0x0F) * 17)
        let blue = UInt8((raw & 0x0F) * 17)
        return IIGSRGBColor(red: red, green: green, blue: blue)
    }

    private static func classicHiresRowOffset(_ y: Int) -> Int {
        (y & 0x07) * 0x400 + ((y >> 3) & 0x07) * 0x80 + (y >> 6) * 0x28
    }

    private static func classicTextByte(
        from memory: FlatMemoryBus,
        pageBase: UInt32,
        row: Int,
        column: Int,
        columns: Int
    ) -> UInt8 {
        let mainColumn = columns == 80 ? column / 2 : column
        let pageOffset = classicTextOffset(row: row, column: mainColumn)
        return memory.peek8(at: pageBase + UInt32(pageOffset))
    }

    private static func classicTextOffset(row: Int, column: Int) -> Int {
        (row & 0x07) * 0x80 + (row >> 3) * 0x28 + column
    }

    private static func drawTextCell(
        byte: UInt8,
        column: Int,
        row: Int,
        foreground: IIGSRGBColor,
        background: IIGSRGBColor,
        into frame: inout IIGSVideoFrame
    ) {
        let startX = column * classicTextCellWidth
        let startY = row * classicTextCellHeight
        let glyph = classicGlyphRows(for: byte)
        let character = byte & 0x7F
        let inverted = byte < 0x40 && character != 0x00 && character != 0x20

        for cellY in 0..<classicTextCellHeight {
            let rowBits = cellY < glyph.count ? glyph[cellY] : 0
            for cellX in 0..<classicTextCellWidth {
                let glyphColumn = cellX - 1
                let lit = (0..<5).contains(glyphColumn) && (rowBits & (1 << UInt8(4 - glyphColumn))) != 0
                let visible = inverted ? !lit : lit
                frame[startX + cellX, startY + cellY] = visible ? foreground : background
            }
        }
    }

    private static func drawLoresCell(column: Int, y: Int, color: IIGSRGBColor, into frame: inout IIGSVideoFrame) {
        let startX = column * classicTextCellWidth
        for x in startX..<(startX + classicTextCellWidth) {
            frame[x, y] = color
        }
    }

    private static func drawClassicTextRows(
        from memory: FlatMemoryBus,
        rows: Range<Int>,
        destinationStartY: Int,
        columns: Int,
        into frame: inout IIGSVideoFrame
    ) {
        let pageBase: UInt32 = memory.softSwitches.page2 ? 0xE00800 : 0xE00400
        let foreground = classicColor(memory.softSwitches.textColor >> 4)
        let background = classicColor(memory.softSwitches.textColor & 0x0F)
        let rowHeight = classicTextCellHeight

        for sourceRow in rows {
            for column in 0..<columns {
                let byte = classicTextByte(from: memory, pageBase: pageBase, row: sourceRow, column: column, columns: columns)
                let startX = column * classicTextCellWidth
                let startY = destinationStartY + (sourceRow - rows.lowerBound) * rowHeight
                let glyph = classicGlyphRows(for: byte)
                let character = byte & 0x7F
                let inverted = byte < 0x40 && character != 0x00 && character != 0x20
                for cellY in 0..<classicTextCellHeight where startY + cellY < frame.height {
                    let rowBits = cellY < glyph.count ? glyph[cellY] : 0
                    for cellX in 0..<classicTextCellWidth where startX + cellX < frame.width {
                        let glyphColumn = cellX - 1
                        let lit = (0..<5).contains(glyphColumn) && (rowBits & (1 << UInt8(4 - glyphColumn))) != 0
                        let visible = inverted ? !lit : lit
                        frame[startX + cellX, startY + cellY] = visible ? foreground : background
                    }
                }
            }
        }
    }

    private static func classicGlyphRows(for byte: UInt8) -> [UInt8] {
        let character = byte & 0x7F
        let normalized = (0x61...0x7A).contains(character) ? character - 0x20 : character
        switch normalized {
        case 0x21: return [0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0, 0b00100]
        case 0x22: return [0b01010, 0b01010, 0b01010, 0, 0, 0, 0]
        case 0x23: return [0b01010, 0b01010, 0b11111, 0b01010, 0b11111, 0b01010, 0b01010]
        case 0x24: return [0b00100, 0b01111, 0b10100, 0b01110, 0b00101, 0b11110, 0b00100]
        case 0x25: return [0b11000, 0b11001, 0b00010, 0b00100, 0b01000, 0b10011, 0b00011]
        case 0x26: return [0b01100, 0b10010, 0b10100, 0b01000, 0b10101, 0b10010, 0b01101]
        case 0x27: return [0b00100, 0b00100, 0b01000, 0, 0, 0, 0]
        case 0x28: return [0b00010, 0b00100, 0b01000, 0b01000, 0b01000, 0b00100, 0b00010]
        case 0x29: return [0b01000, 0b00100, 0b00010, 0b00010, 0b00010, 0b00100, 0b01000]
        case 0x2A: return [0, 0b00100, 0b10101, 0b01110, 0b10101, 0b00100, 0]
        case 0x2B: return [0, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0]
        case 0x2C: return [0, 0, 0, 0, 0b00100, 0b00100, 0b01000]
        case 0x2D: return [0, 0, 0, 0b11111, 0, 0, 0]
        case 0x2E: return [0, 0, 0, 0, 0, 0b01100, 0b01100]
        case 0x2F: return [0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0, 0]
        case 0x30: return [0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110]
        case 0x31: return [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110]
        case 0x32: return [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111]
        case 0x33: return [0b11110, 0b00001, 0b00001, 0b01110, 0b00001, 0b00001, 0b11110]
        case 0x34: return [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010]
        case 0x35: return [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110]
        case 0x36: return [0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110]
        case 0x37: return [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000]
        case 0x38: return [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110]
        case 0x39: return [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100]
        case 0x3A: return [0, 0b01100, 0b01100, 0, 0b01100, 0b01100, 0]
        case 0x3B: return [0, 0b01100, 0b01100, 0, 0b00100, 0b00100, 0b01000]
        case 0x3C: return [0b00010, 0b00100, 0b01000, 0b10000, 0b01000, 0b00100, 0b00010]
        case 0x3D: return [0, 0, 0b11111, 0, 0b11111, 0, 0]
        case 0x3E: return [0b01000, 0b00100, 0b00010, 0b00001, 0b00010, 0b00100, 0b01000]
        case 0x3F: return [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0, 0b00100]
        case 0x40: return [0b01110, 0b10001, 0b10111, 0b10101, 0b10111, 0b10000, 0b01110]
        case 0x41: return [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001]
        case 0x42: return [0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110]
        case 0x43: return [0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110]
        case 0x44: return [0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110]
        case 0x45: return [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111]
        case 0x46: return [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000]
        case 0x47: return [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01110]
        case 0x48: return [0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001]
        case 0x49: return [0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110]
        case 0x4A: return [0b00111, 0b00010, 0b00010, 0b00010, 0b10010, 0b10010, 0b01100]
        case 0x4B: return [0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001]
        case 0x4C: return [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111]
        case 0x4D: return [0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001]
        case 0x4E: return [0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001]
        case 0x4F: return [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110]
        case 0x50: return [0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000]
        case 0x51: return [0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101]
        case 0x52: return [0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001]
        case 0x53: return [0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110]
        case 0x54: return [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100]
        case 0x55: return [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110]
        case 0x56: return [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100]
        case 0x57: return [0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b10101, 0b01010]
        case 0x58: return [0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001]
        case 0x59: return [0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100]
        case 0x5A: return [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111]
        case 0x5B: return [0b01110, 0b01000, 0b01000, 0b01000, 0b01000, 0b01000, 0b01110]
        case 0x5C: return [0b10000, 0b01000, 0b00100, 0b00010, 0b00001, 0, 0]
        case 0x5D: return [0b01110, 0b00010, 0b00010, 0b00010, 0b00010, 0b00010, 0b01110]
        case 0x5E: return [0b00100, 0b01010, 0b10001, 0, 0, 0, 0]
        case 0x5F: return [0, 0, 0, 0, 0, 0, 0b11111]
        default:
            return [0, 0, 0, 0, 0, 0, 0]
        }
    }

    private static func classicColor(_ nibble: UInt8) -> IIGSRGBColor {
        let palette: [IIGSRGBColor] = [
            .black,
            IIGSRGBColor(red: 0xDD, green: 0x00, blue: 0x33),
            IIGSRGBColor(red: 0x00, green: 0x00, blue: 0x99),
            IIGSRGBColor(red: 0xDD, green: 0x22, blue: 0xDD),
            IIGSRGBColor(red: 0x00, green: 0x77, blue: 0x22),
            IIGSRGBColor(red: 0x55, green: 0x55, blue: 0x55),
            IIGSRGBColor(red: 0x22, green: 0x22, blue: 0xFF),
            IIGSRGBColor(red: 0x66, green: 0xAA, blue: 0xFF),
            IIGSRGBColor(red: 0x88, green: 0x55, blue: 0x00),
            IIGSRGBColor(red: 0xFF, green: 0x66, blue: 0x00),
            IIGSRGBColor(red: 0xAA, green: 0xAA, blue: 0xAA),
            IIGSRGBColor(red: 0xFF, green: 0x99, blue: 0x88),
            IIGSRGBColor(red: 0x11, green: 0xDD, blue: 0x00),
            IIGSRGBColor(red: 0xFF, green: 0xFF, blue: 0x00),
            IIGSRGBColor(red: 0x44, green: 0xFF, blue: 0x99),
            .white
        ]
        return palette[Int(nibble & 0x0F)]
    }

    private static func blankFrame(width: Int, height: Int) -> IIGSVideoFrame {
        IIGSVideoFrame(width: width, height: height, pixels: Array(repeating: .black, count: width * height))
    }
}
