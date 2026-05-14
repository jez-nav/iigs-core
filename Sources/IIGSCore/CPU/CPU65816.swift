public enum CPUInterrupt: Sendable {
    case irq
    case nmi
    case abort
}

public final class CPU65816 {
    public private(set) var registers = CPURegisters()
    public private(set) var isStopped = false
    public private(set) var isWaiting = false

    private var irqPending = false
    private var nmiPending = false
    private var abortPending = false

    public init() {}

    public func reset(using bus: IIGSBus) {
        registers = CPURegisters()
        isStopped = false
        isWaiting = false
        irqPending = false
        nmiPending = false
        abortPending = false
        let low = UInt16(bus.read8(at: 0x00FFFC))
        let high = UInt16(bus.read8(at: 0x00FFFD)) << 8
        registers.programCounter = high | low
        enforceModeInvariants()
    }

    public func updateRegisters(_ update: (inout CPURegisters) -> Void) {
        update(&registers)
        enforceModeInvariants()
    }

    public func signal(_ interrupt: CPUInterrupt) {
        switch interrupt {
        case .irq:
            irqPending = true
        case .nmi:
            nmiPending = true
        case .abort:
            abortPending = true
        }

        if isWaiting {
            isWaiting = false
        }
    }

    @discardableResult
    public func step(using bus: IIGSBus) throws -> Int {
        guard !isStopped else {
            bus.idle(cycles: 1)
            return 1
        }

        if isWaiting {
            bus.idle(cycles: 1)
            return 1
        }

        if abortPending {
            abortPending = false
            return enterInterrupt(.abort, using: bus)
        }

        if nmiPending {
            nmiPending = false
            return enterInterrupt(.nmi, using: bus)
        }

        if irqPending && !registers.status.contains(.interruptDisable) {
            irqPending = false
            return enterInterrupt(.irq, using: bus)
        }

        let opcodeAddress = currentProgramAddress
        let opcode = fetch8(using: bus)

        switch opcode {
        case 0x00: return brk(using: bus)
        case 0x01: return accumulatorReadModify(.ora, mode: .directIndexedIndirectX, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x02: return cop(using: bus)
        case 0x03: return accumulatorReadModify(.ora, mode: .stackRelative, using: bus, cycles: 4)
        case 0x04: return testAndSetReset(mode: .direct, setBits: true, using: bus, cycles: directPageBaseCycleCount(5))
        case 0x05: return accumulatorReadModify(.ora, mode: .direct, using: bus, cycles: directPageBaseCycleCount(3))
        case 0x06: return memoryShiftRotate(.asl, mode: .direct, using: bus, cycles: directPageBaseCycleCount(5))
        case 0x07: return accumulatorReadModify(.ora, mode: .directIndirectLong, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x08: push8(registers.status.rawValue, using: bus); return 3
        case 0x09: accumulatorImmediate(.ora, using: bus); return registers.accumulatorIs8Bit ? 2 : 3
        case 0x0A: shiftRotateAccumulator(.asl); return 2
        case 0x0B: push16(registers.directPage, using: bus); return 4
        case 0x0C: return testAndSetReset(mode: .absolute, setBits: true, using: bus, cycles: 6)
        case 0x0D: return accumulatorReadModify(.ora, mode: .absolute, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0x0E: return memoryShiftRotate(.asl, mode: .absolute, using: bus, cycles: 6)
        case 0x0F: return accumulatorReadModify(.ora, mode: .absoluteLong, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)

        case 0x10: return branch(!registers.status.contains(.negative), using: bus)
        case 0x11: return accumulatorReadModify(.ora, mode: .directIndirectIndexedY, using: bus, cycles: directPageBaseCycleCount(5))
        case 0x12: return accumulatorReadModify(.ora, mode: .directIndirect, using: bus, cycles: directPageBaseCycleCount(5))
        case 0x13: return accumulatorReadModify(.ora, mode: .stackRelativeIndirectIndexedY, using: bus, cycles: 7)
        case 0x14: return testAndSetReset(mode: .direct, setBits: false, using: bus, cycles: directPageBaseCycleCount(5))
        case 0x15: return accumulatorReadModify(.ora, mode: .directIndexedX, using: bus, cycles: directPageBaseCycleCount(4))
        case 0x16: return memoryShiftRotate(.asl, mode: .directIndexedX, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x17: return accumulatorReadModify(.ora, mode: .directIndirectLongIndexedY, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x18: registers.status.remove(.carry); return 2
        case 0x19: return accumulatorReadModify(.ora, mode: .absoluteIndexedY, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0x1A: incrementAccumulator(); return 2
        case 0x1B: return tcs()
        case 0x1C: return testAndSetReset(mode: .absolute, setBits: false, using: bus, cycles: 6)
        case 0x1D: return accumulatorReadModify(.ora, mode: .absoluteIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0x1E: return memoryShiftRotate(.asl, mode: .absoluteIndexedX, using: bus, cycles: 7)
        case 0x1F: return accumulatorReadModify(.ora, mode: .absoluteLongIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)

        case 0x20: return jsrAbsolute(using: bus)
        case 0x21: return accumulatorReadModify(.and, mode: .directIndexedIndirectX, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x22: return jsl(using: bus)
        case 0x23: return accumulatorReadModify(.and, mode: .stackRelative, using: bus, cycles: 4)
        case 0x24: return bit(mode: .direct, using: bus, cycles: directPageBaseCycleCount(3))
        case 0x25: return accumulatorReadModify(.and, mode: .direct, using: bus, cycles: directPageBaseCycleCount(3))
        case 0x26: return memoryShiftRotate(.rol, mode: .direct, using: bus, cycles: directPageBaseCycleCount(5))
        case 0x27: return accumulatorReadModify(.and, mode: .directIndirectLong, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x28: registers.status = ProcessorStatus(rawValue: pull8(using: bus)); enforceModeInvariants(); return 4
        case 0x29: accumulatorImmediate(.and, using: bus); return registers.accumulatorIs8Bit ? 2 : 3
        case 0x2A: shiftRotateAccumulator(.rol); return 2
        case 0x2B: registers.directPage = pull16(using: bus); updateZeroNegative(registers.directPage, width: .word); return 5
        case 0x2C: return bit(mode: .absolute, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0x2D: return accumulatorReadModify(.and, mode: .absolute, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0x2E: return memoryShiftRotate(.rol, mode: .absolute, using: bus, cycles: 6)
        case 0x2F: return accumulatorReadModify(.and, mode: .absoluteLong, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)

        case 0x30: return branch(registers.status.contains(.negative), using: bus)
        case 0x31: return accumulatorReadModify(.and, mode: .directIndirectIndexedY, using: bus, cycles: directPageBaseCycleCount(5))
        case 0x32: return accumulatorReadModify(.and, mode: .directIndirect, using: bus, cycles: directPageBaseCycleCount(5))
        case 0x33: return accumulatorReadModify(.and, mode: .stackRelativeIndirectIndexedY, using: bus, cycles: 7)
        case 0x34: return bit(mode: .directIndexedX, using: bus, cycles: directPageBaseCycleCount(4))
        case 0x35: return accumulatorReadModify(.and, mode: .directIndexedX, using: bus, cycles: directPageBaseCycleCount(4))
        case 0x36: return memoryShiftRotate(.rol, mode: .directIndexedX, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x37: return accumulatorReadModify(.and, mode: .directIndirectLongIndexedY, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x38: registers.status.insert(.carry); return 2
        case 0x39: return accumulatorReadModify(.and, mode: .absoluteIndexedY, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0x3A: registers.accumulator = accumulatorResult(registers.accumulator &- 1); updateZeroNegativeAccumulator(); return 2
        case 0x3B: return tsc()
        case 0x3C: return bit(mode: .absoluteIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0x3D: return accumulatorReadModify(.and, mode: .absoluteIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0x3E: return memoryShiftRotate(.rol, mode: .absoluteIndexedX, using: bus, cycles: 7)
        case 0x3F: return accumulatorReadModify(.and, mode: .absoluteLongIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)

        case 0x40: return rti(using: bus)
        case 0x41: return accumulatorReadModify(.eor, mode: .directIndexedIndirectX, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x42: _ = fetch8(using: bus); return 2
        case 0x43: return accumulatorReadModify(.eor, mode: .stackRelative, using: bus, cycles: 4)
        case 0x44: return blockMove(increment: false, using: bus)
        case 0x45: return accumulatorReadModify(.eor, mode: .direct, using: bus, cycles: directPageBaseCycleCount(3))
        case 0x46: return memoryShiftRotate(.lsr, mode: .direct, using: bus, cycles: directPageBaseCycleCount(5))
        case 0x47: return accumulatorReadModify(.eor, mode: .directIndirectLong, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x48: pushAccumulator(using: bus); return registers.accumulatorIs8Bit ? 3 : 4
        case 0x49: accumulatorImmediate(.eor, using: bus); return registers.accumulatorIs8Bit ? 2 : 3
        case 0x4A: shiftRotateAccumulator(.lsr); return 2
        case 0x4B: push8(registers.programBank, using: bus); return 3
        case 0x4C: registers.programCounter = fetch16(using: bus); return 3
        case 0x4D: return accumulatorReadModify(.eor, mode: .absolute, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0x4E: return memoryShiftRotate(.lsr, mode: .absolute, using: bus, cycles: 6)
        case 0x4F: return accumulatorReadModify(.eor, mode: .absoluteLong, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)

        case 0x50: return branch(!registers.status.contains(.overflow), using: bus)
        case 0x51: return accumulatorReadModify(.eor, mode: .directIndirectIndexedY, using: bus, cycles: directPageBaseCycleCount(5))
        case 0x52: return accumulatorReadModify(.eor, mode: .directIndirect, using: bus, cycles: directPageBaseCycleCount(5))
        case 0x53: return accumulatorReadModify(.eor, mode: .stackRelativeIndirectIndexedY, using: bus, cycles: 7)
        case 0x54: return blockMove(increment: true, using: bus)
        case 0x55: return accumulatorReadModify(.eor, mode: .directIndexedX, using: bus, cycles: directPageBaseCycleCount(4))
        case 0x56: return memoryShiftRotate(.lsr, mode: .directIndexedX, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x57: return accumulatorReadModify(.eor, mode: .directIndirectLongIndexedY, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x58: registers.status.remove(.interruptDisable); return 2
        case 0x59: return accumulatorReadModify(.eor, mode: .absoluteIndexedY, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0x5A: pushIndex(registers.y, using: bus); return registers.indexRegistersAre8Bit ? 3 : 4
        case 0x5B: return tcd()
        case 0x5C: return jmlAbsoluteLong(using: bus)
        case 0x5D: return accumulatorReadModify(.eor, mode: .absoluteIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0x5E: return memoryShiftRotate(.lsr, mode: .absoluteIndexedX, using: bus, cycles: 7)
        case 0x5F: return accumulatorReadModify(.eor, mode: .absoluteLongIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)

        case 0x60: registers.programCounter = pull16(using: bus) &+ 1; return 6
        case 0x61: return accumulatorReadModify(.adc, mode: .directIndexedIndirectX, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x62: return per(using: bus)
        case 0x63: return accumulatorReadModify(.adc, mode: .stackRelative, using: bus, cycles: 4)
        case 0x64: return storeZero(mode: .direct, using: bus, cycles: directPageBaseCycleCount(3))
        case 0x65: return accumulatorReadModify(.adc, mode: .direct, using: bus, cycles: directPageBaseCycleCount(3))
        case 0x66: return memoryShiftRotate(.ror, mode: .direct, using: bus, cycles: directPageBaseCycleCount(5))
        case 0x67: return accumulatorReadModify(.adc, mode: .directIndirectLong, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x68: pullAccumulator(using: bus); return registers.accumulatorIs8Bit ? 4 : 5
        case 0x69: accumulatorImmediate(.adc, using: bus); return registers.accumulatorIs8Bit ? 2 : 3
        case 0x6A: shiftRotateAccumulator(.ror); return 2
        case 0x6B: return rtl(using: bus)
        case 0x6C: registers.programCounter = read16(at: UInt32(fetch16(using: bus)), using: bus); return 5
        case 0x6D: return accumulatorReadModify(.adc, mode: .absolute, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0x6E: return memoryShiftRotate(.ror, mode: .absolute, using: bus, cycles: 6)
        case 0x6F: return accumulatorReadModify(.adc, mode: .absoluteLong, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)

        case 0x70: return branch(registers.status.contains(.overflow), using: bus)
        case 0x71: return accumulatorReadModify(.adc, mode: .directIndirectIndexedY, using: bus, cycles: directPageBaseCycleCount(5))
        case 0x72: return accumulatorReadModify(.adc, mode: .directIndirect, using: bus, cycles: directPageBaseCycleCount(5))
        case 0x73: return accumulatorReadModify(.adc, mode: .stackRelativeIndirectIndexedY, using: bus, cycles: 7)
        case 0x74: return storeZero(mode: .directIndexedX, using: bus, cycles: directPageBaseCycleCount(4))
        case 0x75: return accumulatorReadModify(.adc, mode: .directIndexedX, using: bus, cycles: directPageBaseCycleCount(4))
        case 0x76: return memoryShiftRotate(.ror, mode: .directIndexedX, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x77: return accumulatorReadModify(.adc, mode: .directIndirectLongIndexedY, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x78: registers.status.insert(.interruptDisable); return 2
        case 0x79: return accumulatorReadModify(.adc, mode: .absoluteIndexedY, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0x7A: pullIndex(into: \.y, using: bus); return registers.indexRegistersAre8Bit ? 4 : 5
        case 0x7B: return tdc()
        case 0x7C:
            let base = fetch16(using: bus)
            let pointer = UInt16(base &+ registers.x)
            registers.programCounter = read16(at: UInt32(pointer), using: bus)
            return 6
        case 0x7D: return accumulatorReadModify(.adc, mode: .absoluteIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0x7E: return memoryShiftRotate(.ror, mode: .absoluteIndexedX, using: bus, cycles: 7)
        case 0x7F: return accumulatorReadModify(.adc, mode: .absoluteLongIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)

        case 0x80: return branch(true, using: bus)
        case 0x81: return storeAccumulator(mode: .directIndexedIndirectX, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x82: return branchLong(using: bus)
        case 0x83: return storeAccumulator(mode: .stackRelative, using: bus, cycles: 4)
        case 0x84: return storeIndex(registers.y, mode: .direct, using: bus, cycles: directPageBaseCycleCount(3))
        case 0x85: return storeAccumulator(mode: .direct, using: bus, cycles: directPageBaseCycleCount(3))
        case 0x86: return storeIndex(registers.x, mode: .direct, using: bus, cycles: directPageBaseCycleCount(3))
        case 0x87: return storeAccumulator(mode: .directIndirectLong, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x88: decrementIndex(\.y); return 2
        case 0x89: bitImmediate(using: bus); return registers.accumulatorIs8Bit ? 2 : 3
        case 0x8A: transferIndex(registers.x, toAccumulator: true); return 2
        case 0x8B: return phb(using: bus)
        case 0x8C: return storeIndex(registers.y, mode: .absolute, using: bus, cycles: registers.indexRegistersAre8Bit ? 4 : 5)
        case 0x8D: return storeAccumulator(mode: .absolute, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0x8E: return storeIndex(registers.x, mode: .absolute, using: bus, cycles: registers.indexRegistersAre8Bit ? 4 : 5)
        case 0x8F: return storeAccumulator(mode: .absoluteLong, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)

        case 0x90: return branch(!registers.status.contains(.carry), using: bus)
        case 0x91: return storeAccumulator(mode: .directIndirectIndexedY, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x92: return storeAccumulator(mode: .directIndirect, using: bus, cycles: directPageBaseCycleCount(5))
        case 0x93: return storeAccumulator(mode: .stackRelativeIndirectIndexedY, using: bus, cycles: 7)
        case 0x94: return storeIndex(registers.y, mode: .directIndexedX, using: bus, cycles: directPageBaseCycleCount(4))
        case 0x95: return storeAccumulator(mode: .directIndexedX, using: bus, cycles: directPageBaseCycleCount(4))
        case 0x96: return storeIndex(registers.x, mode: .directIndexedY, using: bus, cycles: directPageBaseCycleCount(4))
        case 0x97: return storeAccumulator(mode: .directIndirectLongIndexedY, using: bus, cycles: directPageBaseCycleCount(6))
        case 0x98: transferIndex(registers.y, toAccumulator: true); return 2
        case 0x99: return storeAccumulator(mode: .absoluteIndexedY, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)
        case 0x9A: registers.stackPointer = registers.x; enforceModeInvariants(); return 2
        case 0x9B: return txy()
        case 0x9C: return storeZero(mode: .absolute, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0x9D: return storeAccumulator(mode: .absoluteIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)
        case 0x9E: return storeZero(mode: .absoluteIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)
        case 0x9F: return storeAccumulator(mode: .absoluteLongIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)

        case 0xA0: loadImmediateIndex(into: \.y, using: bus); return registers.indexRegistersAre8Bit ? 2 : 3
        case 0xA1: return loadAccumulator(mode: .directIndexedIndirectX, using: bus, cycles: directPageBaseCycleCount(6))
        case 0xA2: loadImmediateIndex(into: \.x, using: bus); return registers.indexRegistersAre8Bit ? 2 : 3
        case 0xA3: return loadAccumulator(mode: .stackRelative, using: bus, cycles: 4)
        case 0xA4: return loadIndex(into: \.y, mode: .direct, using: bus, cycles: directPageBaseCycleCount(3))
        case 0xA5: return loadAccumulator(mode: .direct, using: bus, cycles: directPageBaseCycleCount(3))
        case 0xA6: return loadIndex(into: \.x, mode: .direct, using: bus, cycles: directPageBaseCycleCount(3))
        case 0xA7: return loadAccumulator(mode: .directIndirectLong, using: bus, cycles: directPageBaseCycleCount(6))
        case 0xA8: transferAccumulator(to: \.y); return 2
        case 0xA9: loadImmediateAccumulator(using: bus); return registers.accumulatorIs8Bit ? 2 : 3
        case 0xAA: transferAccumulator(to: \.x); return 2
        case 0xAB: return plb(using: bus)
        case 0xAC: return loadIndex(into: \.y, mode: .absolute, using: bus, cycles: registers.indexRegistersAre8Bit ? 4 : 5)
        case 0xAD: return loadAccumulator(mode: .absolute, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0xAE: return loadIndex(into: \.x, mode: .absolute, using: bus, cycles: registers.indexRegistersAre8Bit ? 4 : 5)
        case 0xAF: return loadAccumulator(mode: .absoluteLong, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)

        case 0xB0: return branch(registers.status.contains(.carry), using: bus)
        case 0xB1: return loadAccumulator(mode: .directIndirectIndexedY, using: bus, cycles: directPageBaseCycleCount(5))
        case 0xB2: return loadAccumulator(mode: .directIndirect, using: bus, cycles: directPageBaseCycleCount(5))
        case 0xB3: return loadAccumulator(mode: .stackRelativeIndirectIndexedY, using: bus, cycles: 7)
        case 0xB4: return loadIndex(into: \.y, mode: .directIndexedX, using: bus, cycles: directPageBaseCycleCount(4))
        case 0xB5: return loadAccumulator(mode: .directIndexedX, using: bus, cycles: directPageBaseCycleCount(4))
        case 0xB6: return loadIndex(into: \.x, mode: .directIndexedY, using: bus, cycles: directPageBaseCycleCount(4))
        case 0xB7: return loadAccumulator(mode: .directIndirectLongIndexedY, using: bus, cycles: directPageBaseCycleCount(6))
        case 0xB8: registers.status.remove(.overflow); return 2
        case 0xB9: return loadAccumulator(mode: .absoluteIndexedY, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0xBA: registers.x = registers.stackPointer; enforceModeInvariants(); updateZeroNegativeIndex(registers.x); return 2
        case 0xBB: return tyx()
        case 0xBC: return loadIndex(into: \.y, mode: .absoluteIndexedX, using: bus, cycles: registers.indexRegistersAre8Bit ? 4 : 5)
        case 0xBD: return loadAccumulator(mode: .absoluteIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0xBE: return loadIndex(into: \.x, mode: .absoluteIndexedY, using: bus, cycles: registers.indexRegistersAre8Bit ? 4 : 5)
        case 0xBF: return loadAccumulator(mode: .absoluteLongIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)

        case 0xC0: compareImmediate(registers.y, width: indexWidth, using: bus); return registers.indexRegistersAre8Bit ? 2 : 3
        case 0xC1: return compareAccumulator(mode: .directIndexedIndirectX, using: bus, cycles: directPageBaseCycleCount(6))
        case 0xC2: let mask = ProcessorStatus(rawValue: fetch8(using: bus)); registers.status.subtract(mask); enforceModeInvariants(); return 3
        case 0xC3: return compareAccumulator(mode: .stackRelative, using: bus, cycles: 4)
        case 0xC4: return compareIndex(registers.y, mode: .direct, using: bus, cycles: directPageBaseCycleCount(3))
        case 0xC5: return compareAccumulator(mode: .direct, using: bus, cycles: directPageBaseCycleCount(3))
        case 0xC6: return memoryIncrementDecrement(mode: .direct, increment: false, using: bus, cycles: directPageBaseCycleCount(5))
        case 0xC7: return compareAccumulator(mode: .directIndirectLong, using: bus, cycles: directPageBaseCycleCount(6))
        case 0xC8: incrementIndex(\.y); return 2
        case 0xC9: compareImmediate(registers.accumulator, width: accumulatorWidth, using: bus); return registers.accumulatorIs8Bit ? 2 : 3
        case 0xCA: decrementIndex(\.x); return 2
        case 0xCB: isWaiting = true; return 3
        case 0xCC: return compareIndex(registers.y, mode: .absolute, using: bus, cycles: registers.indexRegistersAre8Bit ? 4 : 5)
        case 0xCD: return compareAccumulator(mode: .absolute, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0xCE: return memoryIncrementDecrement(mode: .absolute, increment: false, using: bus, cycles: 6)
        case 0xCF: return compareAccumulator(mode: .absoluteLong, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)

        case 0xD0: return branch(!registers.status.contains(.zero), using: bus)
        case 0xD1: return compareAccumulator(mode: .directIndirectIndexedY, using: bus, cycles: directPageBaseCycleCount(5))
        case 0xD2: return compareAccumulator(mode: .directIndirect, using: bus, cycles: directPageBaseCycleCount(5))
        case 0xD3: return compareAccumulator(mode: .stackRelativeIndirectIndexedY, using: bus, cycles: 7)
        case 0xD4: return pei(using: bus)
        case 0xD5: return compareAccumulator(mode: .directIndexedX, using: bus, cycles: directPageBaseCycleCount(4))
        case 0xD6: return memoryIncrementDecrement(mode: .directIndexedX, increment: false, using: bus, cycles: directPageBaseCycleCount(6))
        case 0xD7: return compareAccumulator(mode: .directIndirectLongIndexedY, using: bus, cycles: directPageBaseCycleCount(6))
        case 0xD8: registers.status.remove(.decimal); return 2
        case 0xD9: return compareAccumulator(mode: .absoluteIndexedY, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0xDA: pushIndex(registers.x, using: bus); return registers.indexRegistersAre8Bit ? 3 : 4
        case 0xDB: isStopped = true; return 3
        case 0xDC: return jmlAbsoluteIndirectLong(using: bus)
        case 0xDD: return compareAccumulator(mode: .absoluteIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0xDE: return memoryIncrementDecrement(mode: .absoluteIndexedX, increment: false, using: bus, cycles: 7)
        case 0xDF: return compareAccumulator(mode: .absoluteLongIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)

        case 0xE0: compareImmediate(registers.x, width: indexWidth, using: bus); return registers.indexRegistersAre8Bit ? 2 : 3
        case 0xE1: return accumulatorReadModify(.sbc, mode: .directIndexedIndirectX, using: bus, cycles: directPageBaseCycleCount(6))
        case 0xE2: let mask = ProcessorStatus(rawValue: fetch8(using: bus)); registers.status.formUnion(mask); enforceModeInvariants(); return 3
        case 0xE3: return accumulatorReadModify(.sbc, mode: .stackRelative, using: bus, cycles: 4)
        case 0xE4: return compareIndex(registers.x, mode: .direct, using: bus, cycles: directPageBaseCycleCount(3))
        case 0xE5: return accumulatorReadModify(.sbc, mode: .direct, using: bus, cycles: directPageBaseCycleCount(3))
        case 0xE6: return memoryIncrementDecrement(mode: .direct, increment: true, using: bus, cycles: directPageBaseCycleCount(5))
        case 0xE7: return accumulatorReadModify(.sbc, mode: .directIndirectLong, using: bus, cycles: directPageBaseCycleCount(6))
        case 0xE8: incrementIndex(\.x); return 2
        case 0xE9: accumulatorImmediate(.sbc, using: bus); return registers.accumulatorIs8Bit ? 2 : 3
        case 0xEA: return 2
        case 0xEB: return xba()
        case 0xEC: return compareIndex(registers.x, mode: .absolute, using: bus, cycles: registers.indexRegistersAre8Bit ? 4 : 5)
        case 0xED: return accumulatorReadModify(.sbc, mode: .absolute, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0xEE: return memoryIncrementDecrement(mode: .absolute, increment: true, using: bus, cycles: 6)
        case 0xEF: return accumulatorReadModify(.sbc, mode: .absoluteLong, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)

        case 0xF0: return branch(registers.status.contains(.zero), using: bus)
        case 0xF1: return accumulatorReadModify(.sbc, mode: .directIndirectIndexedY, using: bus, cycles: directPageBaseCycleCount(5))
        case 0xF2: return accumulatorReadModify(.sbc, mode: .directIndirect, using: bus, cycles: directPageBaseCycleCount(5))
        case 0xF3: return accumulatorReadModify(.sbc, mode: .stackRelativeIndirectIndexedY, using: bus, cycles: 7)
        case 0xF4: return pea(using: bus)
        case 0xF5: return accumulatorReadModify(.sbc, mode: .directIndexedX, using: bus, cycles: directPageBaseCycleCount(4))
        case 0xF6: return memoryIncrementDecrement(mode: .directIndexedX, increment: true, using: bus, cycles: directPageBaseCycleCount(6))
        case 0xF7: return accumulatorReadModify(.sbc, mode: .directIndirectLongIndexedY, using: bus, cycles: directPageBaseCycleCount(6))
        case 0xF8: registers.status.insert(.decimal); return 2
        case 0xF9: return accumulatorReadModify(.sbc, mode: .absoluteIndexedY, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0xFA: pullIndex(into: \.x, using: bus); return registers.indexRegistersAre8Bit ? 4 : 5
        case 0xFB: exchangeCarryAndEmulation(); return 2
        case 0xFC: return jsrAbsoluteIndexedIndirect(using: bus)
        case 0xFD: return accumulatorReadModify(.sbc, mode: .absoluteIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 4 : 5)
        case 0xFE: return memoryIncrementDecrement(mode: .absoluteIndexedX, increment: true, using: bus, cycles: 7)
        case 0xFF: return accumulatorReadModify(.sbc, mode: .absoluteLongIndexedX, using: bus, cycles: registers.accumulatorIs8Bit ? 5 : 6)

        default:
            throw CPUError.unsupportedOpcode(opcode, address: opcodeAddress)
        }
    }
}

private extension CPU65816 {
    enum RegisterWidth: Equatable {
        case byte
        case word

        var mask: UInt16 {
            switch self {
            case .byte: return 0x00FF
            case .word: return 0xFFFF
            }
        }

        var signBit: UInt16 {
            switch self {
            case .byte: return 0x0080
            case .word: return 0x8000
            }
        }

        var bitCount: Int {
            switch self {
            case .byte: return 8
            case .word: return 16
            }
        }
    }

    enum AddressingMode {
        case direct
        case directIndexedX
        case directIndexedY
        case directIndirect
        case directIndexedIndirectX
        case directIndirectIndexedY
        case directIndirectLong
        case directIndirectLongIndexedY
        case absolute
        case absoluteIndexedX
        case absoluteIndexedY
        case absoluteLong
        case absoluteLongIndexedX
        case stackRelative
        case stackRelativeIndirectIndexedY
    }

    enum AccumulatorOperation {
        case ora
        case and
        case eor
        case adc
        case sbc
    }

    enum ShiftRotateOperation {
        case asl
        case lsr
        case rol
        case ror
    }

    var currentProgramAddress: UInt32 {
        (UInt32(registers.programBank) << 16) | UInt32(registers.programCounter)
    }

    var accumulatorWidth: RegisterWidth {
        registers.accumulatorIs8Bit ? .byte : .word
    }

    var indexWidth: RegisterWidth {
        registers.indexRegistersAre8Bit ? .byte : .word
    }

    func fetch8(using bus: IIGSBus) -> UInt8 {
        let value = bus.read8(at: currentProgramAddress)
        registers.programCounter &+= 1
        return value
    }

    func fetch16(using bus: IIGSBus) -> UInt16 {
        let low = UInt16(fetch8(using: bus))
        let high = UInt16(fetch8(using: bus)) << 8
        return high | low
    }

    func fetch24(using bus: IIGSBus) -> UInt32 {
        let low = UInt32(fetch8(using: bus))
        let middle = UInt32(fetch8(using: bus)) << 8
        let high = UInt32(fetch8(using: bus)) << 16
        return high | middle | low
    }

    func read16(at address: UInt32, using bus: IIGSBus) -> UInt16 {
        let low = UInt16(bus.read8(at: address))
        let high = UInt16(bus.read8(at: masked24(address &+ 1))) << 8
        return high | low
    }

    func read16Bank0(at address: UInt16, using bus: IIGSBus) -> UInt16 {
        let low = UInt16(bus.read8(at: UInt32(address)))
        let high = UInt16(bus.read8(at: UInt32(address &+ 1))) << 8
        return high | low
    }

    func read24Bank0(at address: UInt16, using bus: IIGSBus) -> UInt32 {
        let low = UInt32(bus.read8(at: UInt32(address)))
        let middle = UInt32(bus.read8(at: UInt32(address &+ 1))) << 8
        let high = UInt32(bus.read8(at: UInt32(address &+ 2))) << 16
        return high | middle | low
    }

    func readValue(at address: UInt32, width: RegisterWidth, using bus: IIGSBus) -> UInt16 {
        switch width {
        case .byte:
            return UInt16(bus.read8(at: address))
        case .word:
            return read16(at: address, using: bus)
        }
    }

    func writeValue(_ value: UInt16, at address: UInt32, width: RegisterWidth, using bus: IIGSBus) {
        bus.write8(UInt8(truncatingIfNeeded: value), at: address)
        if width == .word {
            bus.write8(UInt8(truncatingIfNeeded: value >> 8), at: masked24(address &+ 1))
        }
    }

    func absoluteDataAddress(_ offset: UInt16) -> UInt32 {
        (UInt32(registers.dataBank) << 16) | UInt32(offset)
    }

    func directAddress(_ offset: UInt8) -> UInt16 {
        UInt16(registers.directPage &+ UInt16(offset))
    }

    func directIndexedAddress(_ offset: UInt8, index: UInt16) -> UInt16 {
        if registers.emulationMode && registers.directPage & 0x00FF == 0 {
            return registers.directPage &+ UInt16(UInt8(truncatingIfNeeded: UInt16(offset) &+ index))
        }
        return registers.directPage &+ UInt16(offset) &+ index
    }

    func directPageBaseCycleCount(_ base: Int) -> Int {
        if registers.directPage & 0x00FF == 0 {
            return base
        }
        return base + 1
    }

    func operandAddress(_ mode: AddressingMode, using bus: IIGSBus) -> UInt32 {
        switch mode {
        case .direct:
            return UInt32(directAddress(fetch8(using: bus)))
        case .directIndexedX:
            return UInt32(directIndexedAddress(fetch8(using: bus), index: registers.x))
        case .directIndexedY:
            return UInt32(directIndexedAddress(fetch8(using: bus), index: registers.y))
        case .directIndirect:
            let pointer = directAddress(fetch8(using: bus))
            return absoluteDataAddress(read16Bank0(at: pointer, using: bus))
        case .directIndexedIndirectX:
            let offset = UInt8(truncatingIfNeeded: UInt16(fetch8(using: bus)) &+ registers.x)
            let pointer = directAddress(offset)
            return absoluteDataAddress(read16Bank0(at: pointer, using: bus))
        case .directIndirectIndexedY:
            let pointer = directAddress(fetch8(using: bus))
            let base = read16Bank0(at: pointer, using: bus)
            return absoluteDataAddress(base &+ registers.y)
        case .directIndirectLong:
            let pointer = directAddress(fetch8(using: bus))
            return read24Bank0(at: pointer, using: bus)
        case .directIndirectLongIndexedY:
            let pointer = directAddress(fetch8(using: bus))
            return masked24(read24Bank0(at: pointer, using: bus) &+ UInt32(registers.y))
        case .absolute:
            return absoluteDataAddress(fetch16(using: bus))
        case .absoluteIndexedX:
            return absoluteDataAddress(fetch16(using: bus) &+ registers.x)
        case .absoluteIndexedY:
            return absoluteDataAddress(fetch16(using: bus) &+ registers.y)
        case .absoluteLong:
            return fetch24(using: bus)
        case .absoluteLongIndexedX:
            return masked24(fetch24(using: bus) &+ UInt32(registers.x))
        case .stackRelative:
            let offset = UInt16(fetch8(using: bus))
            return UInt32(registers.stackPointer &+ offset)
        case .stackRelativeIndirectIndexedY:
            let offset = UInt16(fetch8(using: bus))
            let pointer = registers.stackPointer &+ offset
            let base = read16Bank0(at: pointer, using: bus)
            return absoluteDataAddress(base &+ registers.y)
        }
    }

    func loadImmediateAccumulator(using bus: IIGSBus) {
        switch accumulatorWidth {
        case .byte:
            setAccumulatorLow(UInt16(fetch8(using: bus)))
            updateZeroNegative(registers.accumulator & 0x00FF, width: .byte)
        case .word:
            registers.accumulator = fetch16(using: bus)
            updateZeroNegative(registers.accumulator, width: .word)
        }
    }

    func loadImmediateIndex(into keyPath: WritableKeyPath<CPURegisters, UInt16>, using bus: IIGSBus) {
        switch indexWidth {
        case .byte:
            let value = UInt16(fetch8(using: bus))
            registers[keyPath: keyPath] = value
            updateZeroNegative(value, width: .byte)
        case .word:
            let value = fetch16(using: bus)
            registers[keyPath: keyPath] = value
            updateZeroNegative(value, width: .word)
        }
    }

    func loadAccumulator(mode: AddressingMode, using bus: IIGSBus, cycles: Int) -> Int {
        let value = readValue(at: operandAddress(mode, using: bus), width: accumulatorWidth, using: bus)
        if registers.accumulatorIs8Bit {
            setAccumulatorLow(value)
        } else {
            registers.accumulator = value
        }
        updateZeroNegative(value, width: accumulatorWidth)
        return cycles
    }

    func loadIndex(into keyPath: WritableKeyPath<CPURegisters, UInt16>, mode: AddressingMode, using bus: IIGSBus, cycles: Int) -> Int {
        let value = readValue(at: operandAddress(mode, using: bus), width: indexWidth, using: bus)
        registers[keyPath: keyPath] = value
        updateZeroNegative(value, width: indexWidth)
        enforceModeInvariants()
        return cycles
    }

    func storeAccumulator(mode: AddressingMode, using bus: IIGSBus, cycles: Int) -> Int {
        writeValue(registers.accumulator, at: operandAddress(mode, using: bus), width: accumulatorWidth, using: bus)
        return cycles
    }

    func storeIndex(_ value: UInt16, mode: AddressingMode, using bus: IIGSBus, cycles: Int) -> Int {
        writeValue(value, at: operandAddress(mode, using: bus), width: indexWidth, using: bus)
        return cycles
    }

    func storeZero(mode: AddressingMode, using bus: IIGSBus, cycles: Int) -> Int {
        writeValue(0, at: operandAddress(mode, using: bus), width: accumulatorWidth, using: bus)
        return cycles
    }

    func accumulatorImmediate(_ operation: AccumulatorOperation, using bus: IIGSBus) {
        let value: UInt16 = accumulatorWidth == .byte ? UInt16(fetch8(using: bus)) : fetch16(using: bus)
        applyAccumulator(operation, value)
    }

    func accumulatorReadModify(_ operation: AccumulatorOperation, mode: AddressingMode, using bus: IIGSBus, cycles: Int) -> Int {
        let value = readValue(at: operandAddress(mode, using: bus), width: accumulatorWidth, using: bus)
        applyAccumulator(operation, value)
        return cycles
    }

    func applyAccumulator(_ operation: AccumulatorOperation, _ operand: UInt16) {
        switch operation {
        case .ora:
            registers.accumulator = accumulatorResult(registers.accumulator | operand)
            updateZeroNegativeAccumulator()
        case .and:
            registers.accumulator = accumulatorResult(registers.accumulator & operand)
            updateZeroNegativeAccumulator()
        case .eor:
            registers.accumulator = accumulatorResult(registers.accumulator ^ operand)
            updateZeroNegativeAccumulator()
        case .adc:
            addToAccumulator(operand)
        case .sbc:
            subtractFromAccumulator(operand)
        }
    }

    func accumulatorResult(_ value: UInt16) -> UInt16 {
        if registers.accumulatorIs8Bit {
            return (registers.accumulator & 0xFF00) | (value & 0x00FF)
        }
        return value
    }

    func setAccumulatorLow(_ value: UInt16) {
        registers.accumulator = (registers.accumulator & 0xFF00) | (value & 0x00FF)
    }

    func updateZeroNegativeAccumulator() {
        updateZeroNegative(registers.accumulator & accumulatorWidth.mask, width: accumulatorWidth)
    }

    func updateZeroNegativeIndex(_ value: UInt16) {
        updateZeroNegative(value & indexWidth.mask, width: indexWidth)
    }

    func addToAccumulator(_ operand: UInt16) {
        let width = accumulatorWidth
        let lhs = registers.accumulator & width.mask
        let rhs = operand & width.mask
        let carryIn: UInt32 = registers.status.contains(.carry) ? 1 : 0

        let result: UInt16
        let carryOut: Bool
        let binaryResult = UInt32(lhs) + UInt32(rhs) + carryIn

        if registers.status.contains(.decimal) {
            let bcd = decimalAdd(lhs, rhs, carryIn: carryIn, width: width)
            result = bcd.result
            carryOut = bcd.carry
        } else {
            result = UInt16(binaryResult) & width.mask
            carryOut = binaryResult > UInt32(width.mask)
        }

        let overflow = (~(lhs ^ rhs) & (lhs ^ UInt16(binaryResult)) & width.signBit) != 0
        setFlag(.carry, carryOut)
        setFlag(.overflow, overflow)
        registers.accumulator = accumulatorResult(result)
        updateZeroNegative(result, width: width)
    }

    func subtractFromAccumulator(_ operand: UInt16) {
        let width = accumulatorWidth
        let lhs = registers.accumulator & width.mask
        let rhs = operand & width.mask
        let borrow: UInt32 = registers.status.contains(.carry) ? 0 : 1
        let binaryResult = UInt32(lhs) &- UInt32(rhs) &- borrow

        let result: UInt16
        let carryOut: Bool

        if registers.status.contains(.decimal) {
            let bcd = decimalSubtract(lhs, rhs, borrow: borrow, width: width)
            result = bcd.result
            carryOut = bcd.carry
        } else {
            result = UInt16(binaryResult) & width.mask
            carryOut = UInt32(lhs) >= UInt32(rhs) + borrow
        }

        let overflow = ((lhs ^ rhs) & (lhs ^ UInt16(binaryResult)) & width.signBit) != 0
        setFlag(.carry, carryOut)
        setFlag(.overflow, overflow)
        registers.accumulator = accumulatorResult(result)
        updateZeroNegative(result, width: width)
    }

    func decimalAdd(_ lhs: UInt16, _ rhs: UInt16, carryIn: UInt32, width: RegisterWidth) -> (result: UInt16, carry: Bool) {
        var result: UInt16 = 0
        var carry = Int(carryIn)
        let digitCount = width == .byte ? 2 : 4
        for index in 0..<digitCount {
            let shift = UInt16(index * 4)
            var digit = Int((lhs >> shift) & 0xF) + Int((rhs >> shift) & 0xF) + carry
            if digit > 9 {
                digit -= 10
                carry = 1
            } else {
                carry = 0
            }
            result |= UInt16(digit & 0xF) << shift
        }
        return (result & width.mask, carry != 0)
    }

    func decimalSubtract(_ lhs: UInt16, _ rhs: UInt16, borrow: UInt32, width: RegisterWidth) -> (result: UInt16, carry: Bool) {
        var result: UInt16 = 0
        var borrowOut = Int(borrow)
        let digitCount = width == .byte ? 2 : 4
        for index in 0..<digitCount {
            let shift = UInt16(index * 4)
            var digit = Int((lhs >> shift) & 0xF) - Int((rhs >> shift) & 0xF) - borrowOut
            if digit < 0 {
                digit += 10
                borrowOut = 1
            } else {
                borrowOut = 0
            }
            result |= UInt16(digit & 0xF) << shift
        }
        return (result & width.mask, borrowOut == 0)
    }

    func bitImmediate(using bus: IIGSBus) {
        let value: UInt16 = accumulatorWidth == .byte ? UInt16(fetch8(using: bus)) : fetch16(using: bus)
        setFlag(.zero, (registers.accumulator & value & accumulatorWidth.mask) == 0)
    }

    func bit(mode: AddressingMode, using bus: IIGSBus, cycles: Int) -> Int {
        let value = readValue(at: operandAddress(mode, using: bus), width: accumulatorWidth, using: bus)
        setFlag(.zero, (registers.accumulator & value & accumulatorWidth.mask) == 0)
        setFlag(.negative, (value & accumulatorWidth.signBit) != 0)
        setFlag(.overflow, (value & (accumulatorWidth == .byte ? 0x40 : 0x4000)) != 0)
        return cycles
    }

    func testAndSetReset(mode: AddressingMode, setBits: Bool, using bus: IIGSBus, cycles: Int) -> Int {
        let address = operandAddress(mode, using: bus)
        let old = readValue(at: address, width: accumulatorWidth, using: bus)
        setFlag(.zero, (old & registers.accumulator & accumulatorWidth.mask) == 0)
        let newValue = setBits ? (old | registers.accumulator) : (old & ~registers.accumulator)
        writeValue(newValue, at: address, width: accumulatorWidth, using: bus)
        return cycles
    }

    func compareImmediate(_ registerValue: UInt16, width: RegisterWidth, using bus: IIGSBus) {
        let operand: UInt16 = width == .byte ? UInt16(fetch8(using: bus)) : fetch16(using: bus)
        compare(registerValue, operand, width: width)
    }

    func compareAccumulator(mode: AddressingMode, using bus: IIGSBus, cycles: Int) -> Int {
        let operand = readValue(at: operandAddress(mode, using: bus), width: accumulatorWidth, using: bus)
        compare(registers.accumulator, operand, width: accumulatorWidth)
        return cycles
    }

    func compareIndex(_ registerValue: UInt16, mode: AddressingMode, using bus: IIGSBus, cycles: Int) -> Int {
        let operand = readValue(at: operandAddress(mode, using: bus), width: indexWidth, using: bus)
        compare(registerValue, operand, width: indexWidth)
        return cycles
    }

    func compare(_ lhs: UInt16, _ rhs: UInt16, width: RegisterWidth) {
        let left = lhs & width.mask
        let right = rhs & width.mask
        let result = left &- right
        setFlag(.carry, left >= right)
        updateZeroNegative(result & width.mask, width: width)
    }

    func memoryShiftRotate(_ operation: ShiftRotateOperation, mode: AddressingMode, using bus: IIGSBus, cycles: Int) -> Int {
        let address = operandAddress(mode, using: bus)
        let value = readValue(at: address, width: accumulatorWidth, using: bus)
        let result = shiftRotate(value, operation: operation, width: accumulatorWidth)
        writeValue(result, at: address, width: accumulatorWidth, using: bus)
        return cycles
    }

    func shiftRotateAccumulator(_ operation: ShiftRotateOperation) {
        let result = shiftRotate(registers.accumulator, operation: operation, width: accumulatorWidth)
        registers.accumulator = accumulatorResult(result)
    }

    func shiftRotate(_ value: UInt16, operation: ShiftRotateOperation, width: RegisterWidth) -> UInt16 {
        let oldCarry = registers.status.contains(.carry)
        let masked = value & width.mask
        let result: UInt16
        switch operation {
        case .asl:
            setFlag(.carry, (masked & width.signBit) != 0)
            result = (masked << 1) & width.mask
        case .lsr:
            setFlag(.carry, (masked & 0x0001) != 0)
            result = masked >> 1
        case .rol:
            setFlag(.carry, (masked & width.signBit) != 0)
            result = ((masked << 1) | (oldCarry ? 1 : 0)) & width.mask
        case .ror:
            setFlag(.carry, (masked & 0x0001) != 0)
            result = (masked >> 1) | (oldCarry ? width.signBit : 0)
        }
        updateZeroNegative(result, width: width)
        return result
    }

    func memoryIncrementDecrement(mode: AddressingMode, increment: Bool, using bus: IIGSBus, cycles: Int) -> Int {
        let address = operandAddress(mode, using: bus)
        let old = readValue(at: address, width: accumulatorWidth, using: bus)
        let newValue = increment ? (old &+ 1) & accumulatorWidth.mask : (old &- 1) & accumulatorWidth.mask
        writeValue(newValue, at: address, width: accumulatorWidth, using: bus)
        updateZeroNegative(newValue, width: accumulatorWidth)
        return cycles
    }

    func incrementAccumulator() {
        registers.accumulator = accumulatorResult(registers.accumulator &+ 1)
        updateZeroNegativeAccumulator()
    }

    func incrementIndex(_ keyPath: WritableKeyPath<CPURegisters, UInt16>) {
        let value = (registers[keyPath: keyPath] &+ 1) & indexWidth.mask
        registers[keyPath: keyPath] = value
        updateZeroNegativeIndex(value)
    }

    func decrementIndex(_ keyPath: WritableKeyPath<CPURegisters, UInt16>) {
        let value = (registers[keyPath: keyPath] &- 1) & indexWidth.mask
        registers[keyPath: keyPath] = value
        updateZeroNegativeIndex(value)
    }

    func transferAccumulator(to keyPath: WritableKeyPath<CPURegisters, UInt16>) {
        let value = registers.accumulator & indexWidth.mask
        registers[keyPath: keyPath] = value
        updateZeroNegativeIndex(value)
    }

    func transferIndex(_ value: UInt16, toAccumulator: Bool) {
        if registers.accumulatorIs8Bit {
            let low = value & 0x00FF
            setAccumulatorLow(low)
            updateZeroNegative(low, width: .byte)
        } else {
            registers.accumulator = value
            updateZeroNegative(value, width: .word)
        }
    }

    func txy() -> Int {
        registers.y = registers.x & indexWidth.mask
        updateZeroNegativeIndex(registers.y)
        return 2
    }

    func tyx() -> Int {
        registers.x = registers.y & indexWidth.mask
        updateZeroNegativeIndex(registers.x)
        return 2
    }

    func tcd() -> Int {
        registers.directPage = registers.accumulator
        updateZeroNegative(registers.directPage, width: .word)
        return 2
    }

    func tdc() -> Int {
        registers.accumulator = registers.directPage
        updateZeroNegative(registers.accumulator, width: .word)
        return 2
    }

    func tcs() -> Int {
        registers.stackPointer = registers.accumulator
        enforceModeInvariants()
        return 2
    }

    func tsc() -> Int {
        registers.accumulator = registers.stackPointer
        updateZeroNegative(registers.accumulator, width: .word)
        return 2
    }

    func xba() -> Int {
        registers.accumulator = (registers.accumulator << 8) | (registers.accumulator >> 8)
        updateZeroNegative(registers.accumulator & 0x00FF, width: .byte)
        return 3
    }

    func branch(_ condition: Bool, using bus: IIGSBus) -> Int {
        let offset = Int8(bitPattern: fetch8(using: bus))
        guard condition else {
            return 2
        }
        registers.programCounter = UInt16(truncatingIfNeeded: Int32(registers.programCounter) + Int32(offset))
        return 3
    }

    func branchLong(using bus: IIGSBus) -> Int {
        let offset = Int16(bitPattern: fetch16(using: bus))
        registers.programCounter = UInt16(truncatingIfNeeded: Int32(registers.programCounter) + Int32(offset))
        return 4
    }

    func jsrAbsolute(using bus: IIGSBus) -> Int {
        let target = fetch16(using: bus)
        push16(registers.programCounter &- 1, using: bus)
        registers.programCounter = target
        return 6
    }

    func jsrAbsoluteIndexedIndirect(using bus: IIGSBus) -> Int {
        let base = fetch16(using: bus)
        let pointer = UInt16(base &+ registers.x)
        push16(registers.programCounter &- 1, using: bus)
        registers.programCounter = read16(at: UInt32(pointer), using: bus)
        return 8
    }

    func jsl(using bus: IIGSBus) -> Int {
        let target = fetch24(using: bus)
        push8(registers.programBank, using: bus)
        push16(registers.programCounter &- 1, using: bus)
        registers.programBank = UInt8(truncatingIfNeeded: target >> 16)
        registers.programCounter = UInt16(truncatingIfNeeded: target)
        return 8
    }

    func jmlAbsoluteLong(using bus: IIGSBus) -> Int {
        let target = fetch24(using: bus)
        registers.programBank = UInt8(truncatingIfNeeded: target >> 16)
        registers.programCounter = UInt16(truncatingIfNeeded: target)
        return 4
    }

    func jmlAbsoluteIndirectLong(using bus: IIGSBus) -> Int {
        let pointer = fetch16(using: bus)
        let target = read24Bank0(at: pointer, using: bus)
        registers.programBank = UInt8(truncatingIfNeeded: target >> 16)
        registers.programCounter = UInt16(truncatingIfNeeded: target)
        return 6
    }

    func rtl(using bus: IIGSBus) -> Int {
        let pc = pull16(using: bus) &+ 1
        registers.programBank = pull8(using: bus)
        registers.programCounter = pc
        return 6
    }

    func rti(using bus: IIGSBus) -> Int {
        registers.status = ProcessorStatus(rawValue: pull8(using: bus))
        registers.programCounter = pull16(using: bus)
        if !registers.emulationMode {
            registers.programBank = pull8(using: bus)
        }
        enforceModeInvariants()
        return registers.emulationMode ? 6 : 7
    }

    func brk(using bus: IIGSBus) -> Int {
        _ = fetch8(using: bus)
        if registers.emulationMode {
            push16(registers.programCounter, using: bus)
            push8(registers.status.rawValue | 0x10, using: bus)
            finishInterrupt(vector: 0x00FFFE, using: bus)
            return 7
        } else {
            push8(registers.programBank, using: bus)
            push16(registers.programCounter, using: bus)
            push8(registers.status.rawValue, using: bus)
            finishInterrupt(vector: 0x00FFE6, using: bus)
            return 8
        }
    }

    func cop(using bus: IIGSBus) -> Int {
        _ = fetch8(using: bus)
        if registers.emulationMode {
            push16(registers.programCounter, using: bus)
            push8(registers.status.rawValue, using: bus)
            finishInterrupt(vector: 0x00FFF4, using: bus)
            return 7
        } else {
            push8(registers.programBank, using: bus)
            push16(registers.programCounter, using: bus)
            push8(registers.status.rawValue, using: bus)
            finishInterrupt(vector: 0x00FFE4, using: bus)
            return 8
        }
    }

    func enterInterrupt(_ interrupt: CPUInterrupt, using bus: IIGSBus) -> Int {
        let vector: UInt32
        switch interrupt {
        case .irq:
            vector = registers.emulationMode ? 0x00FFFE : 0x00FFEE
        case .nmi:
            vector = registers.emulationMode ? 0x00FFFA : 0x00FFEA
        case .abort:
            vector = registers.emulationMode ? 0x00FFF8 : 0x00FFE8
        }

        if registers.emulationMode {
            push16(registers.programCounter, using: bus)
            push8(registers.status.rawValue, using: bus)
        } else {
            push8(registers.programBank, using: bus)
            push16(registers.programCounter, using: bus)
            push8(registers.status.rawValue, using: bus)
        }
        finishInterrupt(vector: vector, using: bus)
        return registers.emulationMode ? 7 : 8
    }

    func finishInterrupt(vector: UInt32, using bus: IIGSBus) {
        registers.status.remove(.decimal)
        registers.status.insert(.interruptDisable)
        registers.programBank = 0
        registers.programCounter = read16(at: vector, using: bus)
    }

    func pea(using bus: IIGSBus) -> Int {
        push16(fetch16(using: bus), using: bus)
        return 5
    }

    func pei(using bus: IIGSBus) -> Int {
        let pointer = directAddress(fetch8(using: bus))
        push16(read16Bank0(at: pointer, using: bus), using: bus)
        return directPageBaseCycleCount(6)
    }

    func per(using bus: IIGSBus) -> Int {
        let offset = Int16(bitPattern: fetch16(using: bus))
        let value = UInt16(truncatingIfNeeded: Int32(registers.programCounter) + Int32(offset))
        push16(value, using: bus)
        return 6
    }

    func phb(using bus: IIGSBus) -> Int {
        push8(registers.dataBank, using: bus)
        return 3
    }

    func plb(using bus: IIGSBus) -> Int {
        registers.dataBank = pull8(using: bus)
        updateZeroNegative(UInt16(registers.dataBank), width: .byte)
        return 4
    }

    func pushIndex(_ value: UInt16, using bus: IIGSBus) {
        if registers.indexRegistersAre8Bit {
            push8(UInt8(truncatingIfNeeded: value), using: bus)
        } else {
            push16(value, using: bus)
        }
    }

    func pullIndex(into keyPath: WritableKeyPath<CPURegisters, UInt16>, using bus: IIGSBus) {
        let value: UInt16
        if registers.indexRegistersAre8Bit {
            value = UInt16(pull8(using: bus))
        } else {
            value = pull16(using: bus)
        }
        registers[keyPath: keyPath] = value
        updateZeroNegativeIndex(value)
        enforceModeInvariants()
    }

    func pushAccumulator(using bus: IIGSBus) {
        if registers.accumulatorIs8Bit {
            push8(UInt8(truncatingIfNeeded: registers.accumulator), using: bus)
        } else {
            push16(registers.accumulator, using: bus)
        }
    }

    func pullAccumulator(using bus: IIGSBus) {
        if registers.accumulatorIs8Bit {
            let value = UInt16(pull8(using: bus))
            setAccumulatorLow(value)
            updateZeroNegative(value, width: .byte)
        } else {
            let value = pull16(using: bus)
            registers.accumulator = value
            updateZeroNegative(value, width: .word)
        }
    }

    func blockMove(increment: Bool, using bus: IIGSBus) -> Int {
        let sourceBank = fetch8(using: bus)
        let destinationBank = fetch8(using: bus)
        registers.dataBank = destinationBank

        let sourceAddress = (UInt32(sourceBank) << 16) | UInt32(registers.x)
        let destinationAddress = (UInt32(destinationBank) << 16) | UInt32(registers.y)
        let value = bus.read8(at: sourceAddress)
        bus.write8(value, at: destinationAddress)

        if increment {
            registers.x &+= 1
            registers.y &+= 1
        } else {
            registers.x &-= 1
            registers.y &-= 1
        }

        registers.accumulator &-= 1
        if registers.accumulator != 0xFFFF {
            registers.programCounter &-= 3
        }
        return 7
    }

    func exchangeCarryAndEmulation() {
        let oldCarry = registers.status.contains(.carry)
        let oldEmulation = registers.emulationMode
        registers.emulationMode = oldCarry
        setFlag(.carry, oldEmulation)
        enforceModeInvariants()
    }

    func enforceModeInvariants() {
        if registers.emulationMode {
            registers.status.insert([.accumulator8Bit, .indexRegister8Bit])
            registers.stackPointer = 0x0100 | (registers.stackPointer & 0x00FF)
        }
        if registers.indexRegistersAre8Bit {
            registers.x &= 0x00FF
            registers.y &= 0x00FF
        }
    }

    func updateZeroNegative(_ value: UInt16, width: RegisterWidth) {
        let maskedValue = value & width.mask
        setFlag(.zero, maskedValue == 0)
        setFlag(.negative, (maskedValue & width.signBit) != 0)
    }

    func setFlag(_ flag: ProcessorStatus, _ enabled: Bool) {
        if enabled {
            registers.status.insert(flag)
        } else {
            registers.status.remove(flag)
        }
    }

    func push8(_ value: UInt8, using bus: IIGSBus) {
        bus.write8(value, at: UInt32(registers.stackPointer))
        if registers.emulationMode {
            registers.stackPointer = 0x0100 | UInt16(UInt8(truncatingIfNeeded: registers.stackPointer &- 1))
        } else {
            registers.stackPointer &-= 1
        }
    }

    func push16(_ value: UInt16, using bus: IIGSBus) {
        push8(UInt8(truncatingIfNeeded: value >> 8), using: bus)
        push8(UInt8(truncatingIfNeeded: value), using: bus)
    }

    func pull8(using bus: IIGSBus) -> UInt8 {
        if registers.emulationMode {
            registers.stackPointer = 0x0100 | UInt16(UInt8(truncatingIfNeeded: registers.stackPointer &+ 1))
        } else {
            registers.stackPointer &+= 1
        }
        return bus.read8(at: UInt32(registers.stackPointer))
    }

    func pull16(using bus: IIGSBus) -> UInt16 {
        let low = UInt16(pull8(using: bus))
        let high = UInt16(pull8(using: bus)) << 8
        return high | low
    }
}
