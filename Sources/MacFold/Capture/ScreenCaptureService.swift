import AppKit
import ScreenCaptureKit

protocol DesktopCapturing {
    func capture(displayID: CGDirectDisplayID) async throws -> CGImage
}

enum CaptureError: LocalizedError {
    case permissionRequired, displayUnavailable
    var errorDescription: String? {
        switch self {
        case .permissionRequired: return "Allow Screen Recording in Settings to blur the desktop."
        case .displayUnavailable: return "The built-in display is unavailable."
        }
    }
}

struct ScreenCaptureService: DesktopCapturing {
    func capture(displayID: CGDirectDisplayID) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.permissionRequired }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayUnavailable
        }
        // Excluding our windows also prevents feedback if a display changes
        // while an older snapshot is still being released.
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let configuration = SCStreamConfiguration()
        configuration.width = CGDisplayPixelsWide(displayID)
        configuration.height = CGDisplayPixelsHigh(displayID)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try Task.checkCancellation()
        return image
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static var builtIn: NSScreen? {
        screens.first { $0.displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false }
    }
}
