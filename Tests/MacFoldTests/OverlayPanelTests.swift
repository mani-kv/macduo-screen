import AppKit
import Testing
@testable import MacFold

@MainActor
struct OverlayPanelTests {
    @Test func overlayCanJoinOtherSpacesWithoutActivatingTheApp() {
        _ = NSApplication.shared
        let panel: NSWindow = PassiveOverlayPanel()
        defer { panel.close() }

        // The nonactivating style only has its documented effect on NSPanel.
        // Joining Spaces alone does not make an ordinary NSWindow passive.
        #expect(panel is NSPanel)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect((panel as? NSPanel)?.isFloatingPanel == true)
        #expect(!panel.canBecomeKey && !panel.canBecomeMain)
        #expect(!panel.hidesOnDeactivate)
        #expect(panel.ignoresMouseEvents)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.canJoinAllApplications))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(!panel.collectionBehavior.contains(.moveToActiveSpace))
        #expect(panel.level == .screenSaver)
        #expect(!panel.isVisible)
    }
}
