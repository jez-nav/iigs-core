import SwiftUI

struct MemoryPanel: View {
    @ObservedObject var store: DebuggerStore

    var body: some View {
        GroupBox("Memory") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    LabeledContent("Address") {
                        TextField("000000", text: $store.memoryAddress)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 96)
                            .monospaced()
                    }

                    LabeledContent("Bytes") {
                        TextField("16", text: $store.memoryCount)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                    }

                    Button {
                        store.refreshMemory()
                    } label: {
                        Label("Read", systemImage: "arrow.clockwise")
                    }
                }

                ScrollView {
                    Text(store.memoryDump)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120)
            }
            .padding(.vertical, 4)
        }
    }
}
