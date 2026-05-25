import AppKit
import IIGSCore

struct IIGSHostKeyEvent: Equatable, Sendable {
    let ascii: UInt8?
    let keyCode: UInt8
    let modifiers: IIGSADBModifiers
    let isKeyUp: Bool

    var isControlResetKeyDown: Bool {
        !isKeyUp && keyCode == 0x7F && modifiers.contains(.control)
    }

    func apply(to machine: IIGSMachine) {
        if !isKeyUp, let ascii {
            machine.injectAppleIIKey(ascii, modifiers: modifiers)
        } else {
            machine.memory.adbController.setModifiers(modifiers)
        }
        machine.queueKeyboardEvent(keyCode: keyCode, isKeyUp: isKeyUp)
    }

    func apply(to session: IIGSDebuggerSession) {
        session.injectKeyboardInput(
            ascii: ascii,
            keyCode: keyCode,
            modifiers: modifiers,
            isKeyUp: isKeyUp
        )
    }
}

enum MacKeyboardInputMapper {
    static func resetKeyPress(modifiers: IIGSADBModifiers = []) -> [IIGSHostKeyEvent] {
        modifierEvents(for: modifiers, isKeyUp: false)
            + keyPressEvents(ascii: nil, keyCode: 0x7F, modifiers: modifiers, keyUpModifiers: modifiers)
            + modifierEvents(for: modifiers, isKeyUp: true)
    }

    static func textInputEventGroups(for text: String) -> [[IIGSHostKeyEvent]] {
        text.compactMap { character in
            guard let syntheticKey = syntheticKey(for: character) else {
                return nil
            }
            return keyPressEvents(
                ascii: syntheticKey.ascii,
                keyCode: syntheticKey.keyCode,
                modifiers: syntheticKey.modifiers
            )
        }
    }

    static func keyPressEvents(
        ascii: UInt8?,
        keyCode: UInt8,
        modifiers: IIGSADBModifiers = [],
        keyUpModifiers: IIGSADBModifiers = []
    ) -> [IIGSHostKeyEvent] {
        [
            IIGSHostKeyEvent(ascii: ascii, keyCode: keyCode, modifiers: modifiers, isKeyUp: false),
            IIGSHostKeyEvent(ascii: nil, keyCode: keyCode, modifiers: keyUpModifiers, isKeyUp: true)
        ]
    }

    static func keyDown(from event: NSEvent) -> IIGSHostKeyEvent? {
        keyEvent(
            characters: event.characters ?? event.charactersIgnoringModifiers ?? "",
            keyCode: event.keyCode,
            modifiers: event.modifierFlags,
            isKeyUp: false,
            isRepeat: event.isARepeat
        )
    }

    static func keyDownEvents(from event: NSEvent) -> [IIGSHostKeyEvent] {
        if event.keyCode == 0x7E, !event.isARepeat {
            return cursorUpEscapeSequence()
        }

        return keyDown(from: event).map { [$0] } ?? []
    }

    static func keyUp(from event: NSEvent) -> IIGSHostKeyEvent? {
        keyEvent(
            characters: event.characters ?? event.charactersIgnoringModifiers ?? "",
            keyCode: event.keyCode,
            modifiers: event.modifierFlags,
            isKeyUp: true,
            isRepeat: false
        )
    }

    static func keyUpEvents(from event: NSEvent) -> [IIGSHostKeyEvent] {
        if event.keyCode == 0x7E {
            return []
        }

        return keyUp(from: event).map { [$0] } ?? []
    }

    static func keyEquivalentEvents(from event: NSEvent) -> [IIGSHostKeyEvent] {
        guard event.type == .keyDown else {
            return []
        }

        let downEvents = keyDownEvents(from: event)
        guard !downEvents.isEmpty else {
            return []
        }

        return downEvents + keyUpEvents(from: event)
    }

    static func flagsChanged(from event: NSEvent) -> IIGSHostKeyEvent? {
        guard let keyCode = modifierADBKeyCode(from: event.keyCode) else {
            return nil
        }
        let modifiers = adbModifiers(from: event.modifierFlags)
        return IIGSHostKeyEvent(
            ascii: nil,
            keyCode: keyCode,
            modifiers: modifiers,
            isKeyUp: !modifierIsActive(forADBKeyCode: keyCode, in: event.modifierFlags)
        )
    }

    static func keyEvent(
        characters: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        isKeyUp: Bool,
        isRepeat: Bool = false
    ) -> IIGSHostKeyEvent? {
        guard !isRepeat || isKeyUp,
              let adbKeyCode = adbKeyCode(from: keyCode)
        else {
            return nil
        }
        let mappedModifiers = adbModifiers(from: modifiers)
            .union(aliasModifiers(forMacKeyCode: keyCode, isKeyUp: isKeyUp))
        return IIGSHostKeyEvent(
            ascii: isKeyUp ? nil : appleIIASCII(from: characters, adbKeyCode: adbKeyCode),
            keyCode: adbKeyCode,
            modifiers: mappedModifiers,
            isKeyUp: isKeyUp
        )
    }

    static func adbModifiers(from flags: NSEvent.ModifierFlags) -> IIGSADBModifiers {
        let deviceFlags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: IIGSADBModifiers = []
        if deviceFlags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if deviceFlags.contains(.control) {
            modifiers.insert(.control)
        }
        if deviceFlags.contains(.capsLock) {
            modifiers.insert(.capsLock)
        }
        if deviceFlags.contains(.option) {
            modifiers.insert(.option)
        }
        if deviceFlags.contains(.command) {
            modifiers.insert(.command)
        }
        return modifiers
    }

    private static func adbKeyCode(from macKeyCode: UInt16) -> UInt8? {
        let mapped: UInt16
        switch macKeyCode {
        case 0x36, 0x37:
            mapped = 0x37
        case 0x38, 0x3C:
            mapped = 0x38
        case 0x39:
            mapped = 0x39
        case 0x3A, 0x3D:
            mapped = 0x3A
        case 0x3B, 0x3E:
            mapped = 0x36
        case 0x6F:
            mapped = 0x7F
        case 0x78:
            mapped = 0x3A
        case 0x7A:
            mapped = 0x37
        case 0x7B...0x7E:
            mapped = macKeyCode - 0x40
        default:
            mapped = macKeyCode
        }
        guard mapped <= 0x7F else {
            return nil
        }
        return UInt8(mapped)
    }

    private static func aliasModifiers(forMacKeyCode keyCode: UInt16, isKeyUp: Bool) -> IIGSADBModifiers {
        guard !isKeyUp else {
            return []
        }

        switch keyCode {
        case 0x6F:
            return .control
        case 0x78:
            return .option
        case 0x7A:
            return .command
        default:
            return []
        }
    }

    private static func modifierADBKeyCode(from macKeyCode: UInt16) -> UInt8? {
        switch macKeyCode {
        case 0x36, 0x37:
            return 0x37
        case 0x38, 0x3C:
            return 0x38
        case 0x39:
            return 0x39
        case 0x3A, 0x3D:
            return 0x3A
        case 0x3B, 0x3E:
            return 0x36
        default:
            return nil
        }
    }

    private static func modifierIsActive(forADBKeyCode keyCode: UInt8, in flags: NSEvent.ModifierFlags) -> Bool {
        let deviceFlags = flags.intersection(.deviceIndependentFlagsMask)
        switch keyCode {
        case 0x36:
            return deviceFlags.contains(.control)
        case 0x37:
            return deviceFlags.contains(.command)
        case 0x38:
            return deviceFlags.contains(.shift)
        case 0x39:
            return deviceFlags.contains(.capsLock)
        case 0x3A:
            return deviceFlags.contains(.option)
        default:
            return false
        }
    }

    private static func appleIIASCII(from characters: String, adbKeyCode: UInt8) -> UInt8? {
        switch adbKeyCode {
        case 0x24, 0x4C:
            return 0x0D
        case 0x30:
            return 0x09
        case 0x33, 0x75:
            return 0x7F
        case 0x35:
            return 0x1B
        case 0x3B:
            return 0x08
        case 0x3C:
            return 0x15
        case 0x3D:
            return 0x0A
        case 0x3E:
            return 0x0B
        case 0x36, 0x37, 0x38, 0x39, 0x3A, 0x7F:
            return nil
        default:
            guard let scalar = characters.unicodeScalars.first, scalar.value <= 0x7F else {
                return nil
            }
            return UInt8(scalar.value)
        }
    }

    private static func modifierEvents(for modifiers: IIGSADBModifiers, isKeyUp: Bool) -> [IIGSHostKeyEvent] {
        let eventModifiers: IIGSADBModifiers = isKeyUp ? [] : modifiers
        var events: [IIGSHostKeyEvent] = []
        if modifiers.contains(.control) {
            events.append(IIGSHostKeyEvent(ascii: nil, keyCode: 0x36, modifiers: eventModifiers, isKeyUp: isKeyUp))
        }
        if modifiers.contains(.command) {
            events.append(IIGSHostKeyEvent(ascii: nil, keyCode: 0x37, modifiers: eventModifiers, isKeyUp: isKeyUp))
        }
        if modifiers.contains(.shift) {
            events.append(IIGSHostKeyEvent(ascii: nil, keyCode: 0x38, modifiers: eventModifiers, isKeyUp: isKeyUp))
        }
        if modifiers.contains(.capsLock) {
            events.append(IIGSHostKeyEvent(ascii: nil, keyCode: 0x39, modifiers: eventModifiers, isKeyUp: isKeyUp))
        }
        if modifiers.contains(.option) {
            events.append(IIGSHostKeyEvent(ascii: nil, keyCode: 0x3A, modifiers: eventModifiers, isKeyUp: isKeyUp))
        }
        return events
    }

    private static func cursorUpEscapeSequence() -> [IIGSHostKeyEvent] {
        keyPressEvents(ascii: 0x1B, keyCode: 0x35)
            + keyPressEvents(ascii: 0x44, keyCode: 0x02, modifiers: .shift)
    }

    private static func syntheticKey(for character: Character) -> (ascii: UInt8, keyCode: UInt8, modifiers: IIGSADBModifiers)? {
        let string = String(character)
        if string == "\n" || string == "\r" {
            return (0x0D, 0x24, [])
        }

        guard let scalar = string.unicodeScalars.first, scalar.value <= 0x7F else {
            return nil
        }

        if let keyCode = unshiftedSyntheticKeyCodes[character] {
            return (UInt8(scalar.value), keyCode, [])
        }

        let lowercased = Character(string.lowercased())
        if let keyCode = unshiftedSyntheticKeyCodes[lowercased],
           string.uppercased() == string,
           string.lowercased() != string {
            return (UInt8(scalar.value), keyCode, .shift)
        }

        if let keyCode = shiftedSyntheticKeyCodes[character] {
            return (UInt8(scalar.value), keyCode, .shift)
        }

        return nil
    }

    private static let unshiftedSyntheticKeyCodes: [Character: UInt8] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B,
        "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17,
        "=": 0x18, "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D,
        "]": 0x1E, "o": 0x1F, "u": 0x20, "[": 0x21, "i": 0x22, "p": 0x23,
        "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29, "\\": 0x2A,
        ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F,
        "\t": 0x30, " ": 0x31, "`": 0x32
    ]

    private static let shiftedSyntheticKeyCodes: [Character: UInt8] = [
        "!": 0x12, "@": 0x13, "#": 0x14, "$": 0x15, "^": 0x16, "%": 0x17,
        "+": 0x18, "(": 0x19, "&": 0x1A, "_": 0x1B, "*": 0x1C, ")": 0x1D,
        "}": 0x1E, "{": 0x21, "\"": 0x27, ":": 0x29, "|": 0x2A,
        "<": 0x2B, "?": 0x2C, ">": 0x2F, "~": 0x32
    ]
}
