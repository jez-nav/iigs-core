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

    func testSuperHires640UsesTwoBitPixels() {
        let memory = FlatMemoryBus()
        memory[0x00C029] = 0x80
        writePaletteEntry(0, raw: 0x0000, to: memory)
        writePaletteEntry(1, raw: 0x0F00, to: memory)
        writePaletteEntry(2, raw: 0x00F0, to: memory)
        writePaletteEntry(3, raw: 0x000F, to: memory)
        memory[0xE19D00] = 0x80
        memory[0xE12000] = 0x6C

        let frame = IIGSVideoRenderer.renderSuperHires(from: memory)

        XCTAssertEqual(frame[0, 0], IIGSRGBColor(red: 0xFF, green: 0x00, blue: 0x00))
        XCTAssertEqual(frame[1, 0], IIGSRGBColor(red: 0x00, green: 0xFF, blue: 0x00))
        XCTAssertEqual(frame[2, 0], IIGSRGBColor(red: 0x00, green: 0x00, blue: 0xFF))
        XCTAssertEqual(frame[3, 0], .black)
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
        memory[0x00C022] = 0x0F
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

        XCTAssertEqual(memory[0x00C022], 0x0F)
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
        memory[0x00C022] = 0x0F
        memory[0x000400] = 0xC1

        let frame = IIGSVideoRenderer.renderClassicText(from: memory)

        XCTAssertEqual(frame.width, 560)
        XCTAssertEqual(frame.height, 192)
        XCTAssertEqual(frame[2, 0], .white)
        XCTAssertEqual(frame[9, 0], .white)
    }

    func testRenderFrameSelectsSuperHiresWhenEnabled() {
        let memory = FlatMemoryBus()
        memory[0x00C029] = 0x80

        let frame = IIGSVideoRenderer.renderFrame(from: memory)

        XCTAssertEqual(frame.width, IIGSVideoRenderer.superHiresWidth)
        XCTAssertEqual(frame.height, IIGSVideoRenderer.superHiresHeight)
    }

    private func writePaletteEntry(_ entry: Int, raw: UInt16, to memory: FlatMemoryBus, palette: Int = 0) {
        let address = UInt32(0xE19E00 + (palette * 16 + entry) * 2)
        memory[address] = UInt8(raw & 0x00FF)
        memory[address + 1] = UInt8((raw >> 8) & 0x00FF)
    }
}
