import SwiftUI

struct BreakpointPanel: View {
    @ObservedObject var store: DebuggerStore

    var body: some View {
        GroupBox("Breakpoints") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("008000", text: $store.breakpointAddress)
                        .textFieldStyle(.roundedBorder)
                        .monospaced()

                    Button {
                        store.addBreakpoint()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add breakpoint")

                    Button {
                        store.clearBreakpoint()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help("Clear breakpoint")

                    Button {
                        store.clearAllBreakpoints()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear all breakpoints")
                }

                ScrollView {
                    Text(store.breakpoints)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 80)
            }
            .padding(.vertical, 4)
        }
    }
}

struct LogPanel: View {
    let logText: String

    var body: some View {
        GroupBox("Log") {
            ScrollView {
                Text(logText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .padding(.vertical, 4)
        }
    }
}
