public struct IIGSADBModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift = IIGSADBModifiers(rawValue: 0x01)
    public static let control = IIGSADBModifiers(rawValue: 0x02)
    public static let capsLock = IIGSADBModifiers(rawValue: 0x04)
    public static let option = IIGSADBModifiers(rawValue: 0x40)
    public static let command = IIGSADBModifiers(rawValue: 0x80)
}

public final class IIGSADBController {
    public private(set) var revision: UInt8
    public private(set) var modifierRegister: UInt8 = 0
    public private(set) var mouseX: Int16 = 0
    public private(set) var mouseY: Int16 = 0
    public private(set) var mouseButtonDown = false
    public private(set) var trace: [String] = []

    private var traceContext: String?
    private var keyboardLatch: UInt8 = 0
    private var keyboardStrobe = false
    private var appleIIKeyBuffer: [AppleIIKeyPress] = []
    private var responseHeader: UInt8?
    private var responseQueue: [UInt8] = []
    private var keyboardEvents: [UInt8] = []
    private var mouseBytes: [UInt8] = []
    private var adbRAM = Array(repeating: UInt8(0), count: 256)
    private var modeByte: UInt8 = 0
    private var configurationByte: UInt8 = 0
    private var configurationBytes = Array(repeating: UInt8(0), count: 3)
    private var errorByte: UInt8 = 0
    private var statusControl: UInt8 = 0
    private var commandFull = false
    private var keyboardAddress: UInt8 = 2
    private var mouseAddress: UInt8 = 3
    private var pendingCommand: PendingCommand?

    public init(revision: UInt8 = 5) {
        self.revision = revision
    }

    public var irqAsserted: Bool {
        let status = statusRegister
        return status & 0x20 != 0 && statusControl & 0x10 != 0
            || status & 0x80 != 0 && statusControl & 0x40 != 0
            || status & 0x08 != 0 && statusControl & 0x04 != 0
    }

    public var statusRegister: UInt8 {
        var status = statusControl & 0x56
        if !mouseBytes.isEmpty {
            status |= 0x80
        }
        if responseHeader != nil || !responseQueue.isEmpty {
            status |= 0x20
        }
        if !keyboardEvents.isEmpty {
            status |= 0x08
        }
        if commandFull {
            status |= 0x01
        }
        return status
    }

    func readStatusRegister() -> UInt8 {
        let status = statusRegister
        traceEvent("R C027 \(hex(status))")
        return status
    }

    public func setROMVersion(_ version: IIGSROMVersion) {
        switch version {
        case .rom01:
            revision = 5
        case .rom03:
            revision = 6
        }
    }

    public func reset() {
        responseHeader = nil
        responseQueue.removeAll()
        keyboardEvents.removeAll()
        mouseBytes.removeAll()
        pendingCommand = nil
        modifierRegister = 0
        keyboardLatch = 0
        keyboardStrobe = false
        appleIIKeyBuffer.removeAll()
        mouseX = 0
        mouseY = 0
        mouseButtonDown = false
        modeByte = 0
        configurationByte = 0
        configurationBytes = Array(repeating: UInt8(0), count: 3)
        errorByte = 0
        statusControl = 0
        commandFull = false
        keyboardAddress = 2
        mouseAddress = 3
        trace.removeAll()
    }

    public func injectAppleIIKey(_ ascii: UInt8, modifiers: IIGSADBModifiers = []) {
        let keyPress = AppleIIKeyPress(ascii: ascii & 0x7F, modifiers: modifiers)
        if keyboardStrobe {
            appleIIKeyBuffer.append(keyPress)
        } else {
            presentAppleIIKey(keyPress)
        }
    }

    public func setModifiers(_ modifiers: IIGSADBModifiers) {
        modifierRegister = modifiers.rawValue
    }

    public func queueKeyboardEvent(keyCode: UInt8, isKeyUp: Bool = false) {
        keyboardEvents.append((keyCode & 0x7F) | (isKeyUp ? 0x80 : 0x00))
    }

    public func queueKeyboardKeyDownUp(keyCode: UInt8) {
        queueKeyboardEvent(keyCode: keyCode, isKeyUp: false)
        queueKeyboardEvent(keyCode: keyCode, isKeyUp: true)
    }

    public func moveMouse(dx: Int8, dy: Int8, buttonDown: Bool) {
        mouseButtonDown = buttonDown
        mouseX = mouseX &+ Int16(dx)
        mouseY = mouseY &+ Int16(dy)
        mouseBytes.append(buttonDown ? 0x00 : 0x80)
        mouseBytes.append(UInt8(bitPattern: dx))
        mouseBytes.append(UInt8(bitPattern: dy))
    }

    func readKeyboardData() -> UInt8 {
        if !keyboardStrobe, !appleIIKeyBuffer.isEmpty {
            presentAppleIIKey(appleIIKeyBuffer.removeFirst())
        }
        return keyboardStrobe ? keyboardLatch | 0x80 : keyboardLatch
    }

    func clearKeyboardStrobe() {
        keyboardStrobe = false
    }

    func readMouseData() -> UInt8 {
        guard !mouseBytes.isEmpty else {
            return 0x80
        }
        return mouseBytes.removeFirst()
    }

    func readCommandData() -> UInt8 {
        commandFull = false
        if let header = responseHeader {
            responseHeader = nil
            traceEvent("R C026 header \(hex(header))")
            return header
        }
        guard !responseQueue.isEmpty else {
            traceEvent("R C026 empty 00")
            return 0
        }
        let value = responseQueue.removeFirst()
        traceEvent("R C026 data \(hex(value))")
        return value
    }

    func writeCommandData(_ value: UInt8) {
        commandFull = true
        traceEvent("W C026 \(hex(value))")
        if let pendingCommand {
            continuePendingCommand(pendingCommand, value: value)
            commandFull = false
            return
        }

        responseHeader = nil
        switch value {
        case 0x01:
            abortCommand()
        case 0x02:
            resetKeyboard()
        case 0x03:
            flushKeyboard()
        case 0x04:
            pendingCommand = .setModes
        case 0x05:
            self.pendingCommand = .clearModes
        case 0x06:
            pendingCommand = .setConfiguration([])
        case 0x07:
            pendingCommand = .sync(expectedCount: revision >= 6 ? 8 : 4, bytes: [])
        case 0x08:
            pendingCommand = .writeRAM([])
        case 0x09:
            pendingCommand = .readMemory([])
        case 0x0A:
            queueResult([modeByte])
        case 0x0B:
            queueResult([configurationByte])
        case 0x0C:
            queueResult([errorByte])
            errorByte = 0
        case 0x0D:
            queueResult([revision])
        case 0x0E:
            queueResult([0x00, 0x01, configuredCharacterSet])
        case 0x0F:
            queueResult([0x00, 0x01, configuredKeyboardLayout])
        case 0x10:
            resetController()
        case 0x11:
            pendingCommand = .sendKeyCode
        case 0x12:
            pendingCommand = .discard(expectedCount: 2, bytes: [])
        case 0x13:
            pendingCommand = .discard(expectedCount: 2, bytes: [])
        case 0x40:
            resetController()
        default:
            handleADBDeviceCommand(value)
        }
        commandFull = false
    }

    func writeStatusControl(_ value: UInt8) {
        statusControl = value & 0x56
        traceEvent("W C027 \(hex(value)) -> \(hex(statusControl))")
    }

    func setTraceContext(_ context: String?) {
        traceContext = context
    }

    private func continuePendingCommand(_ command: PendingCommand, value: UInt8) {
        switch command {
        case .setModes:
            modeByte |= value
            pendingCommand = nil
        case .clearModes:
            modeByte &= ~value
            pendingCommand = nil
        case .setConfiguration(var bytes):
            bytes.append(value)
            if bytes.count >= 3 {
                configurationBytes = Array(bytes.prefix(3))
                configurationByte = configurationBytes[0]
                pendingCommand = nil
            } else {
                pendingCommand = .setConfiguration(bytes)
            }
        case .sync(let expectedCount, var bytes):
            bytes.append(value)
            if bytes.count >= expectedCount {
                modeByte = bytes[0]
                configurationBytes = Array(bytes.prefix(3))
                configurationByte = configurationBytes[0]
                pendingCommand = nil
            } else {
                pendingCommand = .sync(expectedCount: expectedCount, bytes: bytes)
            }
        case .readMemory(var bytes):
            bytes.append(value)
            if bytes.count >= 2 {
                queueResult([readADBMemory(address: bytes[0], page: bytes[1])])
                pendingCommand = nil
            } else {
                pendingCommand = .readMemory(bytes)
            }
        case .writeRAM(var bytes):
            bytes.append(value)
            if bytes.count >= 2 {
                adbRAM[Int(bytes[0])] = bytes[1]
                pendingCommand = nil
            } else {
                pendingCommand = .writeRAM(bytes)
            }
        case .sendKeyCode:
            queueKeyboardEvent(keyCode: value)
            pendingCommand = nil
        case .discard(let expectedCount, var bytes):
            bytes.append(value)
            pendingCommand = bytes.count >= expectedCount ? nil : .discard(expectedCount: expectedCount, bytes: bytes)
        case .listenRegister3(let deviceAddress):
            pendingCommand = .listenRegister3Value(deviceAddress: deviceAddress, firstByte: value)
        case .listenRegister3Value(let deviceAddress, _):
            updateDeviceAddress(from: deviceAddress, register3LowByte: value)
            pendingCommand = nil
        }
    }

    private func handleADBDeviceCommand(_ value: UInt8) {
        let controllerCommand = value & 0xF0
        let classicADBCommand = value & 0x0C
        if controllerCommand >= 0x50 && classicADBCommand != 0x08 && classicADBCommand != 0x0C {
            handleControllerDeviceCommand(value)
            return
        }

        let deviceAddress = (value >> 4) & 0x0F
        let command = value & 0x0C
        let register = value & 0x03

        switch command {
        case 0x0C:
            talk(deviceAddress: deviceAddress, register: register)
        case 0x08:
            if register == 3 {
                pendingCommand = .listenRegister3(deviceAddress: deviceAddress)
            }
        default:
            break
        }
    }

    private func handleControllerDeviceCommand(_ value: UInt8) {
        let command = value & 0xF0
        let deviceAddress = value & 0x0F

        switch command {
        case 0x70:
            queueDeviceResponse([])
        case 0x60:
            queueDeviceResponse([])
        case 0x50:
            queueDeviceResponse([])
        case 0xB0:
            pendingCommand = .listenRegister3(deviceAddress: deviceAddress)
        case 0xC0:
            queueDeviceResponse(registerZeroBytes(for: deviceAddress))
        case 0xF0:
            queueDeviceResponse(registerThreeBytes(for: deviceAddress))
        default:
            break
        }
    }

    private func talk(deviceAddress: UInt8, register: UInt8) {
        if deviceAddress == keyboardAddress {
            talkKeyboard(register: register)
        } else if deviceAddress == mouseAddress {
            talkMouse(register: register)
        }
    }

    private func talkKeyboard(register: UInt8) {
        switch register {
        case 0:
            if !keyboardEvents.isEmpty {
                responseQueue.append(keyboardEvents.removeFirst())
            }
        case 3:
            responseQueue.append(0x00)
            responseQueue.append(keyboardAddress)
        default:
            break
        }
    }

    private func talkMouse(register: UInt8) {
        switch register {
        case 0:
            responseQueue.append(contentsOf: mouseBytes)
            mouseBytes.removeAll()
        case 3:
            responseQueue.append(0x00)
            responseQueue.append(mouseAddress)
        default:
            break
        }
    }

    private func registerZeroBytes(for deviceAddress: UInt8) -> [UInt8] {
        if deviceAddress == keyboardAddress {
            let first = keyboardEvents.isEmpty ? UInt8(0xFF) : keyboardEvents.removeFirst()
            let second = keyboardEvents.isEmpty ? UInt8(0xFF) : keyboardEvents.removeFirst()
            return [first, second]
        }
        if deviceAddress == mouseAddress {
            let bytes = Array(mouseBytes.prefix(2))
            mouseBytes.removeFirst(min(2, mouseBytes.count))
            return bytes + Array(repeating: UInt8(0), count: max(0, 2 - bytes.count))
        }
        return []
    }

    private func registerThreeBytes(for deviceAddress: UInt8) -> [UInt8] {
        if deviceAddress == keyboardAddress {
            return [0x02, keyboardAddress]
        }
        if deviceAddress == mouseAddress {
            return [0x01, mouseAddress]
        }
        return []
    }

    private func updateDeviceAddress(from oldAddress: UInt8, register3LowByte: UInt8) {
        let newAddress = register3LowByte & 0x0F
        guard newAddress > 0 else {
            return
        }

        if oldAddress == keyboardAddress {
            keyboardAddress = newAddress
        } else if oldAddress == mouseAddress {
            mouseAddress = newAddress
        }
    }

    private func resetController() {
        reset()
    }

    private func resetKeyboard() {
        flushKeyboard()
        modifierRegister = 0
        commandFull = false
    }

    private func flushKeyboard() {
        keyboardEvents.removeAll()
        appleIIKeyBuffer.removeAll()
        keyboardLatch = 0
        keyboardStrobe = false
        commandFull = false
    }

    private func presentAppleIIKey(_ keyPress: AppleIIKeyPress) {
        keyboardLatch = keyPress.ascii
        keyboardStrobe = true
        modifierRegister = keyPress.modifiers.rawValue
    }

    private func abortCommand() {
        responseHeader = nil
        responseQueue.removeAll()
        pendingCommand = nil
        commandFull = false
    }

    private func readADBMemory(address: UInt8, page: UInt8) -> UInt8 {
        if page == 0 {
            switch address {
            case 0xE2:
                return 0x06
            case 0xE8:
                var value: UInt8 = 0
                if modifierRegister & IIGSADBModifiers.command.rawValue != 0 {
                    value |= 0x20
                }
                if modifierRegister & IIGSADBModifiers.option.rawValue != 0 {
                    value |= 0x10
                }
                return value
            default:
                return adbRAM[Int(address)]
            }
        }

        let wrappedPage = page & 0x1F
        guard wrappedPage == 0x1F else {
            return 0
        }
        switch address {
        case 0x00:
            return 0x72
        case 0x01:
            return revision >= 6 ? 0x26 : 0xF7
        default:
            return 0
        }
    }

    private var keyboardSetupByte: UInt8 {
        configurationBytes.count > 1 ? configurationBytes[1] : configurationByte
    }

    private var configuredCharacterSet: UInt8 {
        (keyboardSetupByte >> 4) & 0x0F
    }

    private var configuredKeyboardLayout: UInt8 {
        keyboardSetupByte & 0x0F
    }

    private func queueResult(_ bytes: [UInt8]) {
        commandFull = false
        responseHeader = nil
        responseQueue = bytes
        traceEvent("Q result \(bytes.map(hex).joined(separator: " "))")
    }

    private func queueDeviceResponse(_ bytes: [UInt8]) {
        commandFull = false
        guard !bytes.isEmpty else {
            responseHeader = 0x80
            responseQueue.removeAll()
            traceEvent("Q 80")
            return
        }
        responseHeader = 0x80 | UInt8(max(0, bytes.count - 1) & 0x07)
        responseQueue = bytes
        traceEvent("Q \(hex(responseHeader ?? 0)) \(bytes.map(hex).joined(separator: " "))")
    }

    private func traceEvent(_ message: String) {
        let contextualMessage = traceContext.map { "\($0) \(message)" } ?? message
        if message.hasPrefix("R C027"), trace.last == contextualMessage {
            return
        }
        trace.append(contextualMessage)
        if trace.count > 2_048 {
            trace.removeFirst(trace.count - 2_048)
        }
    }

    private func hex(_ value: UInt8) -> String {
        let text = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 2 - text.count)) + text
    }

    private enum PendingCommand {
        case setModes
        case clearModes
        case setConfiguration([UInt8])
        case sync(expectedCount: Int, bytes: [UInt8])
        case readMemory([UInt8])
        case writeRAM([UInt8])
        case sendKeyCode
        case discard(expectedCount: Int, bytes: [UInt8])
        case listenRegister3(deviceAddress: UInt8)
        case listenRegister3Value(deviceAddress: UInt8, firstByte: UInt8)
    }

    private struct AppleIIKeyPress {
        let ascii: UInt8
        let modifiers: IIGSADBModifiers
    }
}
