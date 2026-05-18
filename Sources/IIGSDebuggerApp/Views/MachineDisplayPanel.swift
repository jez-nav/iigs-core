import AppKit
import IIGSCore
import SwiftUI

struct MachineDisplayPanel: View {
    @ObservedObject var store: DebuggerStore

    var body: some View {
        GroupBox("Display") {
            VStack(alignment: .leading, spacing: 8) {
                MachineDisplayView(
                    frame: store.videoFrame,
                    isFocused: store.displayHasKeyboardFocus,
                    onFocusChanged: store.setDisplayFocus(_:),
                    onMouse: store.updateDisplayMouse(hostX:hostY:displayX:displayY:buttonDown:),
                    onMouseExit: store.clearHostMouse,
                    onKeyDown: store.handleKeyDown(characters:keyCode:modifiers:),
                    onKeyUp: store.handleKeyUp(keyCode:modifiers:)
                )
                .aspectRatio(
                    displayAspectRatio(for: store.videoFrame),
                    contentMode: .fit
                )
                .overlay(alignment: .topLeading) {
                    Text(store.displayHasKeyboardFocus ? "Input captured" : "Click display for input")
                        .font(.system(.caption2, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
            }
            .padding(.vertical, 4)
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

private struct MachineDisplayView: NSViewRepresentable {
    let frame: IIGSVideoFrame
    let isFocused: Bool
    let onFocusChanged: (Bool) -> Void
    let onMouse: (Int, Int, Int, Int, Bool) -> Void
    let onMouseExit: () -> Void
    let onKeyDown: (String, UInt16, NSEvent.ModifierFlags) -> Void
    let onKeyUp: (UInt16, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> MachineDisplayNSView {
        let view = MachineDisplayNSView()
        view.onFocusChanged = onFocusChanged
        view.onMouse = onMouse
        view.onMouseExit = onMouseExit
        view.onKeyDown = onKeyDown
        view.onKeyUp = onKeyUp
        view.frameBuffer = frame
        return view
    }

    func updateNSView(_ nsView: MachineDisplayNSView, context: Context) {
        nsView.frameBuffer = frame
        nsView.onFocusChanged = onFocusChanged
        nsView.onMouse = onMouse
        nsView.onMouseExit = onMouseExit
        nsView.onKeyDown = onKeyDown
        nsView.onKeyUp = onKeyUp
        if isFocused, nsView.window?.firstResponder !== nsView {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class MachineDisplayNSView: NSView {
    var frameBuffer: IIGSVideoFrame = IIGSVideoFrame(width: 1, height: 1, pixels: [.black]) {
        didSet {
            cachedImage = nil
            needsDisplay = true
        }
    }

    var onFocusChanged: ((Bool) -> Void)?
    var onMouse: ((Int, Int, Int, Int, Bool) -> Void)?
    var onMouseExit: (() -> Void)?
    var onKeyDown: ((String, UInt16, NSEvent.ModifierFlags) -> Void)?
    var onKeyUp: ((UInt16, NSEvent.ModifierFlags) -> Void)?

    private var cachedImage: CGImage?
    private var trackingArea: NSTrackingArea?
    private var mouseButtonDown = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Apple IIgs display")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        onFocusChanged?(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        onFocusChanged?(false)
        return true
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
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
        mouseButtonDown = true
        sendMouse(event, buttonDown: true)
    }

    override func mouseDragged(with event: NSEvent) {
        sendMouse(event, buttonDown: true)
    }

    override func mouseUp(with event: NSEvent) {
        mouseButtonDown = false
        sendMouse(event, buttonDown: false)
    }

    override func mouseMoved(with event: NSEvent) {
        sendMouse(event, buttonDown: mouseButtonDown)
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExit?()
    }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event.characters ?? event.charactersIgnoringModifiers ?? "", event.keyCode, event.modifierFlags)
    }

    override func keyUp(with event: NSEvent) {
        onKeyUp?(event.keyCode, event.modifierFlags)
    }

    private func sendMouse(_ event: NSEvent, buttonDown: Bool) {
        let location = convert(event.locationInWindow, from: nil)
        let clampedX = min(max(0, location.x), max(0, bounds.width))
        let clampedY = min(max(0, location.y), max(0, bounds.height))
        let displayX = bounds.width > 0 ? Int((clampedX / bounds.width * CGFloat(max(0, frameBuffer.width - 1))).rounded()) : 0
        let displayY = bounds.height > 0 ? Int((clampedY / bounds.height * CGFloat(max(0, frameBuffer.height - 1))).rounded()) : 0
        onMouse?(Int(clampedX.rounded()), Int(clampedY.rounded()), displayX, displayY, buttonDown)
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
