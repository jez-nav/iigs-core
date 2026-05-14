public struct IIGSPaddleController: Equatable, Sendable {
    public static let paddleCount = 4

    private var triggerCycle: UInt64 = 0
    private var timeouts = Array(repeating: UInt64(0), count: paddleCount)

    public init() {}

    public mutating func setPosition(_ value: UInt8, paddle: UInt8) {
        guard let index = index(for: paddle) else {
            return
        }
        timeouts[index] = UInt64(value)
    }

    public mutating func trigger(at cycle: UInt64) {
        triggerCycle = cycle
    }

    public func read(paddle: UInt8, at cycle: UInt64) -> UInt8 {
        guard let index = index(for: paddle) else {
            return 0
        }
        return cycle &- triggerCycle < timeouts[index] ? 0x80 : 0x00
    }

    private func index(for paddle: UInt8) -> Int? {
        let index = Int(paddle)
        return (0..<Self.paddleCount).contains(index) ? index : nil
    }
}
