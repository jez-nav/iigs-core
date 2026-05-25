public protocol IIGSBus: AnyObject {
    func read8(at address: UInt32) -> UInt8
    func write8(_ value: UInt8, at address: UInt32)
    func idle(cycles: Int)
    func interruptVectorAddress(_ address: UInt32) -> UInt32
}

public extension IIGSBus {
    func idle(cycles: Int) {}

    func interruptVectorAddress(_ address: UInt32) -> UInt32 {
        masked24(address)
    }
}

@inline(__always)
public func masked24(_ address: UInt32) -> UInt32 {
    address & 0x00FF_FFFF
}
