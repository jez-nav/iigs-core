import AppKit
import IIGSCore
import SwiftUI

struct VideoSurfaceView: NSViewRepresentable {
    let frame: IIGSVideoFrame

    func makeNSView(context: Context) -> VideoSurfaceNSView {
        let view = VideoSurfaceNSView()
        view.frameBuffer = frame
        return view
    }

    func updateNSView(_ nsView: VideoSurfaceNSView, context: Context) {
        nsView.frameBuffer = frame
    }
}

final class VideoSurfaceNSView: NSView {
    var frameBuffer: IIGSVideoFrame = IIGSVideoFrame(width: 1, height: 1, pixels: [.black]) {
        didSet {
            cachedImage = nil
            needsDisplay = true
        }
    }

    private var cachedImage: CGImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Apple IIgs video output")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()

        guard let graphicsContext = NSGraphicsContext.current else {
            return
        }

        let image = cachedImage ?? makeImage(from: frameBuffer)
        cachedImage = image
        graphicsContext.imageInterpolation = .none
        NSImage(cgImage: image, size: bounds.size).draw(in: bounds)
    }

    private func makeImage(from frame: IIGSVideoFrame) -> CGImage {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(frame.width * frame.height * 4)
        for pixel in frame.pixels {
            bytes.append(pixel.red)
            bytes.append(pixel.green)
            bytes.append(pixel.blue)
            bytes.append(0xFF)
        }

        let provider = CGDataProvider(data: Data(bytes) as CFData)
        return CGImage(
            width: frame.width,
            height: frame.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: frame.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}
