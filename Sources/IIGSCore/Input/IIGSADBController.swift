public struct IIGSADBModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift = IIGSADBModifiers(rawValue: 0x01)
    public static let control = IIGSADBModifiers(rawValue: 0x02)
    public static let option = IIGSADBModifiers(rawValue: 0x04)
    public static let command = IIGSADBModifiers(rawValue: 0x08)
    public static let capsLock = IIGSADBModifiers(rawValue: 0x10)
}

public final class IIGSADBController {
    public private(set) var revision: UInt8
    public private(set) var modifierRegister: UInt8 = 0
    public private(set) var mouseX: Int16 = 0
    public private(set) var mouseY: Int16 = 0
    public private(set) var mouseButtonDown = false

    private var keyboardLatch: UInt8 = 0
    private var keyboardStrobe = false
    private var responseQueue: [UInt8] = []
    private var keyboardEvents: [UInt8] = []
    private var mouseBytes: [UInt8] = []
    private var adbRAM = Array(repeating: UInt8(0), count: 256)
    private var modeByte: UInt8 = 0
    private var configurationByte: UInt8 = 0
    private var statusControl: UInt8 = 0
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
        if !responseQueue.isEmpty {
            status |= 0x20
        }
        if !keyboardEvents.isEmpty {
            status |= 0x08
        }
        if pendingCommand != nil {
            status |= 0x01
        }
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
        responseQueue.removeAll()
        keyboardEvents.removeAll()
        mouseBytes.removeAll()
        pendingCommand = nil
        modifierRegister = 0
        keyboardLatch = 0
        keyboardStrobe = false
        mouseX = 0
        mouseY = 0
        mouseButtonDown = false
        modeByte = 0
        configurationByte = 0
        statusControl = 0
        keyboardAddress = 2
        mouseAddress = 3
    }

    public func injectAppleIIKey(_ ascii: UInt8, modifiers: IIGSADBModifiers = []) {
        keyboardLatch = ascii & 0x7F
        keyboardStrobe = true
        modifierRegister = modifiers.rawValue
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
        mouseBytes.append(buttonDown ? 0x80 : 0x00)
        mouseBytes.append(UInt8(bitPattern: dx))
        mouseBytes.append(UInt8(bitPattern: dy))
    }

    func readKeyboardData() -> UInt8 {
        keyboardStrobe ? keyboardLatch | 0x80 : keyboardLatch
    }

    func clearKeyboardStrobe() {
        keyboardStrobe = false
    }

    func readMouseData() -> UInt8 {
        guard !mouseBytes.isEmpty else {
            return 0
        }
        return mouseBytes.removeFirst()
    }

    func readCommandData() -> UInt8 {
        guard !responseQueue.isEmpty else {
            return 0
        }
        return responseQueue.removeFirst()
    }

    func writeCommandData(_ value: UInt8) {
        if let pendingCommand {
            continuePendingCommand(pendingCommand, value: value)
            return
        }

        switch value {
        case 0x00:
            resetController()
        case 0x01:
            self.pendingCommand = .setModes
        case 0x02:
            self.pendingCommand = .clearModes
        case 0x03:
            self.pendingCommand = .setConfiguration
        case 0x08:
            self.pendingCommand = .writeRAMAddress
        case 0x09:
            self.pendingCommand = .readRAMAddress
        case 0x0A:
            responseQueue.append(modeByte)
        case 0x0B:
            responseQueue.append(configurationByte)
        case 0x0D:
            responseQueue.append(revision)
        default:
            handleADBDeviceCommand(value)
        }
    }

    func writeStatusControl(_ value: UInt8) {
        statusControl = value & 0x56
    }

    private func continuePendingCommand(_ command: PendingCommand, value: UInt8) {
        switch command {
        case .setModes:
            modeByte |= value
            pendingCommand = nil
        case .clearModes:
            modeByte &= ~value
            pendingCommand = nil
        case .setConfiguration:
            configurationByte = value
            pendingCommand = nil
        case .readRAMAddress:
            responseQueue.append(adbRAM[Int(value)])
            pendingCommand = nil
        case .writeRAMAddress:
            pendingCommand = .writeRAMValue(address: value)
        case .writeRAMValue(let address):
            adbRAM[Int(address)] = value
            pendingCommand = nil
        case .listenRegister3(let deviceAddress):
            pendingCommand = .listenRegister3Value(deviceAddress: deviceAddress, firstByte: value)
        case .listenRegister3Value(let deviceAddress, _):
            updateDeviceAddress(from: deviceAddress, register3LowByte: value)
            pendingCommand = nil
        }
    }

    private func handleADBDeviceCommand(_ value: UInt8) {
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

    private enum PendingCommand {
        case setModes
        case clearModes
        case setConfiguration
        case readRAMAddress
        case writeRAMAddress
        case writeRAMValue(address: UInt8)
        case listenRegister3(deviceAddress: UInt8)
        case listenRegister3Value(deviceAddress: UInt8, firstByte: UInt8)
    }
}
