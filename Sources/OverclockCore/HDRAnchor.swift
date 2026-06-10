import AppKit
import MetalKit
import OSLog

/// A 1x1 px view rendering an extended-range clear color. Its presence on
/// screen makes macOS engage the XDR backlight range (EDR headroom > 1).
final class EDRAnchorView: MTKView {
    private var commandQueue: MTLCommandQueue?

    init(frame: CGRect, edrTarget: Double) {
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())
        commandQueue = device?.makeCommandQueue()
        colorPixelFormat = .rgba16Float
        colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.wantsExtendedDynamicRangeContent = true
            metalLayer.pixelFormat = .rgba16Float
            metalLayer.isOpaque = false
        } else {
            Logger(subsystem: "BrightnessOverclock", category: "HDRAnchor")
                .error("Backing layer is not CAMetalLayer; EDR will not engage")
        }
        clearColor = MTLClearColorMake(edrTarget, edrTarget, edrTarget, 1.0)
        isPaused = true
        enableSetNeedsDisplay = true
    }

    required init(coder: NSCoder) { fatalError("not supported") }

    func setEDRTarget(_ value: Double) {
        clearColor = MTLClearColorMake(value, value, value, 1.0)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let buffer = commandQueue?.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.endEncoding() // clear-only pass; clearColor does the work
        buffer.present(drawable)
        buffer.commit()
    }
}

/// Borderless 1x1 px window hosting the EDR anchor view.
final class HDRAnchorWindow: NSWindow {
    private var anchorView: EDRAnchorView? { contentView as? EDRAnchorView }

    init(screen: NSScreen, edrTarget: Double) {
        // Top-left corner: hidden behind the display's rounded bezel corner.
        let origin = CGPoint(x: screen.frame.origin.x,
                             y: screen.frame.origin.y + screen.frame.height - 1)
        super.init(contentRect: NSRect(origin: origin, size: CGSize(width: 1, height: 1)),
                   styleMask: [], backing: .buffered, defer: false)
        collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle]
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        canHide = false
        animationBehavior = .none
        contentView = EDRAnchorView(frame: NSRect(x: 0, y: 0, width: 1, height: 1),
                                    edrTarget: edrTarget)
    }

    func show() {
        orderFrontRegardless()
        anchorView?.needsDisplay = true
        displayIfNeeded()
    }

    func setEDRTarget(_ value: Double) {
        anchorView?.setEDRTarget(value)
    }
}
