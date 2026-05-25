public final class IIGSIWMDrive {
    public var media: IIGSFloppyMedia?
    public private(set) var quarterTrack: Int = 0
    fileprivate var streamOffset: Int = 0
    fileprivate var activePhase: Int?
    fileprivate var threePointFiveDiskSwitched = false

    public var track: Int {
        quarterTrack / 4
    }

    fileprivate func applyPhase(_ phase: Int, enabled: Bool) {
        guard enabled else {
            return
        }

        if let previous = activePhase, previous != phase {
            if (previous + 1) % 4 == phase {
                quarterTrack = min(quarterTrack + 1, (IIGSFloppyMedia.tracks5_25 * 4) - 1)
            } else if (phase + 1) % 4 == previous {
                quarterTrack = max(quarterTrack - 1, 0)
            }
        }
        activePhase = phase
    }

    fileprivate var threePointFiveCylinder: Int {
        quarterTrack / 2
    }

    fileprivate func activate3_5Head(side: Int) {
        let cylinder = min(max(threePointFiveCylinder, 0), IIGSFloppyMedia.tracks3_5 - 1)
        let clampedSide = min(max(side, 0), 1)
        let nextTrack = (cylinder * 2) + clampedSide
        if nextTrack != quarterTrack {
            quarterTrack = nextTrack
            streamOffset = 0
        }
    }

    fileprivate func step3_5(outward: Bool) {
        let side = quarterTrack & 1
        let cylinder = min(max(threePointFiveCylinder + (outward ? -1 : 1), 0), IIGSFloppyMedia.tracks3_5 - 1)
        let nextTrack = (cylinder * 2) + side
        if nextTrack != quarterTrack {
            quarterTrack = nextTrack
            streamOffset = 0
        }
    }

    fileprivate func resetStreamOffset() {
        streamOffset = 0
    }

    fileprivate func resetTransientState() {
        streamOffset = 0
        activePhase = nil
        threePointFiveDiskSwitched = false
    }

    fileprivate func mount(_ media: IIGSFloppyMedia) {
        threePointFiveDiskSwitched = self.media != nil
        self.media = media
        resetStreamOffset()
    }

    fileprivate func unmount() {
        if media != nil {
            threePointFiveDiskSwitched = true
        }
        media = nil
        resetStreamOffset()
    }

    fileprivate func clear3_5DiskSwitched() {
        threePointFiveDiskSwitched = false
    }
}

public final class IIGSIWMController {
    public private(set) var phaseLines = [false, false, false, false]
    public private(set) var motorOn = false
    public private(set) var selectedDriveNumber: UInt8 = 1
    public private(set) var q6 = false
    public private(set) var q7 = false
    public private(set) var driveControlRegister: UInt8 = 0
    public private(set) var modeRegister: UInt8 = 0
    public private(set) var threePointFiveMotorOn = false
    public private(set) var threePointFiveStepDirectionOutward = false
    public private(set) var debugTrace: [String] = []
    public private(set) var debugAccessCounts: [String: Int] = [:]
    private var writeModePrimed = false
    private var handshakeReadCount = 0

    public let drive1 = IIGSIWMDrive()
    public let drive2 = IIGSIWMDrive()

    public init() {}

    public func reset() {
        phaseLines = [false, false, false, false]
        motorOn = false
        selectedDriveNumber = 1
        q6 = false
        q7 = false
        driveControlRegister = 0
        modeRegister = 0
        threePointFiveMotorOn = false
        threePointFiveStepDirectionOutward = false
        writeModePrimed = false
        handshakeReadCount = 0
        debugTrace.removeAll(keepingCapacity: true)
        debugAccessCounts.removeAll(keepingCapacity: true)
        drive1.resetTransientState()
        drive2.resetTransientState()
    }

    public var selectedDrive: IIGSIWMDrive {
        selectedDriveNumber == 2 ? drive2 : drive1
    }

    public var is3_5Mode: Bool {
        driveControlRegister & 0x40 != 0
    }

    public var controlInput: Bool {
        driveControlRegister & 0x80 != 0
    }

    public func mount(_ media: IIGSFloppyMedia, drive: UInt8 = 1) {
        precondition(drive == 1 || drive == 2)
        if drive == 1 {
            drive1.mount(media)
        } else {
            drive2.mount(media)
        }
    }

    public func unmount(drive: UInt8) {
        precondition(drive == 1 || drive == 2)
        if drive == 1 {
            drive1.unmount()
        } else {
            drive2.unmount()
        }
    }

    public func readDriveControlRegister() -> UInt8 {
        driveControlRegister
    }

    public func writeDriveControlRegister(_ value: UInt8) {
        driveControlRegister = value & 0xC0
    }

    public func accessSwitch(
        offset: UInt8,
        value: UInt8 = 0,
        isWrite: Bool = false,
        cycle: UInt64? = nil,
        context: String? = nil
    ) -> UInt8 {
        let normalizedOffset = offset & 0x0F
        applySwitchLatch(normalizedOffset)

        if isWrite {
            if q6, q7 {
                if motorOn {
                    if writeModePrimed {
                        writeData(value)
                    } else {
                        writeModePrimed = true
                    }
                } else {
                    modeRegister = value & 0x1F
                }
            }
            trace("W \(hex(normalizedOffset))=\(hex(value))", cycle: cycle, context: context)
            return value
        }

        let result = normalizedOffset & 0x01 == 0 ? readLatchValue(cycle: cycle, context: context) : 0
        trace("R \(hex(normalizedOffset))->\(hex(result))", cycle: cycle, context: context)
        return result
    }

    private func applySwitchLatch(_ offset: UInt8) {
        switch offset {
        case 0x0...0x7:
            let phase = Int(offset >> 1)
            let enabled = offset & 0x01 != 0
            phaseLines[phase] = enabled
            if is3_5Mode, phase == 3, enabled, motorOn {
                perform3_5Action()
            } else if !is3_5Mode {
                selectedDrive.applyPhase(phase, enabled: enabled)
            }
        case 0x8:
            motorOn = false
        case 0x9:
            motorOn = true
        case 0xA:
            selectedDriveNumber = 1
        case 0xB:
            selectedDriveNumber = 2
        case 0xC:
            writeModePrimed = false
            setQ6(false)
        case 0xD:
            setQ6(true)
        case 0xE:
            writeModePrimed = false
            setQ7(false)
        case 0xF:
            if !q7 {
                writeModePrimed = false
            }
            setQ7(true)
        default:
            break
        }
    }

    private func setQ6(_ enabled: Bool) {
        if q6 != enabled {
            q6 = enabled
            handshakeReadCount = 0
        }
    }

    private func setQ7(_ enabled: Bool) {
        if q7 != enabled {
            q7 = enabled
            handshakeReadCount = 0
        }
    }

    private func readLatchValue(cycle: UInt64?, context: String?) -> UInt8 {
        if q6, !q7 {
            if is3_5Mode {
                var status = modeRegister & 0x1F
                if motorOn {
                    status |= 0x20
                }
                let statusSelector = selected3_5StatusSelector()
                let statusBit = read3_5StatusBit(statusSelector: statusSelector)
                count("status35[\(hex(statusSelector))]=\(statusBit ? 1 : 0)")
                if statusBit {
                    status |= 0x80
                }
                trace(
                    "STATUS35 sel=\(hex(statusSelector)) bit=\(statusBit ? 1 : 0) value=\(hex(status))",
                    cycle: cycle,
                    context: context
                )
                return status
            }

            var status = modeRegister & 0x1F
            if selectedDrive.media?.isWriteProtected == true {
                status |= 0x80
            }
            count("status525=\((status & 0x80) != 0 ? 1 : 0)")
            return status
        }

        if q7, !q6 {
            // Q7 high / Q6 low is the IWM write-handshake register. The ROM's
            // 3.5 firmware polls bit 7 for readiness and waits for bit 6 to
            // clear before sending the next byte. Without bit-cell timing, let
            // the underrun bit settle after a few polls like GSPlus does for
            // its simplified enable2 handshake.
            count("handshake")
            let value: UInt8 = handshakeReadCount < 3 ? 0xC0 : 0x80
            handshakeReadCount = min(handshakeReadCount + 1, 3)
            return value
        }

        guard motorOn, let media = selectedDrive.media else {
            count("data-missing")
            return 0xFF
        }

        let value = media.readTrackByte(quarterTrack: selectedDrive.quarterTrack, offset: selectedDrive.streamOffset)
        selectedDrive.streamOffset += 1
        count("data track=\(selectedDrive.quarterTrack)")
        return value
    }

    private func writeData(_ value: UInt8) {
        guard let media = selectedDrive.media else {
            return
        }
        media.writeTrackByte(value, quarterTrack: selectedDrive.quarterTrack, offset: selectedDrive.streamOffset)
        selectedDrive.streamOffset += 1
        handshakeReadCount = 0
    }

    private func read3_5StatusBit(statusSelector: UInt8) -> Bool {
        guard motorOn else {
            return true
        }

        switch statusSelector {
        case 0x00:
            return threePointFiveStepDirectionOutward
        case 0x01:
            selectedDrive.activate3_5Head(side: 0)
            return readSelected3_5DataBit()
        case 0x02:
            return selectedDrive.media == nil
        case 0x03:
            selectedDrive.activate3_5Head(side: 1)
            return readSelected3_5DataBit()
        case 0x04:
            return true
        case 0x06:
            guard let media = selectedDrive.media else {
                return true
            }
            return !media.isWriteProtected
        case 0x08:
            return !threePointFiveMotorOn
        case 0x09:
            return true
        case 0x0A:
            return selectedDrive.threePointFiveCylinder != 0
        case 0x0B:
            return !threePointFiveMotorOn
        case 0x0C:
            return selectedDrive.threePointFiveDiskSwitched
        case 0x0E:
            return selectedDrive.streamOffset & 1 != 0
        case 0x0F:
            return false
        default:
            return true
        }
    }

    private func selected3_5StatusSelector() -> UInt8 {
        var selector: UInt8 = 0
        if phaseLines[2] {
            selector |= 0x01
        }
        if controlInput {
            selector |= 0x02
        }
        if phaseLines[0] {
            selector |= 0x04
        }
        if phaseLines[1] {
            selector |= 0x08
        }
        return selector
    }

    private func readSelected3_5DataBit() -> Bool {
        let value = selectedDrive.media?.readTrackByte(
            quarterTrack: selectedDrive.quarterTrack,
            offset: selectedDrive.streamOffset
        ) ?? 0xFF
        return value & 0x80 != 0
    }

    private func perform3_5Action() {
        let selector = selected3_5StatusSelector()
        count("action35[\(hex(selector))]")
        switch selector {
        case 0x00:
            threePointFiveStepDirectionOutward = false
        case 0x01:
            threePointFiveStepDirectionOutward = true
        case 0x03:
            selectedDrive.clear3_5DiskSwitched()
        case 0x04:
            selectedDrive.step3_5(outward: threePointFiveStepDirectionOutward)
        case 0x08:
            threePointFiveMotorOn = true
        case 0x09:
            threePointFiveMotorOn = false
        case 0x0D:
            selectedDrive.unmount()
        default:
            break
        }
    }

    private func count(_ key: String) {
        debugAccessCounts[key, default: 0] += 1
    }

    private func trace(_ message: String, cycle: UInt64?, context: String?) {
        let cyclePrefix = cycle.map { "\($0) " } ?? ""
        let contextPrefix = context.map { "\($0) " } ?? ""
        debugTrace.append(
            "\(cyclePrefix)\(contextPrefix)\(message) q6=\(q6 ? 1 : 0) q7=\(q7 ? 1 : 0) c031=\(hex(driveControlRegister)) m=\(motorOn ? 1 : 0)/\(threePointFiveMotorOn ? 1 : 0) d=\(selectedDriveNumber) qt=\(selectedDrive.quarterTrack) off=\(selectedDrive.streamOffset)"
        )
        if debugTrace.count > 4_096 {
            debugTrace.removeFirst(debugTrace.count - 4_096)
        }
    }

    private func hex(_ value: UInt8) -> String {
        let text = String(value, radix: 16, uppercase: true)
        return "$" + String(repeating: "0", count: max(0, 2 - text.count)) + text
    }
}
