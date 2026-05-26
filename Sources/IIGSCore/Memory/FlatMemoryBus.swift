import Foundation

public enum IIGSBatteryRAMProfile: Equatable, Sendable {
    case rom01
    case rom03
}

public struct IIGSBatteryRAMSettings: Equatable, Sendable {
    public static let rom01Default = IIGSBatteryRAMSettings(
        textColor: 0x0F,
        backgroundColor: 0x06,
        borderColor: 0x06,
        userVolume: 0x0F,
        slot5: 0x00,
        slot6: 0x00,
        slot7: 0x01,
        startupSlot: 0x00,
        visitMonitorCDAEnabled: false
    )

    public static let rom03Default = IIGSBatteryRAMSettings(
        textColor: 0x0F,
        backgroundColor: 0x06,
        borderColor: 0x06,
        userVolume: 0x0F,
        slot5: 0x00,
        slot6: 0x00,
        slot7: 0x01,
        startupSlot: 0x00,
        visitMonitorCDAEnabled: true
    )

    public var textColor: UInt8
    public var backgroundColor: UInt8
    public var borderColor: UInt8
    public var userVolume: UInt8
    public var slot5: UInt8
    public var slot6: UInt8
    public var slot7: UInt8
    public var startupSlot: UInt8
    public var visitMonitorCDAEnabled: Bool

    public init(
        textColor: UInt8,
        backgroundColor: UInt8,
        borderColor: UInt8,
        userVolume: UInt8,
        slot5: UInt8,
        slot6: UInt8,
        slot7: UInt8,
        startupSlot: UInt8,
        visitMonitorCDAEnabled: Bool
    ) {
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.userVolume = userVolume
        self.slot5 = slot5
        self.slot6 = slot6
        self.slot7 = slot7
        self.startupSlot = startupSlot
        self.visitMonitorCDAEnabled = visitMonitorCDAEnabled
    }
}

public final class FlatMemoryBus: IIGSBus {
    public static let fullAddressSpaceSize = 0x0100_0000
    public static let maximumExpansionRAMSize = 0x0080_0000

    private var bytes: [UInt8]
    private let logicalRAMSize: Int
    private let scheduler: IIGSEventScheduler?
    public private(set) var romImage: IIGSROMImage?
    public private(set) var softSwitches = IIGSSoftSwitchState()
    public private(set) var characterGenerator = IIGSCharacterGenerator()
    public private(set) var interruptState = IIGSInterruptState()
    public let adbController = IIGSADBController()
    public let iwmController = IIGSIWMController()
    public let soundController = IIGSSoundController()
    public private(set) var paddleController = IIGSPaddleController()
    public private(set) var debugIOTrace: [String] = []
    private var realTimeClock = IIGSRealTimeClock()

    public private(set) var cycleCount: UInt64 = 0
    public var traceProgramCounter: UInt32?

    public init(size: Int = FlatMemoryBus.fullAddressSpaceSize, scheduler: IIGSEventScheduler? = nil) {
        precondition(size > 0 && size <= FlatMemoryBus.fullAddressSpaceSize)
        self.bytes = Array(repeating: 0, count: size)
        self.logicalRAMSize = min(size, FlatMemoryBus.maximumExpansionRAMSize)
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
        guard isBackedRAM(address: address, storageIndex: index) else {
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
        if isLanguageCardRAMWriteProtectedAddress(address),
           romImage != nil,
           !softSwitches.languageCardWriteEnabled {
            return
        }
        let index = storageIndex(for: address, isWrite: true)
        guard isBackedRAM(address: address, storageIndex: index) else {
            return
        }
        bytes[index] = value
        shadowWrite(value, sourceAddress: address, sourceIndex: index)
    }

    public func idle(cycles: Int) {
        precondition(cycles >= 0)
        advanceCycles(UInt64(cycles))
    }

    public func drainAudio(sampleRate: Int = IIGSSoundController.defaultSampleRate) -> IIGSAudioBuffer {
        soundController.drainAudio(toCycle: cycleCount, sampleRate: sampleRate)
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

    public func setScanlineInterruptPending(line: Int) {
        guard softSwitches.videoControl & 0x80 != 0,
              (0..<IIGSVideoTiming.superHiresVisibleLines).contains(line)
        else {
            return
        }

        let scb = peek8(at: 0xE19D00 + UInt32(line))
        guard scb & 0x40 != 0 else {
            return
        }

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
        softSwitches.advanceVideoFrame(toCycle: cycleCount)
        scheduler?.advance(to: cycleCount)
    }

    private func synchronizeAudio() {
        soundController.queueAudio(toCycle: cycleCount)
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
        if let c07xROMByte = readC07xROMByte(at: address) {
            return c07xROMByte
        }
        if let slotFirmwareByte = readSlotFirmwareByte(at: address) {
            return slotFirmwareByte
        }
        if let romByte = readROMByte(at: address) {
            return romByte
        }
        let index = storageIndex(for: address, isWrite: false)
        guard isBackedRAM(address: address, storageIndex: index) else {
            return 0xFF
        }
        return bytes[index]
    }

    public func interruptVectorAddress(_ address: UInt32) -> UInt32 {
        let address = masked24(address)
        let lowAddress = UInt16(address & 0xFFFF)
        guard romImage != nil,
              (0xFFE4...0xFFFF).contains(lowAddress),
              softSwitches.shadowInhibit & 0x40 == 0
        else {
            return address
        }
        return 0xFF0000 | UInt32(lowAddress)
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
        realTimeClock.setROMVersion(romImage.version)
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

    public func clearRAM(fill value: UInt8 = 0) {
        bytes = Array(repeating: value, count: bytes.count)
    }

    public var batteryRAMSnapshot: [UInt8] {
        realTimeClock.parameterRAMSnapshot
    }

    public var batteryRAMRevision: UInt64 {
        realTimeClock.parameterRAMRevision
    }

    public var batteryRAMChecksumIsValid: Bool {
        realTimeClock.parameterRAMChecksumIsValid
    }

    public var batteryRAMProfile: IIGSBatteryRAMProfile {
        realTimeClock.parameterRAMProfile
    }

    public var batteryRAMSettings: IIGSBatteryRAMSettings {
        realTimeClock.parameterRAMSettings
    }

    public func loadBatteryRAM(_ bytes: [UInt8]) {
        realTimeClock.loadParameterRAM(bytes)
    }

    public func setBatteryRAMByte(_ value: UInt8, at index: UInt8, updateChecksum: Bool = true) {
        realTimeClock.setParameterRAMByte(value, at: index, updateChecksum: updateChecksum)
    }

    public func setBatteryRAMSettings(_ settings: IIGSBatteryRAMSettings) {
        realTimeClock.setParameterRAMSettings(settings)
    }

    public func setRealTimeClockSecondsSince1904(_ seconds: UInt32) {
        realTimeClock.setSecondsSince1904(seconds)
    }

    public func resetHardware(_ kind: IIGSResetKind = .cold) {
        cycleCount = 0
        softSwitches = IIGSSoftSwitchState()
        softSwitches.shadowInhibit = 0x08
        if let version = romImage?.version {
            softSwitches.setROMVersion(version)
        }
        interruptState = IIGSInterruptState()
        debugIOTrace.removeAll(keepingCapacity: true)
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
        if usesLanguageCardROMOverlay(address), softSwitches.languageCardReadROM {
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
        return usesLanguageCardROMOverlay(address) && romImage != nil && softSwitches.languageCardReadROM
    }

    private func storageIndex(for address: UInt32, isWrite: Bool) -> Int {
        let bank = UInt8((address >> 16) & 0xFF)
        let lowAddress = UInt16(address & 0xFFFF)
        if let slowIndex = slowMemoryStorageIndex(forBank: bank, lowAddress: lowAddress) {
            return slowIndex
        }
        if isLanguageCardAddress(address) {
            return languageCardStorageIndex(forBank: bank, lowAddress: lowAddress)
        }

        guard bank == 0x00 else {
            return Int(address)
        }

        if lowAddress < 0x0200 {
            return (softSwitches.alternateZeroPage ? 0x010000 : 0) + Int(lowAddress)
        }

        if lowAddress < 0xC000 {
            let auxiliary = isWrite ? softSwitches.ramWriteAuxiliary : softSwitches.ramReadAuxiliary
            if auxiliary {
                return 0x010000 + Int(lowAddress)
            }
        }

        return Int(address)
    }

    private func isBackedRAM(address: UInt32, storageIndex: Int) -> Bool {
        guard storageIndex < bytes.count else {
            return false
        }

        let bank = UInt8((address >> 16) & 0xFF)
        switch bank {
        case 0x00...0x7F:
            return storageIndex < logicalRAMSize
        case 0xE0, 0xE1:
            return true
        default:
            return false
        }
    }

    private func slowMemoryStorageIndex(forBank bank: UInt8, lowAddress: UInt16) -> Int? {
        switch bank {
        case 0xE0, 0xE1:
            guard lowAddress < 0xC000 else {
                return nil
            }
            return Int((UInt32(bank) << 16) | UInt32(lowAddress))
        default:
            return nil
        }
    }

    private func languageCardStorageIndex(forBank bank: UInt8, lowAddress: UInt16) -> Int {
        let mappedBank: UInt8
        switch bank {
        case 0x00:
            mappedBank = softSwitches.alternateZeroPage ? 0x01 : 0x00
        case 0x01:
            mappedBank = 0x01
        case 0xE0, 0xE1:
            mappedBank = bank
        default:
            mappedBank = bank
        }

        var mappedLowAddress = lowAddress
        if lowAddress < 0xE000, !softSwitches.languageCardBank2 {
            mappedLowAddress &-= 0x1000
        }
        return Int(UInt32(mappedBank) << 16 | UInt32(mappedLowAddress))
    }

    private func isLanguageCardAddress(_ address: UInt32) -> Bool {
        let bank = UInt8((address >> 16) & 0xFF)
        let lowAddress = UInt16(address & 0xFFFF)
        switch bank {
        case 0x00, 0x01, 0xE0, 0xE1:
            return lowAddress >= 0xD000
        default:
            return false
        }
    }

    private func usesLanguageCardROMOverlay(_ address: UInt32) -> Bool {
        let bank = UInt8((address >> 16) & 0xFF)
        guard bank == 0x00 || bank == 0x01 else {
            return false
        }
        return isLanguageCardAddress(address) && softSwitches.shadowInhibit & 0x40 == 0
    }

    private func isLanguageCardRAMWriteProtectedAddress(_ address: UInt32) -> Bool {
        let bank = UInt8((address >> 16) & 0xFF)
        guard bank == 0x00 || bank == 0x01 else {
            return false
        }
        return isLanguageCardAddress(address) && softSwitches.shadowInhibit & 0x40 == 0
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
        if let c07xROMByte = readC07xROMByte(at: address) {
            return c07xROMByte
        }
        let lowAddress = UInt16(address & 0xFFFF)
        if (0xC080...0xC08F).contains(lowAddress) {
            softSwitches.accessLanguageCardSwitch(lowAddress)
            return 0
        }
        if (0xC0E0...0xC0EF).contains(lowAddress) {
            return iwmController.accessSwitch(
                offset: UInt8(lowAddress & 0x000F),
                cycle: cycleCount,
                context: traceProgramCounter.map { "PC \(hex24($0))" }
            )
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
            traceIO("R C023 \(hexByte(interruptState.c023StatusRegister))")
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
            interruptState.clearC023Status(mask: IIGSInterruptState.c023ScanlinePendingMask)
            return IIGSVideoTiming.verticalCounter(atCycle: cycleCount)
        case 0xC02F:
            interruptState.clearC023Status(mask: IIGSInterruptState.c023ScanlinePendingMask)
            return IIGSVideoTiming.horizontalCounter(atCycle: cycleCount)
        case 0xC030:
            synchronizeAudio()
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
            synchronizeAudio()
            return soundController.readDataPort()
        case 0xC03E:
            return soundController.readPointerLow()
        case 0xC03F:
            return soundController.readPointerHigh()
        case 0xC041:
            traceIO("R C041 \(hexByte(interruptState.enableRegister))")
            return interruptState.enableRegister
        case 0xC046:
            let value = interruptState.videoStatusRegister | (irqLineAsserted ? IIGSInterruptState.systemIRQLineMask : 0)
            traceIO("R C046 \(hexByte(value))")
            return value
        case 0xC047:
            traceIO("R C047 clear")
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
            _ = iwmController.accessSwitch(
                offset: UInt8(lowAddress & 0x000F),
                value: value,
                isWrite: true,
                cycle: cycleCount,
                context: traceProgramCounter.map { "PC \(hex24($0))" }
            )
            return true
        }

        switch lowAddress {
        case 0xC010:
            adbController.clearKeyboardStrobe()
        case 0xC022:
            softSwitches.textColor = value
        case 0xC023:
            traceIO("W C023 \(hexByte(value))")
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
            traceIO("W C032 \(hexByte(value))")
            interruptState.clearC023StatusForC032(value: value)
        case 0xC033:
            realTimeClock.writeData(value)
        case 0xC034:
            realTimeClock.writeControl(value)
            softSwitches.setBorderColor(value, atCycle: cycleCount)
        case 0xC030:
            synchronizeAudio()
            _ = soundController.toggleSpeaker(atCycle: cycleCount)
        case 0xC03C:
            synchronizeAudio()
            soundController.writeSoundControl(value)
        case 0xC03D:
            synchronizeAudio()
            soundController.writeDataPort(value)
        case 0xC03E:
            synchronizeAudio()
            soundController.writePointerLow(value)
        case 0xC03F:
            synchronizeAudio()
            soundController.writePointerHigh(value)
        case 0xC041:
            traceIO("W C041 \(hexByte(value))")
            interruptState.enableRegister = value
            let disabledVideoSources = ~value & (IIGSInterruptState.verticalBlankMask | IIGSInterruptState.quarterSecondMask)
            interruptState.clearVideoStatus(mask: disabledVideoSources)
        case 0xC047:
            traceIO("W C047 \(hexByte(value))")
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

    private func readC07xROMByte(at address: UInt32) -> UInt8? {
        let lowAddress = UInt16(address & 0xFFFF)
        guard isIOPageAddress(address),
              (0xC071...0xC07F).contains(lowAddress)
        else {
            return nil
        }
        return romImage?.byte(mappedAt: 0xFF0000 | UInt32(lowAddress))
    }

    private func statusByte(_ enabled: Bool) -> UInt8 {
        enabled ? 0x80 : 0x00
    }

    private func traceIO(_ message: String) {
        let context = traceProgramCounter.map { "PC \(hex24($0)) " } ?? ""
        debugIOTrace.append("\(cycleCount) \(context)\(message)")
        if debugIOTrace.count > 4_096 {
            debugIOTrace.removeFirst(debugIOTrace.count - 4_096)
        }
    }

    private func hexByte(_ value: UInt8) -> String {
        let text = String(value, radix: 16, uppercase: true)
        return "$" + String(repeating: "0", count: max(0, 2 - text.count)) + text
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
              softSwitches.shadowInhibit & 0x08 == 0
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
        case idle
        case receiveExtendedBRAMAddress(readRequest: Bool)
        case bram(index: UInt8, readRequest: Bool)
        case clockByte(index: UInt8, readRequest: Bool)
        case internalRegister(index: UInt8, readRequest: Bool)
    }

    private static let appleEpochOffsetSeconds = UInt32(((66 * 365) + 17) * 24 * 60 * 60)

    private var dataRegister: UInt8 = 0
    private var controlRegister: UInt8 = 0
    private var state: TransactionState = .idle
    private var bramIndex: UInt8 = 0
    private var activeParameterRAMProfile: IIGSBatteryRAMProfile = .rom01
    private var usesProfileDefaultParameterRAM = true
    private var secondsSince1904: UInt32 = IIGSRealTimeClock.hostSecondsSince1904()
    private var fixedSecondsSince1904: UInt32?
    private var revision: UInt64 = 0
    private var parameterRAM: [UInt8] = IIGSRealTimeClock.defaultParameterRAM(for: .rom01)

    var parameterRAMSnapshot: [UInt8] {
        parameterRAM
    }

    var parameterRAMRevision: UInt64 {
        revision
    }

    var parameterRAMChecksumIsValid: Bool {
        Self.checksumIsValid(parameterRAM)
    }

    var parameterRAMProfile: IIGSBatteryRAMProfile {
        activeParameterRAMProfile
    }

    var parameterRAMSettings: IIGSBatteryRAMSettings {
        Self.settings(from: parameterRAM)
    }

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
            state = .idle
            return
        }

        let controlRequestsRead = value & 0x40 != 0
        switch state {
        case .idle:
            guard !controlRequestsRead else {
                state = .idle
                return
            }
            dispatchCommand(dataRegister)
        case let .receiveExtendedBRAMAddress(readRequest):
            guard !controlRequestsRead, dataRegister & 0x83 == 0 else {
                state = .idle
                return
            }
            bramIndex |= (dataRegister >> 2) & 0x1F
            state = .bram(index: bramIndex, readRequest: readRequest)
        case let .bram(index, readRequest):
            if controlRequestsRead, readRequest {
                dataRegister = parameterRAM[Int(index)]
            } else if !controlRequestsRead, !readRequest {
                parameterRAM[Int(index)] = dataRegister
                usesProfileDefaultParameterRAM = false
                revision &+= 1
            }
            state = .idle
        case let .clockByte(index, readRequest):
            if controlRequestsRead, readRequest {
                dataRegister = readClockByte(index: index)
            } else if !controlRequestsRead, !readRequest {
                writeClockByte(dataRegister, index: index)
            }
            state = .idle
        case .internalRegister:
            state = .idle
        }
    }

    mutating func setROMVersion(_ version: IIGSROMVersion) {
        let profile = IIGSBatteryRAMProfile(romVersion: version)
        guard activeParameterRAMProfile != profile else {
            return
        }

        activeParameterRAMProfile = profile
        if usesProfileDefaultParameterRAM {
            parameterRAM = Self.defaultParameterRAM(for: profile)
            revision &+= 1
        }
    }

    mutating func resetTransientState() {
        dataRegister = 0
        controlRegister = 0
        state = .idle
        bramIndex = 0
    }

    private mutating func dispatchCommand(_ value: UInt8) {
        let commandRequestsRead = value & 0x80 != 0
        let registerIndex = (value >> 2) & 0x03
        let operation = (value >> 4) & 0x07

        switch operation {
        case 0x00:
            refreshClockForHostTime()
            state = .clockByte(index: registerIndex, readRequest: commandRequestsRead)
        case 0x02:
            state = .bram(index: registerIndex &+ 0x10, readRequest: commandRequestsRead)
        case 0x03:
            if registerIndex & 0x02 != 0 {
                bramIndex = (value & 0x07) << 5
                state = .receiveExtendedBRAMAddress(readRequest: commandRequestsRead)
            } else {
                state = .internalRegister(index: registerIndex, readRequest: commandRequestsRead)
            }
        case 0x04...0x07:
            state = .bram(index: (value >> 2) & 0x0F, readRequest: commandRequestsRead)
        default:
            state = .idle
        }
    }

    private func readClockByte(index: UInt8) -> UInt8 {
        UInt8((secondsSince1904 >> (UInt32(index) * 8)) & 0xFF)
    }

    private mutating func writeClockByte(_ value: UInt8, index: UInt8) {
        let shift = UInt32(index) * 8
        let mask = UInt32(0xFF) << shift
        secondsSince1904 = (secondsSince1904 & ~mask) | (UInt32(value) << shift)
        fixedSecondsSince1904 = secondsSince1904
    }

    mutating func setSecondsSince1904(_ seconds: UInt32) {
        secondsSince1904 = seconds
        fixedSecondsSince1904 = seconds
    }

    mutating func loadParameterRAM(_ bytes: [UInt8]) {
        if bytes.count == parameterRAM.count, Self.checksumIsValid(bytes) {
            parameterRAM = bytes
            usesProfileDefaultParameterRAM = false
        } else {
            parameterRAM = Self.defaultParameterRAM(for: activeParameterRAMProfile)
            usesProfileDefaultParameterRAM = true
        }
        revision &+= 1
        resetTransientState()
    }

    mutating func setParameterRAMByte(_ value: UInt8, at index: UInt8, updateChecksum: Bool) {
        parameterRAM[Int(index)] = value
        usesProfileDefaultParameterRAM = false
        if updateChecksum {
            Self.updateChecksum(in: &parameterRAM)
        }
        revision &+= 1
    }

    mutating func setParameterRAMSettings(_ settings: IIGSBatteryRAMSettings) {
        parameterRAM[0x1A] = settings.textColor & 0x0F
        parameterRAM[0x1B] = settings.backgroundColor & 0x0F
        parameterRAM[0x1C] = settings.borderColor & 0x0F
        parameterRAM[0x1E] = settings.userVolume & 0x0F
        parameterRAM[0x25] = settings.slot5
        parameterRAM[0x26] = settings.slot6
        parameterRAM[0x27] = settings.slot7
        parameterRAM[0x28] = settings.startupSlot & 0x07
        if settings.visitMonitorCDAEnabled {
            parameterRAM[0x59] |= 0x80
        } else {
            parameterRAM[0x59] &= 0x7F
        }
        Self.updateChecksum(in: &parameterRAM)
        usesProfileDefaultParameterRAM = false
        revision &+= 1
    }

    private mutating func refreshClockForHostTime() {
        guard fixedSecondsSince1904 == nil else {
            return
        }
        secondsSince1904 = Self.hostSecondsSince1904()
    }

    private static func defaultParameterRAM(for profile: IIGSBatteryRAMProfile) -> [UInt8] {
        var bytes = Array(repeating: UInt8(0), count: 256)
        // These are the control-panel display defaults copied by ROM startup
        // into E1/02C0: white text, medium-blue background and border.
        bytes[0x1A] = 0x0F
        bytes[0x1B] = 0x06
        bytes[0x1C] = 0x06
        bytes[0x1E] = 0x0F // User volume.
        bytes[0x20] = 0x01
        bytes[0x25] = 0x00 // Slot 5 internal SmartPort / 3.5 drive firmware.
        bytes[0x26] = 0x00 // Slot 6 internal 5.25 drive firmware.
        bytes[0x27] = 0x01 // Slot 7 external "Your Card" unless user changes it.
        bytes[0x28] = 0x00 // Startup Slot: scan.
        if profile == .rom03 {
            // ROM 03 uses BRAM $59 to decide whether Visit Monitor/Memory
            // Peeker CDAs are installed during boot.
            bytes[0x59] = 0x80
        }
        updateChecksum(in: &bytes)
        return bytes
    }

    private static func settings(from bytes: [UInt8]) -> IIGSBatteryRAMSettings {
        IIGSBatteryRAMSettings(
            textColor: bytes[0x1A],
            backgroundColor: bytes[0x1B],
            borderColor: bytes[0x1C],
            userVolume: bytes[0x1E],
            slot5: bytes[0x25],
            slot6: bytes[0x26],
            slot7: bytes[0x27],
            startupSlot: bytes[0x28],
            visitMonitorCDAEnabled: bytes[0x59] & 0x80 != 0
        )
    }

    private static func hostSecondsSince1904(date: Date = Date()) -> UInt32 {
        let localizedUnixSeconds = date.timeIntervalSince1970
            + Double(TimeZone.current.secondsFromGMT(for: date))
        let appleSeconds = localizedUnixSeconds + Double(appleEpochOffsetSeconds)
        return UInt32(min(max(appleSeconds, 0), Double(UInt32.max)))
    }

    private static func checksumIsValid(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 256 else {
            return false
        }
        let checksum = computeChecksum(bytes)
        let stored = UInt16(bytes[0xFC]) | (UInt16(bytes[0xFD]) << 8)
        let complement = UInt16(bytes[0xFE]) | (UInt16(bytes[0xFF]) << 8)
        return stored == checksum && complement == (checksum ^ 0xAAAA)
    }

    private static func updateChecksum(in bytes: inout [UInt8]) {
        guard bytes.count == 256 else {
            return
        }
        let checksum = computeChecksum(bytes)
        let complement = checksum ^ 0xAAAA
        bytes[0xFC] = UInt8(checksum & 0xFF)
        bytes[0xFD] = UInt8((checksum >> 8) & 0xFF)
        bytes[0xFE] = UInt8(complement & 0xFF)
        bytes[0xFF] = UInt8((complement >> 8) & 0xFF)
    }

    private static func computeChecksum(_ bytes: [UInt8]) -> UInt16 {
        var checksum: UInt16 = 0
        for index in stride(from: 0xFA, through: 0x00, by: -1) {
            checksum = (checksum << 1) | (checksum >> 15)
            let word = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
            checksum = checksum &+ word
        }
        return checksum
    }
}

private extension IIGSBatteryRAMProfile {
    init(romVersion: IIGSROMVersion) {
        switch romVersion {
        case .rom01:
            self = .rom01
        case .rom03:
            self = .rom03
        }
    }
}
