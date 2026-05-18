import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var store = DebuggerStore()
    private let uiTimer = Timer.publish(every: 1.0 / 10.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            PrimaryActionBar(
                store: store,
                runStateText: runStateText,
                chooseROM: chooseROM,
                chooseBinary: chooseBinary
            )

            Divider()

            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 12) {
                    leftColumn
                    centerColumn
                    rightColumn
                }
                .padding(12)
                .frame(minWidth: 1180, minHeight: 700, alignment: .topLeading)
            }
            .accessibilityHidden(true)
        }
        .onReceive(uiTimer) { _ in
            if case .running = store.runState {
                store.runContinuousTick(instructionBudget: 8_000)
                store.noteUIRefresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .debuggerLoadLocalROMRequested)) { _ in
            store.loadLocalROM1()
        }
        .onReceive(NotificationCenter.default.publisher(for: .debuggerBootLocalROMRequested)) { _ in
            store.bootLocalROM1()
        }
        .onReceive(NotificationCenter.default.publisher(for: .debuggerStepRequested)) { _ in
            store.step()
        }
        .onReceive(NotificationCenter.default.publisher(for: .debuggerRunRequested)) { _ in
            store.run()
        }
        .onReceive(NotificationCenter.default.publisher(for: .debuggerPauseRequested)) { _ in
            store.pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .debuggerResetRequested)) { _ in
            store.reset()
        }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            MachineDisplayPanel(store: store)
                .frame(width: 560, height: 360)

            QuickExecutionPanel(store: store)
            LogPanel(logText: store.logText)
                .frame(height: 150)
        }
        .frame(width: 580, alignment: .topLeading)
    }

    private var centerColumn: some View {
        VStack(spacing: 12) {
            DisassemblyPanel(store: store)
                .frame(height: 330)

            MemoryPanel(store: store)
                .frame(height: 330)
        }
        .frame(width: 520, alignment: .top)
    }

    private var rightColumn: some View {
        ScrollView {
            VStack(spacing: 12) {
                RegisterPanel(snapshot: store.snapshot)
                TimingPanel(store: store)
                MousePanel(store: store, mouse: store.snapshot.mouse)
                InspectorPanel(snapshot: store.snapshot)
                BreakpointPanel(store: store)
            }
            .padding(.trailing, 4)
        }
        .frame(width: 320, height: 700, alignment: .top)
    }

    private var runStateText: String {
        switch store.runState {
        case .paused:
            return "Paused"
        case .running:
            return "Running"
        case let .stopped(reason):
            return "Stopped: \(reason)"
        }
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

private struct PrimaryActionBar: View {
    @ObservedObject var store: DebuggerStore
    let runStateText: String
    let chooseROM: () -> Void
    let chooseBinary: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                store.bootLocalROM1()
            } label: {
                Label("Boot ROM1", systemImage: "power")
                    .frame(minWidth: 118)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!store.canLoadLocalROM1)
            .keyboardShortcut("b", modifiers: [.command])
            .help("Load the local ROM1 fixture and run")
            .accessibilityLabel("Boot local ROM1")
            .accessibilityIdentifier("bootLocalROM1Button")

            Button {
                store.loadLocalROM1()
            } label: {
                Label("Load ROM1", systemImage: "memorychip")
                    .frame(minWidth: 118)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!store.canLoadLocalROM1)
            .keyboardShortcut("1", modifiers: [.command])
            .help("Load the local ROM1 fixture")
            .accessibilityLabel("Load local ROM1")
            .accessibilityIdentifier("loadLocalROM1Button")

            Button {
                chooseROM()
            } label: {
                Label("Open ROM", systemImage: "folder")
                    .frame(minWidth: 106)
            }
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: [.command])
            .help("Open a ROM file")
            .accessibilityLabel("Open ROM file")
            .accessibilityIdentifier("openROMButton")

            Button {
                chooseBinary()
            } label: {
                Label("Binary", systemImage: "doc.badge.plus")
            }
            .controlSize(.large)
            .help("Load a binary file")
            .accessibilityLabel("Load binary file")
            .accessibilityIdentifier("loadBinaryButton")

            Divider()
                .frame(height: 28)

            Button {
                store.reset(.cold)
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help("Cold reset")
            .accessibilityIdentifier("resetButton")

            Button {
                store.step()
            } label: {
                Label("Step", systemImage: "forward.frame")
            }
            .controlSize(.large)
            .keyboardShortcut("s", modifiers: [.command])
            .help("Step one instruction")
            .accessibilityIdentifier("stepButton")

            Button {
                store.run()
            } label: {
                Label("Run", systemImage: "play.fill")
                    .frame(minWidth: 76)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: [.command])
            .help("Run continuously")
            .accessibilityIdentifier("runButton")

            Button {
                store.pause()
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .controlSize(.large)
            .keyboardShortcut(".", modifiers: [.command])
            .help("Pause execution")
            .accessibilityIdentifier("pauseButton")

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("IIGSDebugger")
                    .font(.headline)
                Text(runStateText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(runStateText == "Running" ? Color.green : Color.secondary)
            }
            .frame(minWidth: 130, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct QuickExecutionPanel: View {
    @ObservedObject var store: DebuggerStore

    var body: some View {
        GroupBox("Execution") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    LabeledContent("Step") {
                        TextField("1", text: $store.stepCount)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .monospaced()
                    }

                    Button {
                        store.step()
                    } label: {
                        Label("Step", systemImage: "forward.frame")
                    }

                    Button {
                        store.reset(.warm)
                    } label: {
                        Label("Warm Reset", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                HStack(spacing: 10) {
                    LabeledContent("Cycles") {
                        TextField("1000", text: $store.runLimit)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 92)
                            .monospaced()
                    }

                    Button {
                        store.runCycles()
                    } label: {
                        Label("Run Cycles", systemImage: "timer")
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
                    TextField("Command", text: $store.commandText)
                        .textFieldStyle(.roundedBorder)
                        .monospaced()
                        .onSubmit {
                            store.runCommand()
                        }

                    Button {
                        store.runCommand()
                    } label: {
                        Label("Send", systemImage: "return")
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
