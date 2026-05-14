import IIGSCore
import SwiftUI

struct RegisterPanel: View {
    let snapshot: IIGSDebuggerSnapshot

    var body: some View {
        GroupBox("Registers") {
            VStack(spacing: 10) {
                RegisterGrid(registers: snapshot.registers)
                FlagGrid(flags: snapshot.flags)
                StatusGrid(status: snapshot.status)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct RegisterGrid: View {
    let registers: IIGSDebuggerRegisterSnapshot

    private var rows: [(String, String)] {
        [
            ("PC", hex(registers.programCounter, width: 4)),
            ("PBR", hex(registers.programBank, width: 2)),
            ("S", hex(registers.stackPointer, width: 4)),
            ("D", hex(registers.directPage, width: 4)),
            ("DBR", hex(registers.dataBank, width: 2)),
            ("A", hex(registers.accumulator, width: 4)),
            ("X", hex(registers.x, width: 4)),
            ("Y", hex(registers.y, width: 4)),
            ("P", hex(registers.status, width: 2)),
        ]
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Text(row.1)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FlagGrid: View {
    let flags: IIGSDebuggerFlagSnapshot

    private var values: [(String, Bool)] {
        [
            ("N", flags.negative),
            ("V", flags.overflow),
            ("M", flags.accumulator8Bit),
            ("X", flags.index8Bit),
            ("D", flags.decimal),
            ("I", flags.interruptDisable),
            ("Z", flags.zero),
            ("C", flags.carry),
        ]
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(values, id: \.0) { item in
                Text(item.0)
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 22, height: 20)
                    .foregroundStyle(item.1 ? Color.primary : Color.secondary)
                    .background(item.1 ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .help(item.1 ? "\(item.0) set" : "\(item.0) clear")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusGrid: View {
    let status: IIGSDebuggerStatusSnapshot

    private var values: [(String, Bool)] {
        [
            ("RDY", status.ready),
            ("IRQ", status.irqPending),
            ("NMI", status.nmiPending),
            ("ABT", status.abortPending),
            ("E", status.emulationMode),
            ("WAI", status.waiting),
            ("STP", status.stopped),
        ]
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(values, id: \.0) { item in
                GridRow {
                    Text(item.0)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(item.1 ? "1" : "0")
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TimingPanel: View {
    @ObservedObject var store: DebuggerStore

    var body: some View {
        GroupBox("Stats") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                stat("EM", store.emulatorFPS)
                stat("UI", store.uiFPS)
                stat("CK", store.elapsedSinceReset)
                stat("Cycles", "\(store.snapshot.timing.cycles)")
                stat("Video", "L\(store.snapshot.timing.videoLine) C\(store.snapshot.timing.videoCycleInLine)")
                stat("VBL", store.snapshot.timing.inVerticalBlank ? "1" : "0")
            }
            .font(.system(.caption, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func stat(_ name: String, _ value: String) -> some View {
        GridRow {
            Text(name)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

struct MousePanel: View {
    @ObservedObject var store: DebuggerStore
    let mouse: IIGSDebuggerMouseSnapshot

    var body: some View {
        GroupBox("Mouse") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                row("Host", coordinate(store.hostMouseX, store.hostMouseY))
                row("Display", coordinate(store.displayMouseX, store.displayMouseY))
                row("ROM", "\(mouse.romX) / \(mouse.romY)")
                row("Button", mouse.buttonDown ? "down" : "up")
            }
            .font(.system(.caption, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
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

    private func coordinate(_ x: Int?, _ y: Int?) -> String {
        guard let x, let y else {
            return "-- / --"
        }
        return "\(x) / \(y)"
    }
}

private func hex(_ value: UInt8, width: Int) -> String {
    hex(UInt32(value), width: width)
}

private func hex(_ value: UInt16, width: Int) -> String {
    hex(UInt32(value), width: width)
}

private func hex(_ value: UInt32, width: Int) -> String {
    let text = String(value, radix: 16, uppercase: true)
    return String(repeating: "0", count: Swift.max(0, width - text.count)) + text
}
