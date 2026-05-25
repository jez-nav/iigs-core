import XCTest
@testable import IIGSCore

final class VideoPhase6Tests: XCTestCase {
    func testVideoTimingPositionAndVBLBoundary() {
        XCTAssertEqual(IIGSVideoTiming.cyclesPerFrame, 17_030)
        XCTAssertEqual(IIGSVideoTiming.position(atCycle: 0), IIGSVideoPosition(line: 0, cycleInLine: 0, frameCycle: 0, inVerticalBlank: false))
        XCTAssertEqual(IIGSVideoTiming.position(atCycle: 64), IIGSVideoPosition(line: 0, cycleInLine: 64, frameCycle: 64, inVerticalBlank: false))
        XCTAssertEqual(IIGSVideoTiming.position(atCycle: 65), IIGSVideoPosition(line: 1, cycleInLine: 0, frameCycle: 65, inVerticalBlank: false))

        let vblankStart = UInt64(IIGSVideoTiming.classicVisibleLines * IIGSVideoTiming.cyclesPerLine)
        XCTAssertEqual(IIGSVideoTiming.verticalBlankStatus(atCycle: vblankStart - 1), 0x00)
        XCTAssertEqual(IIGSVideoTiming.verticalBlankStatus(atCycle: vblankStart), 0x80)
        XCTAssertEqual(IIGSVideoTiming.position(atCycle: UInt64(IIGSVideoTiming.cyclesPerFrame)).line, 0)
    }

    func testVideoTimingRegistersFollowBusCycleCount() {
        let memory = FlatMemoryBus()
        memory.idle(cycles: IIGSVideoTiming.classicVisibleLines * IIGSVideoTiming.cyclesPerLine - 1)

        XCTAssertEqual(memory[0x00C019], 0x80)

        let secondMemory = FlatMemoryBus()
        secondMemory.idle(cycles: IIGSVideoTiming.cyclesPerLine - 1)
        XCTAssertEqual(secondMemory[0x00C02E], 0x80)
        XCTAssertEqual(secondMemory[0x00C02F], 0xC0)
    }

    func testSuperHires320UsesPaletteAndExpandsNibbles() {
        let memory = FlatMemoryBus()
        memory[0x00C029] = 0x80
        writePaletteEntry(1, raw: 0x0F00, to: memory)
        writePaletteEntry(2, raw: 0x00F0, to: memory)
        memory[0xE19D00] = 0x00
        memory[0xE12000] = 0x12

        let frame = IIGSVideoRenderer.renderSuperHires(from: memory)

        XCTAssertEqual(frame.width, 640)
        XCTAssertEqual(frame.height, 200)
        XCTAssertEqual(frame[0, 0], IIGSRGBColor(red: 0xFF, green: 0x00, blue: 0x00))
        XCTAssertEqual(frame[1, 0], IIGSRGBColor(red: 0xFF, green: 0x00, blue: 0x00))
        XCTAssertEqual(frame[2, 0], IIGSRGBColor(red: 0x00, green: 0xFF, blue: 0x00))
        XCTAssertEqual(frame[3, 0], IIGSRGBColor(red: 0x00, green: 0xFF, blue: 0x00))
    }

    func testSuperHires640UsesPairedPaletteInterpretation() {
        let memory = FlatMemoryBus()
        memory[0x00C029] = 0x80
        writePaletteEntry(3, raw: 0x000F, to: memory)
        writePaletteEntry(4, raw: 0x0F00, to: memory)
        writePaletteEntry(9, raw: 0x00F0, to: memory)
        writePaletteEntry(14, raw: 0x0FFF, to: memory)
        memory[0xE19D00] = 0x80
        memory[0xE12000] = 0x6C

        let frame = IIGSVideoRenderer.renderSuperHires(from: memory)

        XCTAssertEqual(frame[0, 0], IIGSRGBColor(red: 0x00, green: 0xFF, blue: 0x00))
        XCTAssertEqual(frame[1, 0], .white)
        XCTAssertEqual(frame[2, 0], IIGSRGBColor(red: 0x00, green: 0x00, blue: 0xFF))
        XCTAssertEqual(frame[3, 0], IIGSRGBColor(red: 0xFF, green: 0x00, blue: 0x00))
    }

    func testSuperHires640StandardWhiteSelectorIsContinuousAcrossByte() {
        let memory = FlatMemoryBus()
        memory[0x00C029] = 0x80
        for entry in [3, 7, 11, 15] {
            writePaletteEntry(entry, raw: 0x0FFF, to: memory)
        }
        memory[0xE19D00] = 0x80
        memory[0xE12000] = 0xFF

        let frame = IIGSVideoRenderer.renderSuperHires(from: memory)

        for x in 0..<4 {
            XCTAssertEqual(frame[x, 0], .white, "640-mode selector 3 should use all four white standard-palette entries.")
        }
    }

    func testSuperHiresFillModeRepeatsLastNonzeroNibble() {
        let memory = FlatMemoryBus()
        memory[0x00C029] = 0x80
        writePaletteEntry(1, raw: 0x0F00, to: memory)
        memory[0xE19D00] = 0x20
        memory[0xE12000] = 0x10

        let frame = IIGSVideoRenderer.renderSuperHires(from: memory)

        XCTAssertEqual(frame[0, 0], IIGSRGBColor(red: 0xFF, green: 0x00, blue: 0x00))
        XCTAssertEqual(frame[1, 0], IIGSRGBColor(red: 0xFF, green: 0x00, blue: 0x00))
        XCTAssertEqual(frame[2, 0], IIGSRGBColor(red: 0xFF, green: 0x00, blue: 0x00))
        XCTAssertEqual(frame[3, 0], IIGSRGBColor(red: 0xFF, green: 0x00, blue: 0x00))
    }

    func testClassicTextRendererUsesShadowPage() {
        let memory = FlatMemoryBus()
        memory[0x00C022] = 0xF0
        memory[0x000400] = 0xC1

        let frame = IIGSVideoRenderer.renderClassicText(from: memory)

        XCTAssertEqual(frame.width, 280)
        XCTAssertEqual(frame.height, 192)
        XCTAssertEqual(frame[0, 0], .black)
        XCTAssertEqual(frame[2, 0], .white)
        XCTAssertEqual(frame[1, 3], .white)
    }

    func testClassicTextRendererHasVisibleColdResetTextColor() {
        let memory = FlatMemoryBus()
        memory[0x000400] = 0xC1

        let frame = IIGSVideoRenderer.renderClassicText(from: memory)

        XCTAssertEqual(memory[0x00C022], 0xF6)
        XCTAssertEqual(frame[0, 0], IIGSRGBColor(red: 0x22, green: 0x22, blue: 0xFF))
        XCTAssertEqual(frame[2, 0], .white)
    }

    func testClassicTextRendererAllowsExplicitBlackOnBlackTextColor() {
        let memory = FlatMemoryBus()
        memory[0x00C022] = 0x00
        memory[0x000400] = 0xC1

        let frame = IIGSVideoRenderer.renderClassicText(from: memory)

        XCTAssertEqual(frame[0, 0], .black)
    }

    func testClassicTextRendererTracksEightyColumnWidth() {
        let memory = FlatMemoryBus()
        memory[0x00C00D] = 0
        memory[0x00C022] = 0xF0
        memory[0x000400] = 0xC1
        memory[0x010400] = 0xA0

        let frame = IIGSVideoRenderer.renderClassicText(from: memory)

        XCTAssertEqual(frame.width, 560)
        XCTAssertEqual(frame.height, 192)
        XCTAssertEqual(frame[2, 0], .black)
        XCTAssertEqual(frame[9, 0], .white)
    }

    func testCharacterGeneratorCanLoadRuntimeCharacterROM() {
        var rom = Array(repeating: UInt8(0), count: 256 * IIGSCharacterGlyph.height)
        let glyphOffset = 0x41 * IIGSCharacterGlyph.height
        rom[glyphOffset] = 0x7F

        var generator = IIGSCharacterGenerator()
        generator.loadCharacterROM(rom)
        let glyph = generator.glyph(forScreenByte: 0xC1, alternateCharacterSet: false)

        XCTAssertEqual(generator.source, .characterROM)
        XCTAssertTrue(glyph.pixelLit(x: 0, y: 0))
        XCTAssertTrue(glyph.pixelLit(x: 6, y: 0))
        XCTAssertFalse(glyph.pixelLit(x: 0, y: 1))
    }

    func testAlternateCharacterSetUsesMouseTextGlyphs() {
        let memory = FlatMemoryBus()
        memory[0x00C022] = 0xF0
        memory[0x00C00F] = 0
        memory[0x000400] = 0x40
        memory[0x000401] = 0x4C

        let frame = IIGSVideoRenderer.renderClassicText(from: memory)

        XCTAssertEqual(memory[0x00C01E] & 0x80, 0x80)
        XCTAssertEqual(frame[4, 0], .white)
        XCTAssertEqual(frame[0, 3], .white)
        XCTAssertEqual(frame[6, 3], .white)
        XCTAssertEqual(frame[7, 0], .white)
        XCTAssertEqual(frame[13, 0], .white)
    }

    func testFallbackHyphenGlyphRepeatsWithoutStartupLineGaps() {
        let memory = FlatMemoryBus()
        memory[0x00C022] = 0xF0
        memory[0x000400] = 0xAD
        memory[0x000401] = 0xAD

        let frame = IIGSVideoRenderer.renderClassicText(from: memory)

        for x in 0..<14 {
            XCTAssertEqual(frame[x, 3], .white)
        }
    }

    func testPrimaryCharacterSetFlashesLowRangeBytes() {
        let memory = FlatMemoryBus()
        memory[0x00C022] = 0xF0
        memory[0x000400] = 0x41
        memory.idle(cycles: IIGSVideoTiming.cyclesPerFrame * 30)

        let frame = IIGSVideoRenderer.renderClassicText(from: memory)

        XCTAssertEqual(frame[2, 0], .black)
    }

    func testFlashingSpaceRendersAsBlinkingCursorBlock() {
        let memory = FlatMemoryBus()
        memory[0x00C022] = 0xF0
        memory[0x000400] = 0x60

        let offFrame = IIGSVideoRenderer.renderClassicText(from: memory)
        XCTAssertEqual(offFrame[0, 0], .black)

        memory.idle(cycles: IIGSVideoTiming.cyclesPerFrame * 30)
        let onFrame = IIGSVideoRenderer.renderClassicText(from: memory)

        XCTAssertEqual(onFrame[0, 0], .white)
        XCTAssertEqual(onFrame[6, 7], .white)
    }

    func testFallbackCharacterGeneratorProvidesCheckerboardCursorGlyph() {
        let generator = IIGSCharacterGenerator()
        let glyph = generator.glyph(forCode: 0x7F)

        XCTAssertTrue(glyph.pixelLit(x: 0, y: 0))
        XCTAssertFalse(glyph.pixelLit(x: 1, y: 0))
        XCTAssertFalse(glyph.pixelLit(x: 0, y: 1))
        XCTAssertTrue(glyph.pixelLit(x: 1, y: 1))
    }

    func testClassicTextRendererOverlaysFirmwareCursorFromZeroPage() {
        let memory = FlatMemoryBus()
        memory[0x00C022] = 0xF0
        memory[0x000400] = 0xA0
        memory[0x000024] = 1
        memory[0x000025] = 0
        memory[0x000033] = 0xDD
        memory.idle(cycles: IIGSVideoTiming.cyclesPerFrame * 30)

        let frame = IIGSVideoRenderer.renderClassicText(from: memory)

        XCTAssertEqual(frame[7, 0], .white)
        XCTAssertEqual(frame[8, 0], .black)
        XCTAssertEqual(frame[7, 1], .black)
        XCTAssertEqual(frame[8, 1], .white)
        XCTAssertEqual(frame[0, 0], .black)
    }

    func testFallbackCharacterGeneratorKeepsLowercaseDistinct() {
        let generator = IIGSCharacterGenerator()
        let uppercaseA = generator.glyph(forScreenByte: 0xC1, alternateCharacterSet: false)
        let lowercaseA = generator.glyph(forScreenByte: 0xE1, alternateCharacterSet: false)

        XCTAssertNotEqual(uppercaseA, lowercaseA)
        XCTAssertTrue(lowercaseA.pixelLit(x: 5, y: 3))
        XCTAssertFalse(lowercaseA.pixelLit(x: 2, y: 0))
    }

    func testRenderFrameSelectsSuperHiresWhenEnabled() {
        let memory = FlatMemoryBus()
        memory[0x00C029] = 0x80

        let frame = IIGSVideoRenderer.renderFrame(from: memory)

        XCTAssertEqual(frame.width, IIGSVideoRenderer.superHiresWidth + IIGSVideoRenderer.wideBorderX * 2)
        XCTAssertEqual(frame.height, IIGSVideoRenderer.superHiresHeight + IIGSVideoRenderer.superHiresBorderY * 2)
    }

    func testRenderFrameAddsBorderUsingC034Color() {
        let memory = FlatMemoryBus()
        memory[0x00C034] = 0x0D
        memory[0x000400] = 0xA0

        let frame = IIGSVideoRenderer.renderFrame(from: memory)

        XCTAssertEqual(frame.width, IIGSVideoRenderer.classicGraphicsWidth + IIGSVideoRenderer.classicBorderX * 2)
        XCTAssertEqual(frame.height, IIGSVideoRenderer.classicGraphicsHeight + IIGSVideoRenderer.classicBorderY * 2)
        XCTAssertEqual(frame[0, 0], IIGSRGBColor(red: 0xFF, green: 0xFF, blue: 0x00))
        XCTAssertEqual(frame[IIGSVideoRenderer.classicBorderX, IIGSVideoRenderer.classicBorderY], IIGSRGBColor(red: 0x22, green: 0x22, blue: 0xFF))
    }

    func testBorderColorCanVaryByScanline() {
        let memory = FlatMemoryBus()
        memory[0x00C034] = 0x01
        memory.idle(cycles: IIGSVideoTiming.cyclesPerLine)
        memory[0x00C034] = 0x0D

        let frame = IIGSVideoRenderer.renderFrame(from: memory)

        XCTAssertEqual(frame[0, 0], IIGSRGBColor(red: 0xDD, green: 0x00, blue: 0x33))
        XCTAssertEqual(frame[0, 1], IIGSRGBColor(red: 0xFF, green: 0xFF, blue: 0x00))
    }

    func testBorderColorCanFollowVideoCounterLoop() throws {
        let machine = IIGSMachine()
        let program: [UInt8] = [
            0xAD, 0x2E, 0xC0, // LDA $C02E
            0x8D, 0x34, 0xC0, // STA $C034
            0x80, 0xF8        // BRA $0300
        ]
        for (offset, byte) in program.enumerated() {
            machine.memory[0x000300 + UInt32(offset)] = byte
        }
        machine.cpu.updateRegisters { registers in
            registers.programCounter = 0x0300
        }

        try machine.runForCycles(
            IIGSVideoTiming.cyclesPerFrame + IIGSVideoTiming.cyclesPerLine,
            instructionLimit: 20_000
        )

        let visibleColors = Set(machine.memory.softSwitches.displayBorderColors.prefix(IIGSVideoTiming.classicVisibleLines))
        XCTAssertGreaterThan(visibleColors.count, 1)
    }

    private func writePaletteEntry(_ entry: Int, raw: UInt16, to memory: FlatMemoryBus, palette: Int = 0) {
        let address = UInt32(0xE19E00 + (palette * 16 + entry) * 2)
        memory[address] = UInt8(raw & 0x00FF)
        memory[address + 1] = UInt8((raw >> 8) & 0x00FF)
    }
}
