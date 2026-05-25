import XCTest
@testable import IIGSCore

final class VideoPhase6_5Tests: XCTestCase {
    func testRenderFrameSelectsLoresWhenGraphicsModeIsEnabledWithoutHires() {
        let memory = FlatMemoryBus()
        memory[0x00C050] = 0
        memory[0x00C056] = 0
        memory[0x000400] = 0x21

        let frame = IIGSVideoRenderer.renderFrame(from: memory)

        XCTAssertEqual(frame.width, 320)
        XCTAssertEqual(frame.height, 240)
        XCTAssertEqual(frame[20, 24], IIGSRGBColor(red: 0xDD, green: 0x00, blue: 0x33))
        XCTAssertEqual(frame[20, 28], IIGSRGBColor(red: 0x00, green: 0x00, blue: 0x99))
    }

    func testClassicLoresUsesAppleTextPageLayout() {
        let memory = FlatMemoryBus()
        memory[0x000428] = 0x03

        let frame = IIGSVideoRenderer.renderClassicLores(from: memory)

        XCTAssertEqual(frame[0, 64], IIGSRGBColor(red: 0xDD, green: 0x22, blue: 0xDD))
    }

    func testClassicHiresAddressOffsetMatchesInterleavedRows() {
        XCTAssertEqual(IIGSVideoRenderer.classicHiresAddressOffset(forScanline: 0, byteColumn: 0), 0x0000)
        XCTAssertEqual(IIGSVideoRenderer.classicHiresAddressOffset(forScanline: 1, byteColumn: 0), 0x0400)
        XCTAssertEqual(IIGSVideoRenderer.classicHiresAddressOffset(forScanline: 8, byteColumn: 0), 0x0080)
        XCTAssertEqual(IIGSVideoRenderer.classicHiresAddressOffset(forScanline: 64, byteColumn: 0), 0x0028)
        XCTAssertEqual(IIGSVideoRenderer.classicHiresAddressOffset(forScanline: 191, byteColumn: 39), 0x1FF7)
    }

    func testClassicHiresRendersSevenPixelsPerByteFromShadowPage() {
        let memory = FlatMemoryBus()
        memory[0x00C022] = 0xF0
        memory[0x002000] = 0x41

        let frame = IIGSVideoRenderer.renderClassicHires(from: memory)

        XCTAssertEqual(frame.width, 280)
        XCTAssertEqual(frame.height, 192)
        XCTAssertEqual(frame[0, 0], .white)
        XCTAssertEqual(frame[1, 0], .black)
        XCTAssertEqual(frame[6, 0], .white)
    }

    func testClassicHiresUsesPageTwoWhenSelected() {
        let memory = FlatMemoryBus()
        memory[0x00C022] = 0xF0
        memory[0x002000] = 0x00
        memory[0x004000] = 0x01
        memory[0x00C055] = 0

        let frame = IIGSVideoRenderer.renderClassicHires(from: memory)

        XCTAssertEqual(frame[0, 0], .white)
        XCTAssertEqual(frame[1, 0], .black)
    }

    func testClassicHiresMixedModeDrawsBottomTextRows() {
        let memory = FlatMemoryBus()
        memory[0x00C022] = 0xF0
        memory[0x00C053] = 0
        memory[0x000650] = 0xC1

        let frame = IIGSVideoRenderer.renderClassicHires(from: memory)

        XCTAssertEqual(frame[0, 159], .black)
        XCTAssertEqual(frame[0, 160], .black)
        XCTAssertEqual(frame[2, 160], .white)
        XCTAssertEqual(frame[1, 163], .white)
    }

    func testRenderFrameSelectsHiresWhenGraphicsAndHiresAreEnabled() {
        let memory = FlatMemoryBus()
        memory[0x00C050] = 0
        memory[0x00C057] = 0
        memory[0x00C022] = 0xF0
        memory[0x002000] = 0x01

        let frame = IIGSVideoRenderer.renderFrame(from: memory)

        XCTAssertEqual(frame[IIGSVideoRenderer.classicBorderX, IIGSVideoRenderer.classicBorderY], .white)
        XCTAssertEqual(frame.width, IIGSVideoRenderer.classicGraphicsWidth + IIGSVideoRenderer.classicBorderX * 2)
        XCTAssertEqual(frame.height, IIGSVideoRenderer.classicGraphicsHeight + IIGSVideoRenderer.classicBorderY * 2)
    }
}
