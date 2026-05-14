public struct IIGSInterruptState: Equatable, Sendable {
    public static let verticalBlankMask: UInt8 = 0x80
    public static let quarterSecondMask: UInt8 = 0x40
    public static let c023AnyPendingMask: UInt8 = 0x80
    public static let c023ScanlinePendingMask: UInt8 = 0x40
    public static let c023OneSecondPendingMask: UInt8 = 0x20
    public static let c023ScanlineEnableMask: UInt8 = 0x04
    public static let c023OneSecondEnableMask: UInt8 = 0x02

    public var enableRegister: UInt8 = 0
    public var c023EnableRegister: UInt8 = 0
    public private(set) var videoStatusRegister: UInt8 = 0
    public private(set) var c023PendingRegister: UInt8 = 0

    public init() {}

    public var verticalBlankPending: Bool {
        videoStatusRegister & Self.verticalBlankMask != 0
    }

    public var quarterSecondPending: Bool {
        videoStatusRegister & Self.quarterSecondMask != 0
    }

    public var irqAsserted: Bool {
        let videoIRQ = videoStatusRegister & enableRegister & (Self.verticalBlankMask | Self.quarterSecondMask) != 0
        return videoIRQ || c023IRQAsserted
    }

    public var c023StatusRegister: UInt8 {
        var value = c023EnableRegister & (Self.c023ScanlineEnableMask | Self.c023OneSecondEnableMask)
        value |= c023PendingRegister & (Self.c023ScanlinePendingMask | Self.c023OneSecondPendingMask)
        if c023IRQAsserted {
            value |= Self.c023AnyPendingMask
        }
        return value
    }

    public var c023IRQAsserted: Bool {
        let scanlineEnabled = c023EnableRegister & Self.c023ScanlineEnableMask != 0
        let oneSecondEnabled = c023EnableRegister & Self.c023OneSecondEnableMask != 0
        let scanlinePending = c023PendingRegister & Self.c023ScanlinePendingMask != 0
        let oneSecondPending = c023PendingRegister & Self.c023OneSecondPendingMask != 0
        return scanlineEnabled && scanlinePending || oneSecondEnabled && oneSecondPending
    }

    public mutating func setVerticalBlankPending() {
        videoStatusRegister |= Self.verticalBlankMask
    }

    public mutating func setQuarterSecondPending() {
        videoStatusRegister |= Self.quarterSecondMask
    }

    public mutating func setScanlinePending() {
        c023PendingRegister |= Self.c023ScanlinePendingMask
    }

    public mutating func setOneSecondPending() {
        c023PendingRegister |= Self.c023OneSecondPendingMask
    }

    public mutating func clearVideoStatus(mask: UInt8) {
        videoStatusRegister &= ~mask
    }

    public mutating func clearAllVideoStatus() {
        videoStatusRegister = 0
    }

    public mutating func clearC023Status(mask: UInt8) {
        let clearMask = mask == 0 ? Self.c023ScanlinePendingMask | Self.c023OneSecondPendingMask : mask
        c023PendingRegister &= ~clearMask
    }
}
