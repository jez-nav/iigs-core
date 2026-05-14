import SwiftUI

struct ControlPanel: View {
    @ObservedObject var store: DebuggerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Execution") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Step") {
                        TextField("1", text: $store.stepCount)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                    }

                    HStack {
                        Button {
                            store.step()
                        } label: {
                            Label("Step", systemImage: "forward.frame")
                        }

                        Button {
                            store.reset(.warm)
                        } label: {
                            Label("Warm", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }

                    LabeledContent("Run") {
                        TextField("1000", text: $store.runLimit)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 92)
                    }

                    HStack {
                        Button {
                            store.run()
                        } label: {
                            Label("Run", systemImage: "play.fill")
                        }

                        Button {
                            store.pause()
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
                        }

                        Button {
                            store.runCycles()
                        } label: {
                            Label("Cycles", systemImage: "timer")
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Binary") {
                LabeledContent("Address") {
                    TextField("008000", text: $store.binaryLoadAddress)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 92)
                        .monospaced()
                }
                .padding(.vertical, 4)
            }

            GroupBox("Edit") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("Reg", text: $store.registerName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 56)
                            .monospaced()

                        TextField("Value", text: $store.registerValue)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 92)
                            .monospaced()

                        Button {
                            store.writeRegister()
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .help("Write register")
                    }

                    HStack {
                        TextField("Address", text: $store.memoryWriteAddress)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 92)
                            .monospaced()

                        TextField("Byte", text: $store.memoryWriteValue)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 56)
                            .monospaced()

                        Button {
                            store.writeMemoryByte()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .help("Write memory byte")
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Command") {
                HStack {
                    TextField("regs", text: $store.commandText)
                        .textFieldStyle(.roundedBorder)
                        .monospaced()
                        .onSubmit {
                            store.runCommand()
                        }

                    Button {
                        store.runCommand()
                    } label: {
                        Image(systemName: "return")
                    }
                    .help("Run command")
                }
                .padding(.vertical, 4)
            }

            Spacer()
        }
        .padding(12)
    }
}
