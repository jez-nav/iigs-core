public final class IIGSIWMDrive {
    public var media: IIGSFloppyMedia?
    public private(set) var quarterTrack: Int = 0
    fileprivate var streamOffset: Int = 0
    fileprivate var activePhase: Int?

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
    private var writeModePrimed = false

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
        writeModePrimed = false
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
            drive1.media = media
        } else {
            drive2.media = media
        }
    }

    public func unmount(drive: UInt8) {
        precondition(drive == 1 || drive == 2)
        if drive == 1 {
            drive1.media = nil
        } else {
            drive2.media = nil
        }
    }

    public func readDriveControlRegister() -> UInt8 {
        driveControlRegister
    }

    public func writeDriveControlRegister(_ value: UInt8) {
        driveControlRegister = value & 0xC0
    }

    public func accessSwitch(offset: UInt8, value: UInt8 = 0, isWrite: Bool = false) -> UInt8 {
        let normalizedOffset = offset & 0x0F
        applySwitchLatch(normalizedOffset)

        if isWrite {
            if q6, q7 {
                if motorOn, !is3_5Mode {
                    if writeModePrimed {
                        writeData(value)
                    } else {
                        writeModePrimed = true
                    }
                } else {
                    modeRegister = value & 0x1F
                }
            }
            return value
        }

        return readLatchValue()
    }

    private func applySwitchLatch(_ offset: UInt8) {
        switch offset {
        case 0x0...0x7:
            let phase = Int(offset >> 1)
            let enabled = offset & 0x01 != 0
            phaseLines[phase] = enabled
            selectedDrive.applyPhase(phase, enabled: enabled)
            if is3_5Mode, phase == 3, enabled {
                threePointFiveMotorOn = controlInput
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
            q6 = false
            writeModePrimed = false
        case 0xD:
            q6 = true
        case 0xE:
            q7 = false
            writeModePrimed = false
        case 0xF:
            if !q7 {
                writeModePrimed = false
            }
            q7 = true
        default:
            break
        }
    }

    private func readLatchValue() -> UInt8 {
        if q6, !q7 {
            var status = modeRegister & 0x1F
            if selectedDrive.media?.isWriteProtected == true {
                status |= 0x80
            }
            return status
        }

        if q7, !q6 {
            return is3_5Mode ? driveControlRegister : 0x00
        }

        guard motorOn, !is3_5Mode, let media = selectedDrive.media else {
            return 0xFF
        }

        let value = media.readTrackByte(quarterTrack: selectedDrive.quarterTrack, offset: selectedDrive.streamOffset)
        selectedDrive.streamOffset += 1
        return value
    }

    private func writeData(_ value: UInt8) {
        guard let media = selectedDrive.media else {
            return
        }
        media.writeTrackByte(value, quarterTrack: selectedDrive.quarterTrack, offset: selectedDrive.streamOffset)
        selectedDrive.streamOffset += 1
    }
}
