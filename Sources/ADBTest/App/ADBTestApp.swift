import SwiftUI

@main
struct ADBTestApp: App {
    @StateObject private var store = ADBTestEmulatorStore()

    var body: some Scene {
        WindowGroup("ADBTest") {
            ADBTestContentView(store: store)
                .frame(minWidth: 720, minHeight: 480)
        }
    }
}
