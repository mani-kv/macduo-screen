import AppKit

/// A small panel above the actual overlay. The slider feeds the production
/// session rather than a separate sample renderer.
@MainActor
final class DesktopPreviewWindowController: NSWindowController, NSWindowDelegate {
    private let controller: FoldController
    private let slider = NSSlider(value: 90, minValue: 0, maxValue: 150, target: nil, action: nil)
    private let label = NSTextField(labelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private var timer: Timer?

    init(controller: FoldController) {
        self.controller = controller
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 148),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Test Desktop"
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        slider.target = self
        slider.action = #selector(changed)
        slider.isContinuous = true
        slider.setAccessibilityLabel("Test desktop lid angle")
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 48).isActive = true
        let done = NSButton(title: "Done", target: self, action: #selector(finish))
        done.keyEquivalent = "\u{1b}"
        let row = NSStackView(views: [slider, label, done])
        row.spacing = 12
        let note = NSTextField(wrappingLabelWithString: "Drag left to close, right to reopen. This uses your real desktop and current settings. Press Esc or Done to return to the lid sensor.")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 11)
        let root = NSStackView(views: [note, row, status])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 18),
            row.widthAnchor.constraint(equalTo: root.widthAnchor),
            note.widthAnchor.constraint(equalTo: root.widthAnchor),
            status.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func present() {
        slider.doubleValue = controller.settings.configuration.startAngle
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        changed()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatus() }
        }
    }

    @objc private func changed() {
        label.stringValue = String(format: "%.0f°", slider.doubleValue)
        controller.setDesktopPreview(angle: slider.doubleValue)
        refreshStatus()
    }

    private func refreshStatus() { status.stringValue = controller.status }
    @objc private func finish() { window?.performClose(nil) }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        controller.setDesktopPreview(angle: nil)
    }
}
