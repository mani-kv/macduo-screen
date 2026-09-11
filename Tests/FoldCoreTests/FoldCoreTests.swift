import Testing
@testable import FoldCore

struct FoldCoreTests {
    @Test func duoLookPreservesUserThresholdsAndControls() {
        var config = FoldConfiguration()
        config.startAngle = 57
        config.endAngle = 0
        config.enabled = false
        config.showDebug = true
        config.applyDuoLook()
        #expect(config.startAngle == 57 && config.endAngle == 0)
        #expect(config.enabled == false && config.showDebug == true)
        #expect(config.fold && config.blur > 0 && config.darkening < 0.5)
        #expect(config == config.validated())
    }
    @Test func crossingStartDoesNotJumpToClosed() {
        for start in [57.0, 88.0, 90.0] {
            var config = FoldConfiguration()
            config.startAngle = start
            config.endAngle = 0
            var session = FoldSession()
            #expect(session.update(progress: config.progress(for: start), allowed: true) == .none)
            let firstProgress = config.progress(for: start - 1)
            #expect(firstProgress > 0 && firstProgress < 0.02)
            guard case .capture(let token) = session.update(progress: firstProgress, allowed: true) else {
                Issue.record("Expected capture at first degree below start"); return
            }
            #expect(session.completeCapture(token, succeeded: true) == true)
            #expect(session.state == .folding)
            #expect(session.progress == firstProgress)
            for fraction in [0.25, 0.5, 0.75] {
                #expect(session.update(progress: config.progress(for: start * (1 - fraction)), allowed: true) == .render)
                #expect(session.state == .folding)
                #expect(session.progress == fraction)
            }
            #expect(session.update(progress: config.progress(for: 0), allowed: true) == .render)
            #expect(session.state == .closed)
        }
    }
    @Test func renderingFailureStopsAndCanRecoverAfterReopening() {
        var session = FoldSession()
        guard case .capture(let token) = session.update(progress: 0.5, allowed: true) else {
            Issue.record("Expected a capture request"); return
        }
        #expect(session.completeCapture(token, succeeded: true) == true)
        session.failRendering()
        #expect(session.state == .blocked)
        #expect(session.update(progress: 0.7, allowed: true) == .none)
        #expect(session.update(progress: 0, allowed: true) == .hide)
        guard case .capture = session.update(progress: 0.2, allowed: true) else {
            Issue.record("Reopening should allow another attempt"); return
        }
    }
    @Test func testProgressClampsAndReversesWithoutTime() {
        let config = FoldConfiguration()
        #expect(config.progress(for: 118) == 0)
        #expect(config.progress(for: 90) == 0)
        #expect(config.progress(for: 47.5) == 0.5)
        #expect(config.progress(for: 5) == 1)
        #expect(config.progress(for: 0) == 1)
        #expect(config.progress(for: 47.5) == 0.5)
        #expect(config.progress(for: .nan) == 0)
    }

    @Test func testInvalidSettingsKeepThresholdsSeparated() {
        var config = FoldConfiguration()
        config.startAngle = 0
        config.endAngle = 200
        config.blur = .infinity
        config.compression = 10
        let safe = config.validated()
        #expect(safe.startAngle == 15)
        #expect(safe.endAngle == 10)
        #expect(safe.blur == 24)
        #expect(safe.compression == 0.95)
        #expect(safe.progress(for: 12.5) == 0.5)
    }

    @Test func testReopenBeforeCaptureCompletesNeverShowsOverlay() {
        var session = FoldSession()
        guard case .capture(let token) = session.update(progress: 0.2, allowed: true) else { Issue.record("Expected a capture request"); return }
        #expect(session.update(progress: 0, allowed: true) == .hide)
        #expect(session.completeCapture(token, succeeded: true) == false)
        #expect(session.state == .idle)
    }

    @Test func testRapidRecloseRejectsEarlierCapture() {
        var session = FoldSession()
        guard case .capture(let old) = session.update(progress: 0.2, allowed: true) else { Issue.record("Expected a capture request"); return }
        _ = session.update(progress: 0, allowed: true)
        guard case .capture(let new) = session.update(progress: 0.4, allowed: true) else { Issue.record("Expected a capture request"); return }
        #expect(session.completeCapture(old, succeeded: true) == false)
        #expect(session.completeCapture(new, succeeded: true) == true)
        #expect(session.progress == 0.4)
    }

    @Test func testStationaryLidDoesNotKeepRendering() {
        var session = FoldSession()
        guard case .capture(let token) = session.update(progress: 0.6, allowed: true) else { Issue.record("Expected a capture request"); return }
        #expect(session.completeCapture(token, succeeded: true) == true)
        for _ in 0..<60 { #expect(session.update(progress: 0.6, allowed: true) == .none) }
        #expect(session.update(progress: 0.4, allowed: true) == .render)
        #expect(session.progress == 0.4)
        #expect(session.update(progress: 1, allowed: true) == .render)
        #expect(session.state == .closed)
    }

    @Test func testDisableAndSleepInvalidateCapture() {
        for disable in [true, false] {
            var session = FoldSession()
            guard case .capture(let token) = session.update(progress: 0.7, allowed: true) else { Issue.record("Expected a capture request"); return }
            if disable { _ = session.update(progress: 0.7, allowed: false) } else { session.reset() }
            #expect(session.completeCapture(token, succeeded: true) == false)
            #expect(session.progress == 0)
        }
    }

    @Test func testCaptureFailureDoesNotRetryEveryReading() {
        var session = FoldSession()
        guard case .capture(let token) = session.update(progress: 0.2, allowed: true) else { Issue.record("Expected a capture request"); return }
        #expect(session.completeCapture(token, succeeded: false) == false)
        #expect(session.state == .blocked)
        #expect(session.update(progress: 0.7, allowed: true) == .none)
        _ = session.update(progress: 0, allowed: true)
        guard case .capture = session.update(progress: 0.1, allowed: true) else { Issue.record("Should retry after reopening"); return }
    }
}
