public struct IIGSInterruptState: Equatable, Sendable {
    public static let verticalBlankMask: UInt8 = 0x80
    public static let quarterSecondMask: UInt8 = 0x40

    public var enableRegister: UInt8 = 0
    public private(set) var videoStatusRegister: UInt8 = 0

    public init() {}

    public var verticalBlankPending: Bool {
        videoStatusRegister & Self.verticalBlankMask != 0
    }

    public var quarterSecondPending: Bool {
        videoStatusRegister & Self.quarterSecondMask != 0
    }

    public var irqAsserted: Bool {
        videoStatusRegister & enableRegister & (Self.verticalBlankMask | Self.quarterSecondMask) != 0
    }

    public mutating func setVerticalBlankPending() {
        videoStatusRegister |= Self.verticalBlankMask
    }

    public mutating func setQuarterSecondPending() {
        videoStatusRegister |= Self.quarterSecondMask
    }

    public mutating func clearVideoStatus(mask: UInt8) {
        videoStatusRegister &= ~mask
    }

    public mutating func clearAllVideoStatus() {
        videoStatusRegister = 0
    }
}
