import AppKit
import FoldCore
import LidSensor

@MainActor
final class FoldController {
    let settings: SettingsStore
    private let sensor: LidAngleProvider
    private let capture: DesktopCapturing
    private var overlay: OverlayWindow?
    private var rendererFailure: String?
    private var pendingFrame = false
    private var failedFrames = 0
    private var session = FoldSession()
    private var captureTask: Task<Void, Never>?
    private var watchdog: Timer?
    private var lastReading: TimeInterval = 0
    private var suspended = false
    private var observers: [NSObjectProtocol] = []
    private var permission = CGPreflightScreenCaptureAccess()
    private var lastPermissionCheck: TimeInterval = 0
    private(set) var angle: Double?
    private var previewAngle: Double?
    private(set) var status = "Connecting to lid sensor…"
    var onStatus: (() -> Void)?
    var progress: Double { session.progress }
    var hasCapturePermission: Bool { permission }

    /// Exercises the same capture, session, and fullscreen renderer as the
    /// sensor, without changing the user's thresholds or moving the lid.
    func setDesktopPreview(angle degrees: Double?) {
        if (previewAngle == nil) != (degrees == nil) { reset() }
        previewAngle = degrees
        if let degrees = previewAngle ?? angle { apply(degrees) }
        onStatus?()
    }

    init(settings: SettingsStore, sensor: LidAngleProvider = HIDAngleProvider(),
         capture: DesktopCapturing = ScreenCaptureService()) {
        self.settings = settings
        self.sensor = sensor
        self.capture = capture
        sensor.onReading = { [weak self] reading in
            MainActor.assumeIsolated { self?.receive(reading) }
        }
        sensor.onError = { [weak self] message in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reset()
                self.angle = nil
                self.status = message
                self.onStatus?()
            }
        }
        settings.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
    }

    func start() {
        // Warm the GPU pipeline at launch, so shader compilation never delays
        // the first physical closing gesture.
        do { overlay = try OverlayWindow(renderer: MetalRenderer()) }
        catch { rendererFailure = error.localizedDescription }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.desktopChanged() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.desktopChanged() }
        })
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.angle != nil,
                      ProcessInfo.processInfo.systemUptime - self.lastReading > 0.5 else { return }
                self.reset()
                self.angle = nil
                self.status = "Waiting for a fresh lid reading…"
                self.onStatus?()
            }
        }
        settingsChanged()
    }

    func stop() {
        sensor.stop()
        watchdog?.invalidate()
        watchdog = nil
        reset()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    func refreshPermission() {
        permission = CGPreflightScreenCaptureAccess()
        lastPermissionCheck = ProcessInfo.processInfo.systemUptime
        reset()
        if let angle = previewAngle ?? angle { apply(angle) }
        onStatus?()
    }

    func retry() {
        reset()
        sensor.stop()
        angle = nil
        status = "Connecting to lid sensor…"
        if settings.configuration.enabled, !suspended { sensor.start() }
        onStatus?()
    }

    private func settingsChanged() {
        if settings.configuration.enabled, !suspended {
            sensor.start()
            if let angle = previewAngle ?? angle {
                apply(angle)
                if session.state == .folding || session.state == .closed {
                    renderFrame(angle: angle)
                }
            }
        } else {
            sensor.stop()
            reset()
            angle = nil
            status = suspended ? "Paused while the display sleeps" : "Effect paused"
        }
        onStatus?()
    }

    private func receive(_ reading: LidReading) {
        guard !suspended, settings.configuration.enabled else { return }
        lastReading = reading.timestamp
        angle = reading.angle
        // The confirmed hardware resolves whole degrees. Direct mapping avoids
        // a low-pass filter continuing to move after the physical lid stops.
        if reading.timestamp - lastPermissionCheck > 2 {
            let granted = CGPreflightScreenCaptureAccess()
            if granted != permission { reset() }
            permission = granted
            lastPermissionCheck = reading.timestamp
        }
        apply(previewAngle ?? reading.angle)
        onStatus?()
    }

    private func apply(_ angle: Double) {
        guard settings.configuration.enabled, !suspended else { return }
        if let rendererFailure {
            reset()
            status = rendererFailure
            return
        }
        guard NSScreen.builtIn != nil else {
            reset()
            status = "Waiting for the built-in display"
            return
        }
        guard permission else {
            reset()
            status = "Screen Recording permission needed"
            return
        }
        let action = session.update(progress: settings.configuration.progress(for: angle), allowed: true)
        switch action {
        case .hide:
            cancelCapture()
            overlay?.hide()
            pendingFrame = false
            failedFrames = 0
        case .capture(let token): beginCapture(token: token)
        case .render: renderFrame(angle: angle)
        case .none:
            if pendingFrame, session.state == .folding || session.state == .closed { renderFrame(angle: angle) }
        }
        switch session.state {
        case .idle: status = "Ready when you close the lid"
        case .capturing: status = "Preparing desktop snapshot…"
        case .folding: status = pendingFrame ? "Waiting for the display…" : String(format: "Following the lid · %.0f%%", session.progress * 100)
        case .closed: status = pendingFrame ? "Waiting for the display…" : "Lid almost closed"
        case .blocked: break
        }
    }

    private func beginCapture(token: Int) {
        guard let screen = NSScreen.builtIn, let displayID = screen.displayID else { reset(); return }
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await self.capture.capture(displayID: displayID)
                try Task.checkCancellation()
                guard token == self.session.generation, self.session.state == .capturing,
                      let current = NSScreen.builtIn, current.displayID == displayID,
                      let angle = self.previewAngle ?? self.angle else { return }
                try self.overlay?.prepare(image: image, screen: current)
                guard self.session.completeCapture(token, succeeded: true) else { return }
                self.renderFrame(angle: angle)
                if self.session.state != .blocked {
                    self.status = self.pendingFrame ? "Waiting for the display…" : String(format: "Following the lid · %.0f%%", self.session.progress * 100)
                }
                self.onStatus?()
            } catch is CancellationError {
                // A newer lid state already invalidated this capture.
            } catch {
                guard token == self.session.generation else { return }
                _ = self.session.completeCapture(token, succeeded: false)
                self.overlay?.hide()
                self.status = error.localizedDescription
                self.onStatus?()
            }
        }
    }

    private func cancelCapture() { captureTask?.cancel(); captureTask = nil }
    private func reset() { session.reset(); cancelCapture(); overlay?.hide(); pendingFrame = false; failedFrames = 0 }

    private func desktopChanged() {
        // Discard the previous Space's image and any in-flight capture, then
        // restore the effect without waiting for another sensor/slider event.
        reset()
        if let angle = previewAngle ?? angle { apply(angle) }
        onStatus?()
    }

    private func renderFrame(angle: Double) {
        if overlay?.render(angle: angle, progress: session.progress, configuration: settings.configuration) == true {
            pendingFrame = false
            failedFrames = 0
        } else {
            failedFrames += 1
            pendingFrame = failedFrames < 3
            if !pendingFrame {
                session.failRendering()
                overlay?.hide()
                status = overlay?.lastError.map { "Couldn’t draw the effect: \($0)" }
                    ?? "Couldn’t draw the effect. Reopen the lid or choose Reconnect sensor."
            }
        }
    }
    private func suspend() { suspended = true; sensor.stop(); reset(); angle = nil; status = "Paused while the display sleeps"; onStatus?() }
    private func resume() { suspended = false; reset(); angle = nil; settingsChanged() }
}
