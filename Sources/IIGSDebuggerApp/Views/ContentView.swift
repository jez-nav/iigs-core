import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var store = DebuggerStore()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            HSplitView {
                ControlPanel(store: store)
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

                VStack(spacing: 12) {
                    RegisterPanel(registers: store.registers)
                    MemoryPanel(store: store)
                }
                .padding(12)
                .frame(minWidth: 360)

                VStack(spacing: 12) {
                    BreakpointPanel(store: store)
                    LogPanel(logText: store.logText)
                }
                .padding(12)
                .frame(minWidth: 300, idealWidth: 360)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .debuggerStepRequested)) { _ in
            store.step()
        }
        .onReceive(NotificationCenter.default.publisher(for: .debuggerRunRequested)) { _ in
            store.run()
        }
        .onReceive(NotificationCenter.default.publisher(for: .debuggerResetRequested)) { _ in
            store.reset()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                chooseROM()
            } label: {
                Label("ROM", systemImage: "memorychip")
            }
            .help("Load ROM")

            Button {
                chooseBinary()
            } label: {
                Label("Binary", systemImage: "doc.badge.plus")
            }
            .help("Load binary")

            Spacer()

            Text("IIGSDebugger")
                .font(.headline)

            Spacer()

            Button {
                store.reset(.cold)
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .help("Cold reset")

            Button {
                store.step()
            } label: {
                Label("Step", systemImage: "forward.frame")
            }
            .help("Step")

            Button {
                store.run()
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .help("Run")
        }
        .controlSize(.regular)
    }

    private func chooseROM() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Load Apple IIgs ROM"

        if panel.runModal() == .OK, let url = panel.url {
            store.loadROM(from: url)
        }
    }

    private func chooseBinary() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Load Binary"

        if panel.runModal() == .OK, let url = panel.url {
            store.loadBinary(from: url)
        }
    }
}
