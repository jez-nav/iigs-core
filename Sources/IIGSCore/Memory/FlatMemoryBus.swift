public final class FlatMemoryBus: IIGSBus {
    public static let fullAddressSpaceSize = 0x0100_0000

    private var bytes: [UInt8]
    private let scheduler: IIGSEventScheduler?
    public private(set) var romImage: IIGSROMImage?
    public private(set) var softSwitches = IIGSSoftSwitchState()
    public private(set) var characterGenerator = IIGSCharacterGenerator()
    public private(set) var interruptState = IIGSInterruptState()
    public let adbController = IIGSADBController()
    public let iwmController = IIGSIWMController()
    public let soundController = IIGSSoundController()
    public private(set) var paddleController = IIGSPaddleController()
    private var realTimeClock = IIGSRealTimeClock()

    public private(set) var cycleCount: UInt64 = 0
    public var traceProgramCounter: UInt32?

    public init(size: Int = FlatMemoryBus.fullAddressSpaceSize, scheduler: IIGSEventScheduler? = nil) {
        precondition(size > 0 && size <= FlatMemoryBus.fullAddressSpaceSize)
        self.bytes = Array(repeating: 0, count: size)
        self.scheduler = scheduler
    }

    public func read8(at address: UInt32) -> UInt8 {
        advanceCycles(1)
        let address = masked24(address)
        if let softSwitchValue = readSoftSwitch(at: address) {
            return softSwitchValue
        }
        if let slotFirmwareByte = readSlotFirmwareByte(at: address) {
            return slotFirmwareByte
        }
        if let romByte = readROMByte(at: address) {
            return romByte
        }
        let index = storageIndex(for: address, isWrite: false)
        guard index < bytes.count else {
            return 0xFF
        }
        return bytes[index]
    }

    public func write8(_ value: UInt8, at address: UInt32) {
        advanceCycles(1)
        let address = masked24(address)
        if writeSoftSwitch(value, at: address) {
            return
        }
        if isSlotFirmwareAddress(address) {
            return
        }
        if isReadOnlyROM(at: address) {
            return
        }
        if isLanguageCardAddress(address), romImage != nil, !softSwitches.languageCardWriteEnabled {
            return
        }
        let index = storageIndex(for: address, isWrite: true)
        guard index < bytes.count else {
            return
        }
        bytes[index] = value
        shadowWrite(value, sourceAddress: address, sourceIndex: index)
    }

    public func idle(cycles: Int) {
        precondition(cycles >= 0)
        advanceCycles(UInt64(cycles))
    }

    public var irqLineAsserted: Bool {
        interruptState.irqAsserted || adbController.irqAsserted || soundController.docIRQAsserted
    }

    public var cpuSpeedMode: IIGSCPUSpeedMode {
        softSwitches.speedRegister & 0x80 != 0 ? .fast : .slow
    }

    public func setVerticalBlankInterruptPending() {
        guard interruptState.enableRegister & IIGSInterruptState.verticalBlankMask != 0 else {
            return
        }
        interruptState.setVerticalBlankPending()
    }

    public func setQuarterSecondInterruptPending() {
        guard interruptState.enableRegister & IIGSInterruptState.quarterSecondMask != 0 else {
            return
        }
        interruptState.setQuarterSecondPending()
    }

    public func setScanlineInterruptPending() {
        interruptState.setScanlinePending()
    }

    public func setOneSecondInterruptPending() {
        interruptState.setOneSecondPending()
    }

    public func setPaddlePosition(_ value: UInt8, paddle: UInt8) {
        paddleController.setPosition(value, paddle: paddle)
    }

    private func advanceCycles(_ cycles: UInt64) {
        guard cycles > 0 else {
            return
        }
        cycleCount += cycles
        scheduler?.advance(to: cycleCount)
    }

    public func peek8(at address: UInt32) -> UInt8 {
        let index = Int(masked24(address))
        guard index < bytes.count else {
            return 0xFF
        }
        return bytes[index]
    }

    public func debugRead8(at address: UInt32) -> UInt8 {
        let address = masked24(address)
        if let slotFirmwareByte = readSlotFirmwareByte(at: address) {
            return slotFirmwareByte
        }
        if let romByte = readROMByte(at: address) {
            return romByte
        }
        let index = storageIndex(for: address, isWrite: false)
        guard index < bytes.count else {
            return 0xFF
        }
        return bytes[index]
    }

    public func load(_ values: [UInt8], at startAddress: UInt32) {
        for (offset, value) in values.enumerated() {
            write8(value, at: startAddress &+ UInt32(offset))
        }
    }

    public func installROM(_ romImage: IIGSROMImage) {
        self.romImage = romImage
        softSwitches.setROMVersion(romImage.version)
        adbController.setROMVersion(romImage.version)
    }

    public func loadCharacterROM(_ bytes: [UInt8], bank: Int = 0, invertedBits: Bool = false) {
        characterGenerator.loadCharacterROM(bytes, bank: bank, invertedBits: invertedBits)
    }

    public func useFallbackCharacterGenerator() {
        characterGenerator = IIGSCharacterGenerator()
    }

    public func removeROM() {
        romImage = nil
    }

    public func resetHardware(_ kind: IIGSResetKind = .cold) {
        cycleCount = 0
        softSwitches = IIGSSoftSwitchState()
        softSwitches.shadowInhibit = 0x08
        if let version = romImage?.version {
            softSwitches.setROMVersion(version)
        }
        interruptState = IIGSInterruptState()
        adbController.reset()
        iwmController.reset()
        soundController.reset()
        paddleController = IIGSPaddleController()
        realTimeClock.resetTransientState()

        _ = kind
    }

    public subscript(address: UInt32) -> UInt8 {
        get { read8(at: address) }
        set { write8(newValue, at: address) }
    }

    private func readROMByte(at address: UInt32) -> UInt8? {
        if isLanguageCardAddress(address), softSwitches.languageCardReadROM {
            return romImage?.byte(languageCardAddress: UInt16(address & 0xFFFF))
        }
        return romImage?.byte(mappedAt: address)
    }

    private func readSlotFirmwareByte(at address: UInt32) -> UInt8? {
        guard isSlotFirmwareAddress(address) else {
            return nil
        }
        let lowAddress = address & 0xFFFF
        return romImage?.byte(mappedAt: 0xFF0000 | lowAddress)
    }

    private func isReadOnlyROM(at address: UInt32) -> Bool {
        if romImage?.contains(mappedAddress: address) == true {
            return true
        }
        return isLanguageCardAddress(address) && romImage != nil && softSwitches.languageCardReadROM
    }

    private func storageIndex(for address: UInt32, isWrite: Bool) -> Int {
        let bank = UInt8((address >> 16) & 0xFF)
        let lowAddress = UInt16(address & 0xFFFF)
        if let slowIndex = slowMemoryStorageIndex(forBank: bank, lowAddress: lowAddress) {
            return slowIndex
        }
        guard bank == 0x00 else {
            return Int(address)
        }

        if lowAddress < 0x0200, softSwitches.alternateZeroPage {
            return 0x010000 + Int(lowAddress)
        }

        if lowAddress < 0xC000 {
            let auxiliary = isWrite ? softSwitches.ramWriteAuxiliary : softSwitches.ramReadAuxiliary
            if auxiliary {
                return 0x010000 + Int(lowAddress)
            }
        }

        if lowAddress >= 0xD000 {
            return languageCardStorageIndex(for: lowAddress)
        }

        return Int(address)
    }

    private func slowMemoryStorageIndex(forBank bank: UInt8, lowAddress: UInt16) -> Int? {
        switch bank {
        case 0xE0:
            guard lowAddress < 0xC000 else {
                return nil
            }
            if classicShadowInhibitMask(for: lowAddress) != nil {
                return Int(0xE00000 + UInt32(lowAddress))
            }
            return Int(lowAddress)
        case 0xE1:
            guard lowAddress < 0xC000 else {
                return nil
            }
            if (0x2000...0x9FFF).contains(lowAddress) {
                return Int(0xE10000 + UInt32(lowAddress))
            }
            return Int(0x010000 + UInt32(lowAddress))
        default:
            return nil
        }
    }

    private func languageCardStorageIndex(for lowAddress: UInt16) -> Int {
        if lowAddress < 0xE000 {
            let bankBase = softSwitches.languageCardBank2 ? 0x010000 : 0x000000
            return bankBase + Int(lowAddress)
        }
        return Int(lowAddress)
    }

    private func isLanguageCardAddress(_ address: UInt32) -> Bool {
        let bank = UInt8((address >> 16) & 0xFF)
        let lowAddress = UInt16(address & 0xFFFF)
        return bank == 0x00 && lowAddress >= 0xD000
    }

    private func isSlotFirmwareAddress(_ address: UInt32) -> Bool {
        let bank = UInt8((address >> 16) & 0xFF)
        let lowAddress = UInt16(address & 0xFFFF)
        switch bank {
        case 0x00, 0x01, 0xE0, 0xE1:
            return (0xC100...0xCFFF).contains(lowAddress)
        default:
            return false
        }
    }

    private func readSoftSwitch(at address: UInt32) -> UInt8? {
        guard isIOPageAddress(address) else {
            return nil
        }
        let lowAddress = UInt16(address & 0xFFFF)
        if (0xC080...0xC08F).contains(lowAddress) {
            softSwitches.accessLanguageCardSwitch(lowAddress)
            return 0
        }
        if (0xC0E0...0xC0EF).contains(lowAddress) {
            return iwmController.accessSwitch(offset: UInt8(lowAddress & 0x000F))
        }

        switch lowAddress {
        case 0xC000:
            return adbController.readKeyboardData()
        case 0xC010:
            adbController.clearKeyboardStrobe()
            return 0
        case 0xC011:
            return statusByte(softSwitches.languageCardBank2)
        case 0xC012:
            return statusByte(!softSwitches.languageCardReadROM)
        case 0xC013:
            return statusByte(softSwitches.ramReadAuxiliary)
        case 0xC014:
            return statusByte(softSwitches.ramWriteAuxiliary)
        case 0xC016:
            return statusByte(softSwitches.alternateZeroPage)
        case 0xC018:
            return statusByte(softSwitches.eightyStore)
        case 0xC019:
            return IIGSVideoTiming.verticalBlankStatus(atCycle: cycleCount)
        case 0xC01A:
            return statusByte(!softSwitches.textMode)
        case 0xC01B:
            return statusByte(softSwitches.mixedMode)
        case 0xC01C:
            return statusByte(softSwitches.page2)
        case 0xC01D:
            return statusByte(softSwitches.hires)
        case 0xC01E:
            return statusByte(softSwitches.alternateCharacterSet)
        case 0xC01F:
            return statusByte(softSwitches.eightyColumnVideo)
        case 0xC021:
            return 0
        case 0xC023:
            return interruptState.c023StatusRegister
        case 0xC022:
            return softSwitches.textColor
        case 0xC024:
            return adbController.readMouseData()
        case 0xC025:
            return adbController.modifierRegister
        case 0xC026:
            adbController.setTraceContext(traceProgramCounter.map { "PC \(hex24($0))" })
            return adbController.readCommandData()
        case 0xC027:
            adbController.setTraceContext(traceProgramCounter.map { "PC \(hex24($0))" })
            return adbController.readStatusRegister()
        case 0xC029:
            return softSwitches.videoControl
        case 0xC02E:
            return IIGSVideoTiming.verticalCounter(atCycle: cycleCount)
        case 0xC02F:
            return IIGSVideoTiming.horizontalCounter(atCycle: cycleCount)
        case 0xC030:
            return soundController.toggleSpeaker(atCycle: cycleCount)
        case 0xC031:
            return iwmController.readDriveControlRegister()
        case 0xC032:
            return 0
        case 0xC033:
            return realTimeClock.readData()
        case 0xC034:
            return realTimeClock.readControl()
        case 0xC03C:
            return soundController.readSoundControl()
        case 0xC03D:
            return soundController.readDataPort()
        case 0xC03E:
            return soundController.readPointerLow()
        case 0xC03F:
            return soundController.readPointerHigh()
        case 0xC041:
            return interruptState.enableRegister
        case 0xC046:
            return interruptState.videoStatusRegister
        case 0xC047:
            interruptState.clearAllVideoStatus()
            return 0
        case 0xC060:
            return 0
        case 0xC061:
            return adbController.modifierRegister & IIGSADBModifiers.command.rawValue != 0 ? 0x80 : 0x00
        case 0xC062:
            return adbController.modifierRegister & IIGSADBModifiers.option.rawValue != 0 ? 0x80 : 0x00
        case 0xC063:
            return 0
        case 0xC02D:
            return softSwitches.slotROMSelect
        case 0xC035:
            return softSwitches.shadowInhibit
        case 0xC036:
            return softSwitches.speedRegister & 0xDF
        case 0xC068:
            return softSwitches.stateRegister
        case 0xC064...0xC067:
            return paddleController.read(paddle: UInt8(lowAddress & 0x0003), at: cycleCount)
        case 0xC070:
            paddleController.trigger(at: cycleCount)
            return 0
        default:
            applyClassicSoftSwitch(lowAddress)
            return 0
        }
    }

    private func writeSoftSwitch(_ value: UInt8, at address: UInt32) -> Bool {
        guard isIOPageAddress(address) else {
            return false
        }
        let lowAddress = UInt16(address & 0xFFFF)
        if (0xC080...0xC08F).contains(lowAddress) {
            softSwitches.accessLanguageCardSwitch(lowAddress)
            return true
        }
        if (0xC0E0...0xC0EF).contains(lowAddress) {
            _ = iwmController.accessSwitch(offset: UInt8(lowAddress & 0x000F), value: value, isWrite: true)
            return true
        }

        switch lowAddress {
        case 0xC010:
            adbController.clearKeyboardStrobe()
        case 0xC022:
            softSwitches.textColor = value
        case 0xC023:
            interruptState.c023EnableRegister = value
        case 0xC026:
            adbController.setTraceContext(traceProgramCounter.map { "PC \(hex24($0))" })
            adbController.writeCommandData(value)
        case 0xC027:
            adbController.setTraceContext(traceProgramCounter.map { "PC \(hex24($0))" })
            adbController.writeStatusControl(value)
        case 0xC029:
            softSwitches.videoControl = value
        case 0xC02D:
            softSwitches.slotROMSelect = value
        case 0xC031:
            iwmController.writeDriveControlRegister(value)
        case 0xC032:
            interruptState.clearC023Status(mask: value)
        case 0xC033:
            realTimeClock.writeData(value)
        case 0xC034:
            realTimeClock.writeControl(value)
        case 0xC030:
            _ = soundController.toggleSpeaker(atCycle: cycleCount)
        case 0xC03C:
            soundController.writeSoundControl(value)
        case 0xC03D:
            soundController.writeDataPort(value)
        case 0xC03E:
            soundController.writePointerLow(value)
        case 0xC03F:
            soundController.writePointerHigh(value)
        case 0xC041:
            interruptState.enableRegister = value
            let disabledVideoSources = ~value & (IIGSInterruptState.verticalBlankMask | IIGSInterruptState.quarterSecondMask)
            interruptState.clearVideoStatus(mask: disabledVideoSources)
        case 0xC047:
            interruptState.clearVideoStatus(mask: value == 0 ? 0xFF : value)
        case 0xC035:
            softSwitches.shadowInhibit = value
        case 0xC036:
            softSwitches.speedRegister = value & 0xDF
        case 0xC068:
            softSwitches.writeStateRegister(value)
        case 0xC064...0xC067:
            break
        case 0xC070:
            paddleController.trigger(at: cycleCount)
        default:
            applyClassicSoftSwitch(lowAddress)
        }
        return true
    }

    private func isIOPageAddress(_ address: UInt32) -> Bool {
        let bank = UInt8((address >> 16) & 0xFF)
        let lowAddress = UInt16(address & 0xFFFF)
        switch bank {
        case 0x00, 0x01, 0xE0, 0xE1:
            return (0xC000...0xC0FF).contains(lowAddress)
        default:
            return false
        }
    }

    private func statusByte(_ enabled: Bool) -> UInt8 {
        enabled ? 0x80 : 0x00
    }

    private func hex24(_ value: UInt32) -> String {
        let text = String(value & 0x00FF_FFFF, radix: 16, uppercase: true)
        return "$" + String(repeating: "0", count: max(0, 6 - text.count)) + text
    }

    private func applyClassicSoftSwitch(_ lowAddress: UInt16) {
        switch lowAddress {
        case 0xC000:
            softSwitches.eightyStore = false
        case 0xC001:
            softSwitches.eightyStore = true
        case 0xC002:
            softSwitches.ramReadAuxiliary = false
        case 0xC003:
            softSwitches.ramReadAuxiliary = true
        case 0xC004:
            softSwitches.ramWriteAuxiliary = false
        case 0xC005:
            softSwitches.ramWriteAuxiliary = true
        case 0xC006:
            softSwitches.internalCxROM = false
        case 0xC007:
            softSwitches.internalCxROM = true
        case 0xC008:
            softSwitches.alternateZeroPage = false
        case 0xC009:
            softSwitches.alternateZeroPage = true
        case 0xC00C:
            softSwitches.eightyColumnVideo = false
        case 0xC00D:
            softSwitches.eightyColumnVideo = true
        case 0xC00E:
            softSwitches.alternateCharacterSet = false
        case 0xC00F:
            softSwitches.alternateCharacterSet = true
        case 0xC050:
            softSwitches.textMode = false
        case 0xC051:
            softSwitches.textMode = true
        case 0xC052:
            softSwitches.mixedMode = false
        case 0xC053:
            softSwitches.mixedMode = true
        case 0xC054:
            softSwitches.page2 = false
        case 0xC055:
            softSwitches.page2 = true
        case 0xC056:
            softSwitches.hires = false
        case 0xC057:
            softSwitches.hires = true
        default:
            break
        }
    }

    private func shadowWrite(_ value: UInt8, sourceAddress: UInt32, sourceIndex: Int) {
        let sourceBank = UInt8((sourceAddress >> 16) & 0xFF)
        let sourceLowAddress = UInt16(sourceAddress & 0xFFFF)
        let effectiveBank = UInt8((sourceIndex >> 16) & 0xFF)
        let effectiveLowAddress = UInt16(sourceIndex & 0xFFFF)

        if sourceBank == 0x00, effectiveBank <= 0x01 {
            shadowClassicWrite(value, lowAddress: effectiveLowAddress)
        } else if sourceBank <= 0x01 {
            shadowClassicWrite(value, lowAddress: sourceLowAddress)
        }

        if shouldShadowSuperHires(fromBank: effectiveBank, lowAddress: effectiveLowAddress) {
            writeRaw(value, at: 0xE10000 + UInt32(effectiveLowAddress))
        } else if sourceBank <= 0x01, shouldShadowSuperHires(fromBank: sourceBank, lowAddress: sourceLowAddress) {
            writeRaw(value, at: 0xE10000 + UInt32(sourceLowAddress))
        }
    }

    private func shadowClassicWrite(_ value: UInt8, lowAddress: UInt16) {
        guard let inhibitMask = classicShadowInhibitMask(for: lowAddress),
              softSwitches.shadowInhibit & inhibitMask == 0
        else {
            return
        }
        writeRaw(value, at: 0xE00000 + UInt32(lowAddress))
    }

    private func classicShadowInhibitMask(for lowAddress: UInt16) -> UInt8? {
        switch lowAddress {
        case 0x0400...0x07FF:
            return 0x01
        case 0x0800...0x0BFF:
            return 0x02
        case 0x2000...0x3FFF:
            return 0x04
        case 0x4000...0x5FFF:
            return 0x08
        default:
            return nil
        }
    }

    private func shouldShadowSuperHires(fromBank bank: UInt8, lowAddress: UInt16) -> Bool {
        guard (0x2000...0x9FFF).contains(lowAddress),
              softSwitches.shadowInhibit & 0x10 == 0
        else {
            return false
        }

        if bank == 0x01 {
            return true
        }

        let shadowAllEnabled = softSwitches.speedRegister & 0x10 != 0
        return shadowAllEnabled && bank % 2 == 1 && bank < 0xE0
    }

    private func writeRaw(_ value: UInt8, at address: UInt32) {
        let index = Int(masked24(address))
        guard index < bytes.count else {
            return
        }
        bytes[index] = value
    }

}

private struct IIGSRealTimeClock {
    private enum TransactionState {
        case receiveCommand
        case receiveBRAMAddress(read: Bool)
        case readBRAM
        case writeBRAM
        case readClock(index: UInt32)
        case writeClock(index: UInt32)
        case registerWrite
    }

    private var dataRegister: UInt8 = 0
    private var controlRegister: UInt8 = 0
    private var state: TransactionState = .receiveCommand
    private var bramIndex: UInt8 = 0
    private var secondsSince1904: UInt32 = 0
    private var parameterRAM: [UInt8] = {
        var bytes = Array(repeating: UInt8(0), count: 256)
        // These are the control-panel display defaults copied by ROM startup
        // into E1/02C0: white text, medium-blue background and border.
        bytes[0x1A] = 0x0F
        bytes[0x1B] = 0x06
        bytes[0x1C] = 0x06
        bytes[0x20] = 0x01
        return bytes
    }()

    mutating func readData() -> UInt8 {
        dataRegister
    }

    func readControl() -> UInt8 {
        controlRegister & 0x7F
    }

    mutating func writeData(_ value: UInt8) {
        dataRegister = value
    }

    mutating func writeControl(_ value: UInt8) {
        controlRegister = value & 0x7F
        guard value & 0x80 != 0 else {
            return
        }

        guard value & 0x20 != 0 else {
            state = .receiveCommand
            return
        }

        let isReadOperation = value & 0x40 != 0
        switch state {
        case .receiveCommand:
            dispatchCommand(dataRegister)
        case let .receiveBRAMAddress(read):
            bramIndex |= (dataRegister >> 2) & 0x1F
            state = read ? .readBRAM : .writeBRAM
        case .readBRAM:
            if isReadOperation {
                dataRegister = parameterRAM[Int(bramIndex)]
                state = .receiveCommand
            } else {
                dispatchCommand(dataRegister)
            }
        case .writeBRAM:
            if !isReadOperation {
                parameterRAM[Int(bramIndex)] = dataRegister
                state = .receiveCommand
            }
        case let .readClock(index):
            if isReadOperation {
                dataRegister = readClockByte(index: index)
                state = .receiveCommand
            } else {
                dispatchCommand(dataRegister)
            }
        case let .writeClock(index):
            if !isReadOperation {
                writeClockByte(dataRegister, index: index)
                state = .receiveCommand
            }
        case .registerWrite:
            break
        }
    }

    mutating func resetTransientState() {
        dataRegister = 0
        controlRegister = 0
        state = .receiveCommand
        bramIndex = 0
    }

    private mutating func dispatchCommand(_ value: UInt8) {
        let command = (value >> 3) & 0x0F
        let option = value & 0x07
        let commandRequestsRead = value & 0x80 != 0

        switch command {
        case 0x00:
            let index = UInt32(option)
            state = commandRequestsRead ? .readClock(index: index) : .writeClock(index: index)
        case 0x01:
            let index = UInt32(option) | 0x8000_0000
            state = commandRequestsRead ? .readClock(index: index) : .writeClock(index: index)
        case 0x06:
            state = .registerWrite
        case 0x07:
            bramIndex = option << 5
            state = .receiveBRAMAddress(read: commandRequestsRead)
        default:
            state = .receiveCommand
        }
    }

    private func readClockByte(index: UInt32) -> UInt8 {
        let option = UInt8(index & 0xFF)
        guard option & 0x01 != 0 else {
            return 0
        }
        if index & 0x8000_0000 != 0 {
            return option & 0x04 != 0
                ? UInt8((secondsSince1904 >> 24) & 0xFF)
                : UInt8((secondsSince1904 >> 16) & 0xFF)
        }
        return option & 0x04 != 0
            ? UInt8((secondsSince1904 >> 8) & 0xFF)
            : UInt8(secondsSince1904 & 0xFF)
    }

    private mutating func writeClockByte(_ value: UInt8, index: UInt32) {
        let option = UInt8(index & 0xFF)
        guard option & 0x01 != 0 else {
            return
        }
        if index & 0x8000_0000 != 0 {
            if option & 0x04 != 0 {
                secondsSince1904 = (secondsSince1904 & 0x00FF_FFFF) | (UInt32(value) << 24)
            } else {
                secondsSince1904 = (secondsSince1904 & 0xFF00_FFFF) | (UInt32(value) << 16)
            }
        } else if option & 0x04 != 0 {
            secondsSince1904 = (secondsSince1904 & 0xFFFF_00FF) | (UInt32(value) << 8)
        } else {
            secondsSince1904 = (secondsSince1904 & 0xFFFF_FF00) | UInt32(value)
        }
    }
}
