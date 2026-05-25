import IIGSCore
import SwiftUI

struct ADBTestContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: ADBTestEmulatorStore

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black

                ADBTestVideoSurfaceView(
                    frame: store.videoFrame,
                    isFocused: store.displayHasKeyboardFocus,
                    onFocusChanged: store.setDisplayFocus(_:),
                    onKeyEvent: store.handleKeyEvent(_:)
                )
                .aspectRatio(displayAspectRatio(for: store.videoFrame), contentMode: .fit)
                .padding(24)

                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            keyboardControlBar
        }
        .background(Color.black.ignoresSafeArea())
        .background(WindowTitleUpdater(title: store.windowTitle))
        .onAppear {
            store.start()
        }
        .onDisappear {
            store.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.appBecameActive()
            case .inactive, .background:
                store.appBecameInactive()
            @unknown default:
                store.appBecameInactive()
            }
        }
    }

    private var keyboardControlBar: some View {
        HStack(spacing: 12) {
            Button(action: store.sendResetKey) {
                Label("BASIC Reset", systemImage: "terminal")
            }

            Button(action: store.sendControlResetKey) {
                Label("Control-Reset", systemImage: "restart")
            }

            Button(action: store.sendControlPanelResetKey) {
                Label("Control Panel", systemImage: "gearshape")
            }

            Button(action: store.typeBasicSmokeTest) {
                Label("Type BASIC Test", systemImage: "keyboard")
            }
            .buttonStyle(.borderedProminent)

            Spacer(minLength: 8)

            Text("F12 Reset  |  F1 Open-Apple  |  F2 Closed-Apple")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(store.inputStatus)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(store.displayHasKeyboardFocus ? .green : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func displayAspectRatio(for frame: IIGSVideoFrame) -> CGFloat {
        let superHiresFrameWidth = IIGSVideoRenderer.superHiresWidth + IIGSVideoRenderer.wideBorderX * 2
        let superHiresFrameHeight = IIGSVideoRenderer.superHiresHeight + IIGSVideoRenderer.superHiresBorderY * 2
        if frame.width == IIGSVideoRenderer.superHiresWidth && frame.height == IIGSVideoRenderer.superHiresHeight
            || frame.width == superHiresFrameWidth && frame.height == superHiresFrameHeight {
            return CGFloat(frame.width) / CGFloat(frame.height * 2)
        }
        return CGFloat(max(1, frame.width)) / CGFloat(max(1, frame.height))
    }
}
