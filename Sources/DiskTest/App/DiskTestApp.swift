import SwiftUI

@main
struct DiskTestApp: App {
    @StateObject private var store = DiskTestEmulatorStore()

    var body: some Scene {
        WindowGroup("DiskTest") {
            DiskTestContentView(store: store)
                .frame(minWidth: 960, minHeight: 560)
        }
        .commands {
            CommandMenu("Emulator") {
                Button("Classic Desk Accessory") {
                    store.sendClassicDeskAccessoryKey()
                }
                .keyboardShortcut(.escape, modifiers: [.command, .control])
            }
        }
    }
}
