public struct IIGSSoftSwitchState: Equatable, Sendable {
    public var eightyStore: Bool
    public var ramReadAuxiliary: Bool
    public var ramWriteAuxiliary: Bool
    public var internalCxROM: Bool
    public var alternateZeroPage: Bool
    public var eightyColumnVideo: Bool
    public var alternateCharacterSet: Bool
    public var textMode: Bool
    public var mixedMode: Bool
    public var page2: Bool
    public var hires: Bool
    public var shadowInhibit: UInt8
    public var textColor: UInt8
    public var borderColor: UInt8
    public var videoControl: UInt8
    public var slotROMSelect: UInt8
    public var speedRegister: UInt8
    public private(set) var displayBorderColors: [UInt8]
    public private(set) var languageCardReadROM: Bool
    public private(set) var languageCardWriteEnabled: Bool
    public private(set) var languageCardBank2: Bool
    public private(set) var romBank: Bool

    private var languageCardPrewriteArmed: Bool
    private var activeBorderColors: [UInt8]
    private var activeBorderFrame: UInt64

    public init() {
        self.eightyStore = false
        self.ramReadAuxiliary = false
        self.ramWriteAuxiliary = false
        self.internalCxROM = false
        self.alternateZeroPage = false
        self.eightyColumnVideo = false
        self.alternateCharacterSet = false
        self.textMode = true
        self.mixedMode = false
        self.page2 = false
        self.hires = false
        self.shadowInhibit = 0
        self.textColor = 0xF6
        self.borderColor = 0x06
        self.videoControl = 0x01
        self.slotROMSelect = 0
        self.speedRegister = 0
        self.displayBorderColors = Array(repeating: 0x06, count: IIGSVideoTiming.scanlinesPerFrame)
        self.languageCardReadROM = true
        self.languageCardWriteEnabled = false
        self.languageCardBank2 = true
        self.romBank = false
        self.languageCardPrewriteArmed = false
        self.activeBorderColors = Array(repeating: 0x06, count: IIGSVideoTiming.scanlinesPerFrame)
        self.activeBorderFrame = 0
    }

    public var stateRegister: UInt8 {
        (alternateZeroPage ? 0x80 : 0)
            | (page2 ? 0x40 : 0)
            | (ramReadAuxiliary ? 0x20 : 0)
            | (ramWriteAuxiliary ? 0x10 : 0)
            | (languageCardReadROM ? 0x08 : 0)
            | (languageCardBank2 ? 0x04 : 0)
            | (romBank ? 0x02 : 0)
            | (internalCxROM ? 0x01 : 0)
    }

    mutating func writeStateRegister(_ value: UInt8) {
        alternateZeroPage = value & 0x80 != 0
        page2 = value & 0x40 != 0
        ramReadAuxiliary = value & 0x20 != 0
        ramWriteAuxiliary = value & 0x10 != 0
        languageCardReadROM = value & 0x08 != 0
        languageCardBank2 = value & 0x04 != 0
        romBank = value & 0x02 != 0
        internalCxROM = value & 0x01 != 0
    }

    mutating func setROMVersion(_ version: IIGSROMVersion) {
        switch version {
        case .rom01:
            speedRegister &= 0xBF
        case .rom03:
            speedRegister |= 0x40
        }
    }

    mutating func setBorderColor(_ value: UInt8, atCycle cycle: UInt64) {
        advanceVideoFrame(toCycle: cycle)
        borderColor = value & 0x0F
        let line = IIGSVideoTiming.position(atCycle: cycle).line
        activeBorderColors[line] = borderColor
        displayBorderColors[line] = borderColor
    }

    mutating func advanceVideoFrame(toCycle cycle: UInt64) {
        let frame = cycle / UInt64(IIGSVideoTiming.cyclesPerFrame)
        guard frame != activeBorderFrame else {
            return
        }

        if frame == activeBorderFrame + 1 {
            displayBorderColors = activeBorderColors
        } else {
            displayBorderColors = Array(repeating: borderColor, count: IIGSVideoTiming.scanlinesPerFrame)
        }
        activeBorderColors = Array(repeating: borderColor, count: IIGSVideoTiming.scanlinesPerFrame)
        activeBorderFrame = frame
    }

    mutating func accessLanguageCardSwitch(_ lowAddress: UInt16) {
        let offset = lowAddress & 0x000F
        languageCardBank2 = offset < 0x0008

        switch offset & 0x0003 {
        case 0x0000:
            languageCardReadROM = false
            languageCardWriteEnabled = false
            languageCardPrewriteArmed = false
        case 0x0001:
            languageCardReadROM = true
            armOrEnableLanguageCardWrite()
        case 0x0002:
            languageCardReadROM = true
            languageCardWriteEnabled = false
            languageCardPrewriteArmed = false
        default:
            languageCardReadROM = false
            armOrEnableLanguageCardWrite()
        }
    }

    private mutating func armOrEnableLanguageCardWrite() {
        if languageCardPrewriteArmed {
            languageCardWriteEnabled = true
        } else {
            languageCardPrewriteArmed = true
            languageCardWriteEnabled = false
        }
    }
}
