import AppKit
import FoldCore

private final class PassiveWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class OverlayWindow {
    private let window: NSWindow
    private let view = NSImageView(frame: .zero)
    private let renderer: MetalRenderer
    private let debug = NSTextField(labelWithString: "")
    private var renderSize = CGSize.zero
    private var scale = 1.0
    private var frameCount = 0
    private var intervalStart = ProcessInfo.processInfo.systemUptime
    private var fps = 0.0
    private(set) var lastError: String?

    init(renderer: MetalRenderer) {
        self.renderer = renderer
        window = PassiveWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.hidesOnDeactivate = false
        // Metal completes the image offscreen; AppKit presents it using the
        // normal window compositor, without a fullscreen CAMetalLayer drawable.
        view.imageScaling = .scaleAxesIndependently
        view.autoresizingMask = [.width, .height]
        let content = NSView(frame: .zero)
        window.contentView = content
        content.addSubview(view)
        debug.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        debug.textColor = .white
        debug.drawsBackground = true
        debug.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        debug.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(debug)
        NSLayoutConstraint.activate([
            debug.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            debug.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
    }

    func prepare(image: CGImage, screen: NSScreen) throws {
        hide()
        window.setFrame(screen.frame, display: false)
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        scale = Double(screen.backingScaleFactor)
        renderSize = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                            height: screen.frame.height * screen.backingScaleFactor)
        try renderer.setImage(image)
        intervalStart = ProcessInfo.processInfo.systemUptime
        frameCount = 0
    }

    @discardableResult
    func render(angle: Double, progress: Double, configuration: FoldConfiguration) -> Bool {
        do {
            // Wait for actual GPU completion, including error checking, before
            // replacing the visible image. The source snapshot stays unchanged.
            let image = try renderer.renderOffscreen(width: Int(renderSize.width), height: Int(renderSize.height),
                                                     progress: progress, configuration: configuration, scale: scale)
            view.image = NSImage(cgImage: image, size: view.bounds.size)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            return false
        }
        let now = ProcessInfo.processInfo.systemUptime
        frameCount += 1
        if now - intervalStart >= 0.5 {
            fps = Double(frameCount) / (now - intervalStart)
            frameCount = 0
            intervalStart = now
        }
        debug.isHidden = !configuration.showDebug
        debug.stringValue = String(format: "  %.0f°  ·  %.3f progress  ·  %.0f FPS (on change)  ", angle, progress, fps)
        // The first changed sensor degree must not expose a fully opaque
        // snapshot and black edge mask in one step. AppKit opacity follows
        // angle directly; there is no duration-based animation or tail.
        window.alphaValue = FoldConfiguration.overlayOpacity(for: progress)
        view.needsDisplay = true
        if !window.isVisible {
            window.displayIfNeeded()
            window.orderFrontRegardless()
        }
        return true
    }

    func hide() {
        window.orderOut(nil)
        window.alphaValue = 0
        view.image = nil
        renderer.clear()
    }
}
