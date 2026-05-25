import AppKit
import IIGSCore
import SwiftUI

struct DiskTestVideoSurfaceView: NSViewRepresentable {
    let frame: IIGSVideoFrame
    let isFocused: Bool
    let onFocusChanged: (Bool) -> Void
    let onKeyEvent: (IIGSHostKeyEvent) -> Void

    func makeNSView(context: Context) -> DiskTestVideoSurfaceNSView {
        let view = DiskTestVideoSurfaceNSView()
        view.frameBuffer = frame
        view.onFocusChanged = onFocusChanged
        view.onKeyEvent = onKeyEvent
        return view
    }

    func updateNSView(_ nsView: DiskTestVideoSurfaceNSView, context: Context) {
        nsView.frameBuffer = frame
        nsView.onFocusChanged = onFocusChanged
        nsView.onKeyEvent = onKeyEvent
        if isFocused, nsView.window?.firstResponder !== nsView {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class DiskTestVideoSurfaceNSView: NSView {
    var frameBuffer: IIGSVideoFrame = IIGSVideoFrame(width: 1, height: 1, pixels: [.black]) {
        didSet {
            cachedImage = nil
            needsDisplay = true
        }
    }

    var onFocusChanged: ((Bool) -> Void)?
    var onKeyEvent: ((IIGSHostKeyEvent) -> Void)?

    private var cachedImage: CGImage?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Apple IIgs disk test display")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        onFocusChanged?(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        onFocusChanged?(false)
        return true
    }

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

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        for input in MacKeyboardInputMapper.keyDownEvents(from: event) {
            onKeyEvent?(input)
        }
    }

    override func keyUp(with event: NSEvent) {
        for input in MacKeyboardInputMapper.keyUpEvents(from: event) {
            onKeyEvent?(input)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        if let input = MacKeyboardInputMapper.flagsChanged(from: event) {
            onKeyEvent?(input)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let events = MacKeyboardInputMapper.keyEquivalentEvents(from: event)
        guard !events.isEmpty else {
            return super.performKeyEquivalent(with: event)
        }
        for event in events {
            onKeyEvent?(event)
        }
        return true
    }

    private func makeImage(from frame: IIGSVideoFrame) -> CGImage {
        let byteCount = frame.width * frame.height * 4
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: frame.width,
            height: frame.height,
            bitsPerComponent: 8,
            bytesPerRow: frame.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ), let data = context.data else {
            fatalError("Unable to allocate Apple IIgs video bitmap")
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: byteCount)
        var offset = 0
        for pixel in frame.pixels {
            pixels[offset] = pixel.red
            pixels[offset + 1] = pixel.green
            pixels[offset + 2] = pixel.blue
            pixels[offset + 3] = 0xFF
            offset += 4
        }

        return context.makeImage()!
    }
}
