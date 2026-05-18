import SwiftUI

@main
struct VideoTestApp: App {
    @StateObject private var store = VideoTestEmulatorStore()

    var body: some Scene {
        WindowGroup("VideoTest") {
            VideoTestContentView(store: store)
                .frame(minWidth: 720, minHeight: 480)
        }
    }
}
