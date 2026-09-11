import AppKit
import MetalKit
import FoldCore

@MainActor
final class PreviewWindowController: NSWindowController {
    private let renderer: MetalRenderer
    private let canvas: MTKView
    private let settings: SettingsStore
    private let slider = NSSlider(value: 90, minValue: 0, maxValue: 150, target: nil, action: nil)
    private let angle = NSTextField(labelWithString: "90°")

    init(settings: SettingsStore) throws {
        self.settings = settings
        renderer = try MetalRenderer()
        canvas = MTKView(frame: NSRect(x: 0, y: 0, width: 640, height: 400), device: renderer.device)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 688, height: 504),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "MacFold Preview"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        guard let content = window.contentView else { return }
        canvas.colorPixelFormat = .bgra8Unorm
        canvas.isPaused = true
        canvas.enableSetNeedsDisplay = false
        canvas.clearColor = MTLClearColorMake(0, 0, 0, 1)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(canvas)
        slider.target = self
        slider.action = #selector(updatePreview)
        slider.isContinuous = true
        slider.setAccessibilityLabel("Preview lid angle")
        angle.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        angle.widthAnchor.constraint(equalToConstant: 48).isActive = true
        let row = NSStackView(views: [NSTextField(labelWithString: "Lid angle"), slider, angle])
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(row)
        let note = NSTextField(labelWithString: "Drag to close or reopen this sample desktop. Uses your current effect settings.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(note)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            canvas.heightAnchor.constraint(equalToConstant: 400),
            row.topAnchor.constraint(equalTo: canvas.bottomAnchor, constant: 16),
            row.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            note.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            note.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 10)
        ])
        try renderer.setImage(SampleDesktop.image())
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        canvas.layoutSubtreeIfNeeded()
        updatePreview()
    }

    @objc private func updatePreview() {
        let degrees = slider.doubleValue
        angle.stringValue = String(format: "%.0f°", degrees)
        renderer.draw(in: canvas, progress: settings.configuration.progress(for: degrees), configuration: settings.configuration)
    }
}

enum SampleDesktop {
    static func image() -> CGImage {
        let size = NSSize(width: 1280, height: 800)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(starting: NSColor(calibratedRed: 0.18, green: 0.37, blue: 0.48, alpha: 1),
                       ending: NSColor(calibratedRed: 0.70, green: 0.80, blue: 0.76, alpha: 1))!.draw(in: rect, angle: 45)
            NSColor.white.withAlphaComponent(0.25).setFill()
            NSBezierPath(ovalIn: NSRect(x: 720, y: 320, width: 720, height: 720)).fill()
            NSColor.white.withAlphaComponent(0.88).setFill()
            NSBezierPath(roundedRect: NSRect(x: 180, y: 130, width: 920, height: 540), xRadius: 18, yRadius: 18).fill()
            for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: 204 + i * 26, y: 632, width: 14, height: 14)).fill()
            }
            let ink = NSColor(calibratedWhite: 0.17, alpha: 1)
            ("A softer close." as NSString).draw(at: NSPoint(x: 240, y: 500), withAttributes: [.font: NSFont.systemFont(ofSize: 52, weight: .semibold), .foregroundColor: ink])
            ("Your lid sets the pace." as NSString).draw(at: NSPoint(x: 243, y: 448), withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: ink.withAlphaComponent(0.7)])
            for (i, width) in [680, 590, 640, 420].enumerated() {
                ink.withAlphaComponent(0.12).setFill()
                NSBezierPath(roundedRect: NSRect(x: 244, y: 350 - i * 36, width: width, height: 12), xRadius: 6, yRadius: 6).fill()
            }
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}
