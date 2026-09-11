import AppKit
import FoldCore
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let controller: FoldController
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let angleLabel = NSTextField(labelWithString: "—°")
    private let enable = NSButton(checkboxWithTitle: "Enable lid effect", target: nil, action: nil)
    private let login = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let fold = NSButton(checkboxWithTitle: "Keep the picture upright as the lid closes", target: nil, action: nil)
    private let debug = NSButton(checkboxWithTitle: "Show angle, progress, and render FPS", target: nil, action: nil)
    private let permissionButton = NSButton(title: "Allow Screen Recording…", target: nil, action: nil)
    private let loginNote = NSTextField(wrappingLabelWithString: "")
    private var sliders: [String: NSSlider] = [:]
    private var values: [String: NSTextField] = [:]
    private var refreshTimer: Timer?
    private var lastLoginCheck: TimeInterval = -.infinity
    private var cachedLoginStatus: SMAppService.Status = .notRegistered

    init(controller: FoldController) {
        self.controller = controller
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 716),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "MacFold Settings"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildUI()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func present() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func windowWillClose(_ notification: Notification) { refreshTimer?.invalidate(); refreshTimer = nil }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 26)
        ])
        let title = NSTextField(labelWithString: "MacFold")
        title.font = .systemFont(ofSize: 27, weight: .semibold)
        let subtitle = note("A softer close. Your lid sets the pace.")
        let titles = stack([title, subtitle], spacing: 5)
        let icon = NSImageView(image: NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: nil)!)
        icon.contentTintColor = .controlAccentColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        root.addArrangedSubview(horizontal([icon, titles], spacing: 14))
        addRule(root)

        angleLabel.font = .monospacedDigitSystemFont(ofSize: 31, weight: .light)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        let status = horizontal([angleLabel, statusLabel], spacing: 20)
        status.heightAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
        root.addArrangedSubview(status)
        for (button, selector) in [(enable, #selector(toggleEnabled)), (login, #selector(toggleLogin)),
                                    (fold, #selector(toggleFold)), (debug, #selector(toggleDebug))] {
            button.target = self
            button.action = selector
        }
        root.addArrangedSubview(horizontal([enable, login], spacing: 30))
        loginNote.font = .systemFont(ofSize: 11)
        loginNote.textColor = .secondaryLabelColor
        root.addArrangedSubview(loginNote)
        addRule(root)

        let controls = stack([], spacing: 12)
        controls.addArrangedSubview(sliderRow("start", title: "Begin below", range: 15...150))
        controls.addArrangedSubview(sliderRow("end", title: "Fully faded at", range: 0...85))
        controls.addArrangedSubview(sliderRow("blur", title: "Blur", range: 0...60))
        controls.addArrangedSubview(sliderRow("darkening", title: "Dimming", range: 0...1))
        root.addArrangedSubview(controls)
        root.addArrangedSubview(fold)
        let folding = stack([], spacing: 12)
        folding.addArrangedSubview(sliderRow("perspective", title: "Perspective", range: 0...1))
        folding.addArrangedSubview(sliderRow("compression", title: "Stretch", range: 0...0.95))
        root.addArrangedSubview(folding)
        root.addArrangedSubview(debug)
        addRule(root)
        root.addArrangedSubview(note("Uses one desktop snapshot per close. The effect follows the lid in both directions and only covers the built-in display."))
        permissionButton.target = self
        permissionButton.action = #selector(requestPermission)
        let reset = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        let preview = NSButton(title: "Preview…", target: self, action: #selector(showPreview))
        root.addArrangedSubview(horizontal([permissionButton, preview, reset], spacing: 10))
        let desktopTest = NSButton(title: "Test Desktop…", target: self, action: #selector(showDesktopPreview))
        root.addArrangedSubview(horizontal([desktopTest], spacing: 10))
        for view in root.arrangedSubviews { view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        content.layoutSubtreeIfNeeded()
        window?.setContentSize(NSSize(width: 500, height: root.fittingSize.height + 52))
    }

    private func stack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let result = NSStackView(views: views)
        result.orientation = .vertical
        result.alignment = .leading
        result.spacing = spacing
        return result
    }

    private func horizontal(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let result = NSStackView(views: views)
        result.orientation = .horizontal
        result.alignment = .centerY
        result.spacing = spacing
        return result
    }

    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func addRule(_ root: NSStackView) {
        let rule = NSBox()
        rule.boxType = .separator
        root.addArrangedSubview(rule)
    }

    private func sliderRow(_ id: String, title: String, range: ClosedRange<Double>) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.widthAnchor.constraint(equalToConstant: 112).isActive = true
        let slider = NSSlider(value: 0, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: self, action: #selector(sliderChanged(_:)))
        slider.identifier = NSUserInterfaceItemIdentifier(id)
        slider.isContinuous = true
        slider.setAccessibilityLabel(title)
        slider.widthAnchor.constraint(equalToConstant: 236).isActive = true
        let value = NSTextField(labelWithString: "")
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        value.textColor = .secondaryLabelColor
        value.alignment = .right
        value.widthAnchor.constraint(equalToConstant: 64).isActive = true
        sliders[id] = slider
        values[id] = value
        return horizontal([label, slider, value], spacing: 12)
    }

    func refresh() {
        let config = controller.settings.configuration
        angleLabel.stringValue = controller.angle.map { String(format: "%.0f°", $0) } ?? "—°"
        statusLabel.stringValue = controller.status
        enable.state = config.enabled ? .on : .off
        fold.state = config.fold ? .on : .off
        debug.state = config.showDebug ? .on : .off
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastLoginCheck > 3 {
            cachedLoginStatus = SMAppService.mainApp.status
            lastLoginCheck = now
        }
        let loginStatus = cachedLoginStatus
        login.state = (loginStatus == .enabled || loginStatus == .requiresApproval) ? .on : .off
        loginNote.stringValue = loginStatus == .requiresApproval
            ? "Approve MacFold in System Settings → General → Login Items."
            : "Launch at login starts MacFold quietly in the menu bar."
        let numbers = ["start": config.startAngle, "end": config.endAngle, "blur": config.blur,
                       "darkening": config.darkening, "perspective": config.perspective, "compression": config.compression]
        sliders["end"]?.maxValue = config.startAngle - 5
        for (id, number) in numbers {
            sliders[id]?.doubleValue = number
            values[id]?.stringValue = (id == "start" || id == "end") ? String(format: "%.0f°", number)
                : id == "blur" ? String(format: "%.0f pt", number) : String(format: "%.0f%%", number * 100)
        }
        sliders["perspective"]?.isEnabled = config.fold
        sliders["compression"]?.isEnabled = config.fold
        permissionButton.title = controller.hasCapturePermission ? "Screen Recording ✓" : "Allow Screen Recording…"
    }

    @objc private func toggleEnabled() { controller.settings.update { $0.enabled = enable.state == .on }; refresh() }
    @objc private func toggleFold() { controller.settings.update { $0.fold = fold.state == .on }; refresh() }
    @objc private func toggleDebug() { controller.settings.update { $0.showDebug = debug.state == .on }; refresh() }
    @objc private func restoreDefaults() { controller.settings.configuration = FoldConfiguration(); refresh() }
    @objc private func sliderChanged(_ sender: NSSlider) {
        let value = sender.doubleValue
        controller.settings.update {
            switch sender.identifier?.rawValue {
            case "start": $0.startAngle = value.rounded()
            case "end": $0.endAngle = value.rounded()
            case "blur": $0.blur = value.rounded()
            case "darkening": $0.darkening = value
            case "perspective": $0.perspective = value
            case "compression": $0.compression = value
            default: break
            }
        }
        refresh()
    }

    @objc private func toggleLogin() {
        do {
            if login.state == .on {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } else { try SMAppService.mainApp.unregister() }
        } catch { showError("Couldn’t update launch at login", error: error) }
        lastLoginCheck = -.infinity
        refresh()
    }

    @objc private func requestPermission() {
        if !CGPreflightScreenCaptureAccess() {
            if !CGRequestScreenCaptureAccess() {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
        }
        controller.refreshPermission()
        refresh()
    }

    private var previewWindow: PreviewWindowController?
    private var desktopPreviewWindow: DesktopPreviewWindowController?
    @objc private func showDesktopPreview() {
        if desktopPreviewWindow == nil { desktopPreviewWindow = DesktopPreviewWindowController(controller: controller) }
        desktopPreviewWindow?.present()
    }
    @objc private func showPreview() {
        do {
            if previewWindow == nil { previewWindow = try PreviewWindowController(settings: controller.settings) }
            previewWindow?.present()
        } catch { showError("Couldn’t open preview", error: error) }
    }

    private func showError(_ title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        if let window { alert.beginSheetModal(for: window) }
    }
}
