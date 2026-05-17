import IIGSCore
import SwiftUI

struct InspectorPanel: View {
    let snapshot: IIGSDebuggerSnapshot

    var body: some View {
        GroupBox("Inspectors") {
            VStack(alignment: .leading, spacing: 10) {
                HardwareInspector(hardware: snapshot.hardware)
                Divider()
                InterruptInspector(interrupts: snapshot.interrupts)
                Divider()
                SchedulerInspector(events: snapshot.pendingEvents)
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.vertical, 4)
        }
    }
}

private struct HardwareInspector: View {
    let hardware: IIGSDebuggerHardwareSnapshot

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            row("STATE", hex(hardware.stateRegister, width: 2))
            row("SHDW", hex(hardware.shadowInhibit, width: 2))
            row("SPEED", hex(hardware.speedRegister, width: 2))
            row("VIDEO", hex(hardware.videoControl, width: 2))
            row("TXT", hex(hardware.textColor, width: 2))
            row("VC/HC", "\(hex(hardware.verticalCounter, width: 2)) / \(hex(hardware.horizontalCounter, width: 2))")
            row("ADB MOD", hex(hardware.keyboardModifiers, width: 2))
        }
        VStack(alignment: .leading, spacing: 2) {
            Text("ADB")
                .foregroundStyle(.secondary)
            ForEach(hardware.adbTrace.suffix(8), id: \.self) { line in
                Text(line)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, 4)
    }

    private func row(_ name: String, _ value: String) -> some View {
        GridRow {
            Text(name)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private struct InterruptInspector: View {
    let interrupts: IIGSDebuggerInterruptSnapshot

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            row("IRQ", interrupts.irqAsserted ? "1" : "0")
            row("VGC IE", hex(interrupts.videoEnable, width: 2))
            row("VGC ST", hex(interrupts.videoStatus, width: 2))
            row("C023 IE", hex(interrupts.c023Enable, width: 2))
            row("C023 ST", hex(interrupts.c023Status, width: 2))
            row("VBL/QS", "\(bit(interrupts.verticalBlankPending)) / \(bit(interrupts.quarterSecondPending))")
            row("SL/1S", "\(bit(interrupts.scanlinePending)) / \(bit(interrupts.oneSecondPending))")
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        GridRow {
            Text(name)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private struct SchedulerInspector: View {
    let events: [IIGSDebuggerEventSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Events")
                .foregroundStyle(.secondary)

            if events.isEmpty {
                Text("none")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events.prefix(6)) { event in
                    Text("\(event.cycle) \(eventKind(event.kind)) \(hex(event.payload, width: 6))")
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func eventKind(_ kind: IIGSEventKind) -> String {
    switch kind {
    case .videoScanline:
        return "scanline"
    case .verticalBlankStart:
        return "vblStart"
    case .verticalBlankEnd:
        return "vblEnd"
    case .videoFrame:
        return "frame"
    case .paddleTimeout:
        return "paddle"
    case .docOscillator:
        return "doc"
    case .disk:
        return "disk"
    case .scc:
        return "scc"
    case .clockTick:
        return "clock"
    case .custom:
        return "custom"
    }
}

private func bit(_ value: Bool) -> String {
    value ? "1" : "0"
}

private func hex(_ value: UInt8, width: Int) -> String {
    hex(UInt32(value), width: width)
}

private func hex(_ value: UInt32, width: Int) -> String {
    let text = String(value, radix: 16, uppercase: true)
    return String(repeating: "0", count: Swift.max(0, width - text.count)) + text
}
