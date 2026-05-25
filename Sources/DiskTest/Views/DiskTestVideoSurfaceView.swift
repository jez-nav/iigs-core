import AppKit
import IIGSCore
import SwiftUI

struct DiskTestVideoSurfaceView: NSViewRepresentable {
    let frame: IIGSVideoFrame
    let isFocused: Bool
    let onFocusChanged: (Bool) -> Void
    let onMouse: (Int, Int, Bool, Bool) -> Void
    let onMouseExit: () -> Void
    let onKeyEvent: (IIGSHostKeyEvent) -> Void

    func makeNSView(context: Context) -> DiskTestVideoSurfaceNSView {
        let view = DiskTestVideoSurfaceNSView()
        view.frameBuffer = frame
        view.onFocusChanged = onFocusChanged
        view.onMouse = onMouse
        view.onMouseExit = onMouseExit
        view.onKeyEvent = onKeyEvent
        return view
    }

    func updateNSView(_ nsView: DiskTestVideoSurfaceNSView, context: Context) {
        nsView.frameBuffer = frame
        nsView.onFocusChanged = onFocusChanged
        nsView.onMouse = onMouse
        nsView.onMouseExit = onMouseExit
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
            if oldValue.width != frameBuffer.width || oldValue.height != frameBuffer.height {
                window?.invalidateCursorRects(for: self)
            }
        }
    }

    var onFocusChanged: ((Bool) -> Void)?
    var onMouse: ((Int, Int, Bool, Bool) -> Void)?
    var onMouseExit: (() -> Void)?
    var onKeyEvent: ((IIGSHostKeyEvent) -> Void)?

    private var cachedImage: CGImage?
    private var trackingArea: NSTrackingArea?
    private var mouseButtonDown = false
    private var mouseInsideActiveDisplay = false

    private static let transparentCursor = NSCursor(
        image: NSImage(size: NSSize(width: 1, height: 1)),
        hotSpot: .zero
    )

    private struct ActiveDisplayGeometry {
        let viewRect: NSRect
        let pixelWidth: Int
        let pixelHeight: Int
    }

    private struct PixelRect {
        let x: Int
        let y: Int
        let width: Int
        let height: Int

        var minX: Int { x }
        var minY: Int { y }
    }

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
        window?.acceptsMouseMovedEvents = true
        window?.invalidateCursorRects(for: self)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.acceptsMouseMovedEvents = true
            self.window?.invalidateCursorRects(for: self)
            self.window?.makeFirstResponder(self)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    override func becomeFirstResponder() -> Bool {
        onFocusChanged?(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        deactivateMouse()
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

    override func resetCursorRects() {
        addCursorRect(activeDisplayGeometry().viewRect, cursor: Self.transparentCursor)
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
        guard activeDisplayGeometry().viewRect.contains(convert(event.locationInWindow, from: nil)) else {
            deactivateMouse()
            return
        }
        mouseButtonDown = true
        sendMouse(event, buttonDown: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard mouseButtonDown else {
            deactivateMouse()
            return
        }
        sendMouse(event, buttonDown: true)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseButtonDown = false }
        guard mouseButtonDown else {
            deactivateMouse()
            return
        }
        sendMouse(event, buttonDown: false)
    }

    override func mouseMoved(with event: NSEvent) {
        sendMouse(event, buttonDown: mouseButtonDown)
    }

    override func mouseExited(with event: NSEvent) {
        deactivateMouse()
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

    private func sendMouse(_ event: NSEvent, buttonDown: Bool) {
        let location = convert(event.locationInWindow, from: nil)
        let geometry = activeDisplayGeometry()
        guard geometry.viewRect.contains(location) else {
            deactivateMouse()
            return
        }

        let syncToHostPosition = !mouseInsideActiveDisplay
        mouseInsideActiveDisplay = true
        let localX = location.x - geometry.viewRect.minX
        let localY = location.y - geometry.viewRect.minY
        let clampedX = min(max(0, localX), max(0, geometry.viewRect.width))
        let clampedY = min(max(0, localY), max(0, geometry.viewRect.height))
        let displayX = geometry.viewRect.width > 0
            ? Int((clampedX / geometry.viewRect.width * CGFloat(max(0, geometry.pixelWidth - 1))).rounded())
            : 0
        let displayY = geometry.viewRect.height > 0
            ? Int((clampedY / geometry.viewRect.height * CGFloat(max(0, geometry.pixelHeight - 1))).rounded())
            : 0
        onMouse?(displayX, displayY, buttonDown, syncToHostPosition)
    }

    private func deactivateMouse() {
        guard mouseInsideActiveDisplay || mouseButtonDown else {
            return
        }
        mouseInsideActiveDisplay = false
        mouseButtonDown = false
        onMouseExit?()
    }

    private func activeDisplayGeometry() -> ActiveDisplayGeometry {
        let pixelRect = activeDisplayPixelRect()
        guard frameBuffer.width > 0, frameBuffer.height > 0 else {
            return ActiveDisplayGeometry(viewRect: bounds, pixelWidth: 1, pixelHeight: 1)
        }

        let scaleX = bounds.width / CGFloat(frameBuffer.width)
        let scaleY = bounds.height / CGFloat(frameBuffer.height)
        let viewRect = NSRect(
            x: CGFloat(pixelRect.minX) * scaleX,
            y: CGFloat(pixelRect.minY) * scaleY,
            width: CGFloat(pixelRect.width) * scaleX,
            height: CGFloat(pixelRect.height) * scaleY
        ).intersection(bounds)
        return ActiveDisplayGeometry(
            viewRect: viewRect.isEmpty ? bounds : viewRect,
            pixelWidth: max(1, pixelRect.width),
            pixelHeight: max(1, pixelRect.height)
        )
    }

    private func activeDisplayPixelRect() -> PixelRect {
        let superHiresFrameWidth = IIGSVideoRenderer.superHiresWidth + IIGSVideoRenderer.wideBorderX * 2
        let superHiresFrameHeight = IIGSVideoRenderer.superHiresHeight + IIGSVideoRenderer.superHiresBorderY * 2
        if frameBuffer.width == superHiresFrameWidth, frameBuffer.height == superHiresFrameHeight {
            return PixelRect(
                x: IIGSVideoRenderer.wideBorderX,
                y: IIGSVideoRenderer.superHiresBorderY,
                width: IIGSVideoRenderer.superHiresWidth,
                height: IIGSVideoRenderer.superHiresHeight
            )
        }

        let classicHeight = IIGSVideoRenderer.classicGraphicsHeight
        let classicFrameHeight = classicHeight + IIGSVideoRenderer.classicBorderY * 2
        let classic40Width = IIGSVideoRenderer.classicGraphicsWidth
        let classic40FrameWidth = classic40Width + IIGSVideoRenderer.classicBorderX * 2
        if frameBuffer.width == classic40FrameWidth, frameBuffer.height == classicFrameHeight {
            return PixelRect(
                x: IIGSVideoRenderer.classicBorderX,
                y: IIGSVideoRenderer.classicBorderY,
                width: classic40Width,
                height: classicHeight
            )
        }

        let classic80Width = IIGSVideoRenderer.classicTextCellWidth * 80
        let classic80FrameWidth = classic80Width + IIGSVideoRenderer.wideBorderX * 2
        if frameBuffer.width == classic80FrameWidth, frameBuffer.height == classicFrameHeight {
            return PixelRect(
                x: IIGSVideoRenderer.wideBorderX,
                y: IIGSVideoRenderer.classicBorderY,
                width: classic80Width,
                height: classicHeight
            )
        }

        return PixelRect(x: 0, y: 0, width: frameBuffer.width, height: frameBuffer.height)
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
