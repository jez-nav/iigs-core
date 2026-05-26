import AppKit
import XCTest
@testable import IIGSCore

final class MacKeyboardInputMapperTests: XCTestCase {
    func testReturnMapsToADBReturnAndAppleIICarriageReturn() throws {
        let event = try XCTUnwrap(MacKeyboardInputMapper.keyEvent(
            characters: "\r",
            keyCode: 0x24,
            modifiers: [],
            isKeyUp: false
        ))

        XCTAssertEqual(event.keyCode, 0x24)
        XCTAssertEqual(event.ascii, 0x0D)
        XCTAssertFalse(event.isKeyUp)
    }

    func testModernMacArrowsMapToClassicIIgsADBKeyCodes() throws {
        let left = try XCTUnwrap(MacKeyboardInputMapper.keyEvent(
            characters: "",
            keyCode: 0x7B,
            modifiers: [],
            isKeyUp: false
        ))
        let up = try XCTUnwrap(MacKeyboardInputMapper.keyEvent(
            characters: "",
            keyCode: 0x7E,
            modifiers: [],
            isKeyUp: false
        ))

        XCTAssertEqual(left.keyCode, 0x3B)
        XCTAssertEqual(left.ascii, 0x08)
        XCTAssertEqual(up.keyCode, 0x3E)
        XCTAssertEqual(up.ascii, 0x0B)
    }

    func testOpenAppleClosedAppleAndCapsLockUseIIgsModifierBits() throws {
        XCTAssertEqual(IIGSADBModifiers.command.rawValue, 0x80)
        XCTAssertEqual(IIGSADBModifiers.option.rawValue, 0x40)
        XCTAssertEqual(IIGSADBModifiers.capsLock.rawValue, 0x04)

        let commandA = try XCTUnwrap(MacKeyboardInputMapper.keyEvent(
            characters: "a",
            keyCode: 0x00,
            modifiers: [.command],
            isKeyUp: false
        ))
        let optionA = try XCTUnwrap(MacKeyboardInputMapper.keyEvent(
            characters: "a",
            keyCode: 0x00,
            modifiers: [.option],
            isKeyUp: false
        ))

        XCTAssertTrue(commandA.modifiers.contains(.command))
        XCTAssertFalse(commandA.modifiers.contains(.option))
        XCTAssertTrue(optionA.modifiers.contains(.option))
        XCTAssertFalse(optionA.modifiers.contains(.command))
    }

    func testF1AndF2AliasOpenAppleAndClosedAppleKeys() throws {
        let f1 = try XCTUnwrap(MacKeyboardInputMapper.keyEvent(
            characters: "",
            keyCode: 0x7A,
            modifiers: [],
            isKeyUp: false
        ))
        let f2 = try XCTUnwrap(MacKeyboardInputMapper.keyEvent(
            characters: "",
            keyCode: 0x78,
            modifiers: [],
            isKeyUp: false
        ))

        XCTAssertEqual(f1.keyCode, 0x37)
        XCTAssertNil(f1.ascii)
        XCTAssertTrue(f1.modifiers.contains(.command))
        XCTAssertEqual(f2.keyCode, 0x3A)
        XCTAssertNil(f2.ascii)
        XCTAssertTrue(f2.modifiers.contains(.option))
    }

    func testF12AliasesControlResetKeyDown() throws {
        let f12 = try XCTUnwrap(MacKeyboardInputMapper.keyEvent(
            characters: "",
            keyCode: 0x6F,
            modifiers: [],
            isKeyUp: false
        ))

        XCTAssertEqual(f12.keyCode, 0x7F)
        XCTAssertTrue(f12.modifiers.contains(.control))
        XCTAssertTrue(f12.isControlResetKeyDown)
    }

    func testUpArrowKeyDownSendsEscapeCursorUpSequenceForBasic() throws {
        let events = MacKeyboardInputMapper.keyDownEvents(from: try makeKeyEvent(keyCode: 0x7E))

        XCTAssertEqual(events.map(\.keyCode), [0x35, 0x35, 0x02, 0x02])
        XCTAssertEqual(events.map(\.isKeyUp), [false, true, false, true])
        XCTAssertEqual(events.map(\.ascii), [UInt8(0x1B), nil, UInt8(0x44), nil])
        XCTAssertTrue(events[2].modifiers.contains(.shift))
    }

    func testFlagsChangedQueuesModifierPressAndRelease() throws {
        let commandDown = try XCTUnwrap(MacKeyboardInputMapper.flagsChanged(from: try makeFlagsEvent(
            keyCode: 0x37,
            flags: [.command]
        )))
        let commandUp = try XCTUnwrap(MacKeyboardInputMapper.flagsChanged(from: try makeFlagsEvent(
            keyCode: 0x37,
            flags: []
        )))

        XCTAssertEqual(commandDown.keyCode, 0x37)
        XCTAssertTrue(commandDown.modifiers.contains(.command))
        XCTAssertFalse(commandDown.isKeyUp)
        XCTAssertEqual(commandUp.keyCode, 0x37)
        XCTAssertFalse(commandUp.modifiers.contains(.command))
        XCTAssertTrue(commandUp.isKeyUp)
    }

    func testTranslatedInputAppliesToADBQueueAndAppleIIStrobe() throws {
        let machine = IIGSMachine()
        let down = try XCTUnwrap(MacKeyboardInputMapper.keyEvent(
            characters: "A",
            keyCode: 0x00,
            modifiers: [.shift],
            isKeyUp: false
        ))
        let up = try XCTUnwrap(MacKeyboardInputMapper.keyEvent(
            characters: "",
            keyCode: 0x00,
            modifiers: [],
            isKeyUp: true
        ))

        down.apply(to: machine)
        XCTAssertEqual(machine.memory[0x00C000], 0xC1)
        XCTAssertEqual(machine.memory[0x00C025] & IIGSADBModifiers.shift.rawValue, IIGSADBModifiers.shift.rawValue)

        machine.memory[0x00C026] = 0x2C
        XCTAssertEqual(machine.memory[0x00C026], 0x00)

        up.apply(to: machine)
        machine.memory[0x00C026] = 0x2C
        XCTAssertEqual(machine.memory[0x00C026], 0x80)
    }

    func testResetKeyPressCreatesADBResetDownAndUpEvents() throws {
        let events = MacKeyboardInputMapper.resetKeyPress()

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].keyCode, 0x7F)
        XCTAssertFalse(events[0].isKeyUp)
        XCTAssertEqual(events[1].keyCode, 0x7F)
        XCTAssertTrue(events[1].isKeyUp)
    }

    func testControlResetKeepsControlModifierActiveThroughResetKey() throws {
        let events = MacKeyboardInputMapper.resetKeyPress(modifiers: .control)

        XCTAssertEqual(events.map(\.keyCode), [0x36, 0x7F, 0x7F, 0x36])
        XCTAssertEqual(events.map(\.isKeyUp), [false, false, true, true])
        XCTAssertTrue(events[1].modifiers.contains(.control))
        XCTAssertTrue(events[2].modifiers.contains(.control))
        XCTAssertFalse(events[3].modifiers.contains(.control))
    }

    func testClassicDeskAccessoryKeyPressSendsOpenAppleControlEscape() throws {
        let events = MacKeyboardInputMapper.classicDeskAccessoryKeyPress()

        XCTAssertEqual(events.map(\.keyCode), [0x36, 0x37, 0x35, 0x35, 0x36, 0x37])
        XCTAssertEqual(events.map(\.isKeyUp), [false, false, false, true, true, true])
        XCTAssertEqual(events[2].ascii, 0x1B)
        XCTAssertTrue(events[2].modifiers.contains(.control))
        XCTAssertTrue(events[2].modifiers.contains(.command))
        XCTAssertTrue(events[3].modifiers.contains(.control))
        XCTAssertTrue(events[3].modifiers.contains(.command))
        XCTAssertFalse(events[4].modifiers.contains(.control))
        XCTAssertFalse(events[5].modifiers.contains(.command))
    }

    func testClassicDeskAccessoryGroupsKeepModifiersLatchedThroughEscape() throws {
        let groups = MacKeyboardInputMapper.classicDeskAccessoryEventGroups()
        let machine = IIGSMachine()

        XCTAssertEqual(groups.map(\.count), [2, 1, 1, 2])

        for event in groups[0] {
            event.apply(to: machine)
        }
        XCTAssertEqual(
            machine.memory[0x00C025] & (IIGSADBModifiers.control.rawValue | IIGSADBModifiers.command.rawValue),
            IIGSADBModifiers.control.rawValue | IIGSADBModifiers.command.rawValue
        )

        groups[1][0].apply(to: machine)
        XCTAssertEqual(machine.memory[0x00C000], 0x9B)
        XCTAssertEqual(machine.memory[0x00C027] & 0x20, 0x20)
        XCTAssertEqual(machine.memory[0x00C026], 0x20)
        XCTAssertEqual(
            machine.memory[0x00C025] & (IIGSADBModifiers.control.rawValue | IIGSADBModifiers.command.rawValue),
            IIGSADBModifiers.control.rawValue | IIGSADBModifiers.command.rawValue
        )

        groups[2][0].apply(to: machine)
        XCTAssertEqual(
            machine.memory[0x00C025] & (IIGSADBModifiers.control.rawValue | IIGSADBModifiers.command.rawValue),
            IIGSADBModifiers.control.rawValue | IIGSADBModifiers.command.rawValue
        )

        for event in groups[3] {
            event.apply(to: machine)
        }
        XCTAssertEqual(machine.memory[0x00C025] & IIGSADBModifiers.control.rawValue, 0)
        XCTAssertEqual(machine.memory[0x00C025] & IIGSADBModifiers.command.rawValue, 0)
    }

    func testControlCommandEscapeKeyEquivalentTriggersClassicDeskAccessoryOnlyOnce() throws {
        let event = try makeKeyEvent(keyCode: 0x35, flags: [.control, .command])
        let events = MacKeyboardInputMapper.keyEquivalentEvents(from: event)

        XCTAssertEqual(events.map(\.keyCode), [0x35, 0x35])
        XCTAssertEqual(events.map(\.isKeyUp), [false, true])
        XCTAssertEqual(events[0].ascii, 0x1B)
        XCTAssertTrue(events[0].modifiers.contains(.control))
        XCTAssertTrue(events[0].modifiers.contains(.command))
        XCTAssertTrue(MacKeyboardInputMapper.keyUpEvents(from: event).isEmpty)
    }

    func testSyntheticBasicTextProducesPacedKeyGroups() throws {
        let groups = MacKeyboardInputMapper.textInputEventGroups(for: "10 PRINT \"OK\"\n")
        let downEvents = groups.compactMap(\.first)

        XCTAssertEqual(groups.count, 14)
        XCTAssertEqual(downEvents.map(\.ascii), [
            0x31, 0x30, 0x20, 0x50, 0x52, 0x49, 0x4E,
            0x54, 0x20, 0x22, 0x4F, 0x4B, 0x22, 0x0D
        ])
        XCTAssertEqual(downEvents[9].keyCode, 0x27)
        XCTAssertTrue(downEvents[9].modifiers.contains(.shift))
        XCTAssertEqual(downEvents.last?.keyCode, 0x24)
    }

    func testMouseEventSplitsLargeDisplayDeltasIntoSafeADBChunks() {
        let events = IIGSHostMouseEvent.events(deltaX: 300, deltaY: -260, buttonDown: true)

        XCTAssertEqual(events, [
            IIGSHostMouseEvent(dx: 127, dy: -127, buttonDown: true),
            IIGSHostMouseEvent(dx: 127, dy: -127, buttonDown: true),
            IIGSHostMouseEvent(dx: 46, dy: -6, buttonDown: true)
        ])
    }

    func testMouseEventCanRepresentButtonOnlyTransition() {
        let events = IIGSHostMouseEvent.events(
            deltaX: 0,
            deltaY: 0,
            buttonDown: true,
            includeStationaryEvent: true
        )

        XCTAssertEqual(events, [IIGSHostMouseEvent(dx: 0, dy: 0, buttonDown: true)])
    }

    func testMouseEventAppliesToMachineADBMousePath() {
        let machine = IIGSMachine()

        IIGSHostMouseEvent(dx: 4, dy: -2, buttonDown: true).apply(to: machine)

        XCTAssertEqual(machine.memory[0x00C024], 0x84)
        XCTAssertEqual(machine.memory[0x00C024], 0x7E)
        XCTAssertEqual(machine.memory.adbController.mouseX, 4)
        XCTAssertEqual(machine.memory.adbController.mouseY, -2)
        XCTAssertTrue(machine.memory.adbController.mouseButtonDown)
    }

    private func makeFlagsEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func makeKeyEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
