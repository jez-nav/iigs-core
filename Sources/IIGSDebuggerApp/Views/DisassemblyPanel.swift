import IIGSCore
import SwiftUI

struct DisassemblyPanel: View {
    @ObservedObject var store: DebuggerStore

    var body: some View {
        GroupBox("Disassembly") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    LabeledContent("Start") {
                        TextField("008000", text: $store.disassemblyStart)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 92)
                            .monospaced()
                            .onSubmit {
                                store.refreshDisassemblyRows()
                            }
                    }

                    Button {
                        store.refreshDisassemblyRows()
                    } label: {
                        Label("Read", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh disassembly")

                    Spacer()
                }

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(store.disassemblyRows) { row in
                            DisassemblyRowView(row: row, currentAddress: store.snapshot.registers.programAddress)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityHidden(true)
                }
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct DisassemblyRowView: View {
    let row: IIGSDisassembledInstruction
    let currentAddress: UInt32

    var body: some View {
        HStack(spacing: 10) {
            Text(row.address == currentAddress ? ">" : " ")
                .foregroundStyle(row.address == currentAddress ? Color.accentColor : Color.secondary)
                .frame(width: 10, alignment: .leading)

            Text(hex(row.address, width: 6))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            Text(row.bytes.map { hex($0, width: 2) }.joined(separator: " "))
                .frame(width: 110, alignment: .leading)

            Text(row.mnemonic)
                .frame(width: 42, alignment: .leading)

            Text(row.operand)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .lineLimit(1)
    }
}

private func hex(_ value: UInt8, width: Int) -> String {
    hex(UInt32(value), width: width)
}

private func hex(_ value: UInt32, width: Int) -> String {
    let text = String(value, radix: 16, uppercase: true)
    return String(repeating: "0", count: Swift.max(0, width - text.count)) + text
}
