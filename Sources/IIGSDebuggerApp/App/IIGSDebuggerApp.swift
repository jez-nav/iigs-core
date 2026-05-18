import SwiftUI

@main
struct IIGSDebuggerApp: App {
    var body: some Scene {
        WindowGroup("IIGSDebugger") {
            ContentView()
                .frame(minWidth: 1120, minHeight: 760)
        }
        .commands {
            CommandMenu("Debugger") {
                Button("Boot Local ROM1") {
                    NotificationCenter.default.post(name: .debuggerBootLocalROMRequested, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command])

                Button("Load Local ROM1") {
                    NotificationCenter.default.post(name: .debuggerLoadLocalROMRequested, object: nil)
                }
                .keyboardShortcut("1", modifiers: [.command])

                Divider()

                Button("Step") {
                    NotificationCenter.default.post(name: .debuggerStepRequested, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command])

                Button("Run") {
                    NotificationCenter.default.post(name: .debuggerRunRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Pause") {
                    NotificationCenter.default.post(name: .debuggerPauseRequested, object: nil)
                }
                .keyboardShortcut(".", modifiers: [.command])

                Button("Reset") {
                    NotificationCenter.default.post(name: .debuggerResetRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let debuggerLoadLocalROMRequested = Notification.Name("IIGSDebugger.loadLocalROMRequested")
    static let debuggerBootLocalROMRequested = Notification.Name("IIGSDebugger.bootLocalROMRequested")
    static let debuggerStepRequested = Notification.Name("IIGSDebugger.stepRequested")
    static let debuggerRunRequested = Notification.Name("IIGSDebugger.runRequested")
    static let debuggerPauseRequested = Notification.Name("IIGSDebugger.pauseRequested")
    static let debuggerResetRequested = Notification.Name("IIGSDebugger.resetRequested")
}
