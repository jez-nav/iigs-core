import SwiftUI

@main
struct IIGSDebuggerApp: App {
    var body: some Scene {
        WindowGroup("IIGSDebugger") {
            ContentView()
                .frame(minWidth: 980, minHeight: 660)
        }
        .commands {
            CommandMenu("Debugger") {
                Button("Step") {
                    NotificationCenter.default.post(name: .debuggerStepRequested, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command])

                Button("Run") {
                    NotificationCenter.default.post(name: .debuggerRunRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Reset") {
                    NotificationCenter.default.post(name: .debuggerResetRequested, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let debuggerStepRequested = Notification.Name("IIGSDebugger.stepRequested")
    static let debuggerRunRequested = Notification.Name("IIGSDebugger.runRequested")
    static let debuggerResetRequested = Notification.Name("IIGSDebugger.resetRequested")
}
