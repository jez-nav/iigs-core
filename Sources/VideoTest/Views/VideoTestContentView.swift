import IIGSCore
import SwiftUI

struct VideoTestContentView: View {
    @ObservedObject var store: VideoTestEmulatorStore

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VideoSurfaceView(frame: store.videoFrame)
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
        .background(WindowTitleUpdater(title: store.windowTitle))
        .onAppear {
            store.start()
        }
        .onDisappear {
            store.stop()
        }
    }

    private func displayAspectRatio(for frame: IIGSVideoFrame) -> CGFloat {
        if frame.width == IIGSVideoRenderer.superHiresWidth,
           frame.height == IIGSVideoRenderer.superHiresHeight {
            return CGFloat(IIGSVideoRenderer.superHiresWidth) / CGFloat(IIGSVideoRenderer.superHiresHeight * 2)
        }
        return CGFloat(max(1, frame.width)) / CGFloat(max(1, frame.height))
    }
}
