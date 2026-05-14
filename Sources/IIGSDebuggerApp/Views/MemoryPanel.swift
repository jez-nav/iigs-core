import IIGSCore
import SwiftUI

struct MemoryPanel: View {
    @ObservedObject var store: DebuggerStore

    var body: some View {
        GroupBox("Memory") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    LabeledContent("Bank") {
                        TextField("00", text: $store.memoryBank)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 56)
                            .monospaced()
                            .onSubmit {
                                store.updateMemoryBank()
                            }
                    }

                    Button {
                        store.updateMemoryBank()
                    } label: {
                        Label("Read", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh bank")

                    Text("Range \(store.memoryBank.uppercased())0000...\(store.memoryBank.uppercased())FFFF")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(store.memoryRows) { row in
                            MemoryRowView(row: row)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct MemoryRowView: View {
    let row: IIGSDebuggerMemoryRow

    var body: some View {
        HStack(spacing: 12) {
            Text(hex(row.address, width: 6))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            Text(row.bytes.map { hex($0, width: 2) }.joined(separator: " "))
                .frame(width: 382, alignment: .leading)

            Text(row.ascii)
                .foregroundStyle(.secondary)
                .frame(minWidth: 132, alignment: .leading)
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
