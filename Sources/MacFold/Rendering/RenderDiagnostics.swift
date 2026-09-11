import AppKit
import FoldCore
import MetalKit

enum RenderDiagnostics {
    /// Exercises the actual MTKView presentation lifecycle. Offscreen textures
    /// cannot catch a view reusing the same already-presented drawable.
    static func checkWindow() throws {
        let renderer = try MetalRenderer()
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = MTKView(frame: .zero, device: renderer.device)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.colorPixelFormat = .bgra8Unorm
        window.contentView = view
        defer { window.orderOut(nil); renderer.clear() }
        var configuration = FoldConfiguration()
        configuration.fold = true
        var previousID: Int?
        var count = 0
        for cycle in 0..<3 {
            // Match the overlay's zero-sized startup, subsequent resize,
            // repeated angle updates, hiding, and reuse for the next gesture.
            let size = NSSize(width: 400 + cycle * 80, height: 260 + cycle * 40)
            window.setFrame(NSRect(origin: NSPoint(x: 40, y: 80), size: size), display: false)
            view.frame = NSRect(origin: .zero, size: size)
            view.drawableSize = NSSize(width: size.width * 2, height: size.height * 2)
            try renderer.setImage(SampleDesktop.image())
            for progress in [0.01, 0.3, 0.7, 1.0, 0.7, 0.3, 0.01] {
                guard renderer.draw(in: view, progress: progress, configuration: configuration),
                      let id = renderer.lastDrawableID, id != previousID else {
                    throw CheckError.failed("MTKView failed to supply a fresh drawable at frame \(count + 1)")
                }
                if !window.isVisible { window.orderFrontRegardless() }
                previousID = id
                count += 1
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.035))
            }
            window.orderOut(nil)
            renderer.clear()
        }
        print("Window check passed: \(count) fresh drawables across closing, reopening, resizing, and window reuse.")
    }

    static func run(directory: String) throws {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let renderer = try MetalRenderer()
        let sample = SampleDesktop.image()
        // A white source isolates the darkness mask from desktop colors.
        // Check the top void, feather gradient, outer side, and open endpoint.
        let whiteContext = CGContext(data: nil, width: 640, height: 400, bitsPerComponent: 8,
                                     bytesPerRow: 640 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        whiteContext.setFillColor(CGColor(gray: 1, alpha: 1))
        whiteContext.fill(CGRect(x: 0, y: 0, width: 640, height: 400))
        try renderer.setImage(whiteContext.makeImage()!)
        var maskConfig = FoldConfiguration()
        maskConfig.applyDuoLook()
        maskConfig.blur = 0
        maskConfig.darkening = 0
        let openMask = try renderer.renderOffscreen(width: 640, height: 400, progress: 0, configuration: maskConfig)
        let mask = try renderer.renderOffscreen(width: 640, height: 400, progress: 0.6, configuration: maskConfig)
        let earlyMask = try renderer.renderOffscreen(width: 640, height: 400, progress: 0.1, configuration: maskConfig)
        func brightness(_ image: CGImage, _ x: Int, _ y: Int) -> UInt8 {
            let data = image.dataProvider!.data!
            return CFDataGetBytePtr(data)![y * image.bytesPerRow + x * 4]
        }
        let earlyFeatherRows = (0..<100).filter {
            let value = brightness(earlyMask, 320, $0)
            return value > 0 && value < 255
        }.count
        guard brightness(openMask, 320, 0) == 255,
              earlyFeatherRows >= 12,
              brightness(mask, 320, 20) == 0,
              brightness(mask, 0, 200) == 0,
              brightness(mask, 320, 90) > 0,
              brightness(mask, 320, 90) < brightness(mask, 320, 120),
              brightness(mask, 320, 120) < brightness(mask, 320, 200),
              brightness(mask, 80, 120) < brightness(mask, 320, 120),
              brightness(mask, 80, 120) == brightness(mask, 559, 120),
              brightness(mask, 320, 200) == 255 else {
            throw CheckError.failed("Darkness mask must preserve open image, black out the void, and feather the top")
        }
        try png(mask).write(to: url.appendingPathComponent("darkness-mask.png"))
        print("Darkness mask check passed: black exterior, broad top feather, rounded symmetric corners, unchanged open endpoint.")
        // Exercise the fullscreen image path at Retina resolution, including
        // large input textures and the physical-pixel blur radius.
        let width = 3456, height = 2234
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(sample, in: CGRect(x: 0, y: 0, width: width, height: height))
        try renderer.setImage(context.makeImage()!)
        var fullConfig = FoldConfiguration()
        fullConfig.blur = 30
        fullConfig.darkening = 0
        fullConfig.fold = false
        let start = ProcessInfo.processInfo.systemUptime
        let sharp = try renderer.renderOffscreen(width: width, height: height, progress: 0, configuration: fullConfig, scale: 2)
        let soft = try renderer.renderOffscreen(width: width, height: height, progress: 0.6, configuration: fullConfig, scale: 2)
        guard png(sharp) != png(soft) else { throw CheckError.failed("Retina blur did not change pixels with dimming disabled") }
        fullConfig.blur = 0
        fullConfig.fold = true
        let folded = try renderer.renderOffscreen(width: width, height: height, progress: 0.6, configuration: fullConfig, scale: 2)
        guard png(sharp) != png(folded) else { throw CheckError.failed("Retina perspective did not change pixels with blur and dimming disabled") }
        try png(soft).write(to: url.appendingPathComponent("retina-blur.png"))
        try png(folded).write(to: url.appendingPathComponent("retina-fold.png"))
        print(String(format: "Retina image check passed: independent blur and fold at %dx%d (%.2fs including PNG checks).", width, height, ProcessInfo.processInfo.systemUptime - start))
        try renderer.setImage(sample)
        var configuration = FoldConfiguration()
        configuration.applyDuoLook()
        var frames: [(String, CGImage)] = []
        for fold in [false, true] {
            configuration.fold = fold
            for angle in [90.0, 60.0, 30.0, 5.0] {
                let frame = try renderer.renderOffscreen(width: 640, height: 400,
                                                         progress: configuration.progress(for: angle), configuration: configuration)
                let name = "\(fold ? "fold" : "blur")-\(Int(angle))"
                try png(frame).write(to: url.appendingPathComponent(name + ".png"))
                frames.append((name, frame))
            }
        }
        // Returning to the same angle must reproduce the same frame, including
        // after fully closing, with no elapsed-time or directional state.
        configuration.fold = true
        let first = try renderer.renderOffscreen(width: 640, height: 400, progress: 0.6, configuration: configuration)
        _ = try renderer.renderOffscreen(width: 640, height: 400, progress: 1, configuration: configuration)
        let reversed = try renderer.renderOffscreen(width: 640, height: 400, progress: 0.6, configuration: configuration)
        guard png(first) == png(reversed) else { throw CheckError.failed("Angle reversal produced different pixels") }
        guard let closed = frames.last?.1.dataProvider?.data, let bytes = CFDataGetBytePtr(closed) else {
            throw CheckError.failed("Cannot inspect closed frame")
        }
        for offset in stride(from: 0, to: CFDataGetLength(closed), by: 4) {
            guard bytes[offset] == 0, bytes[offset + 1] == 0, bytes[offset + 2] == 0 else {
                throw CheckError.failed("Closed frame is not black")
            }
        }
        let sheet = NSImage(size: NSSize(width: 1280, height: 1728), flipped: false) { _ in
            NSColor.windowBackgroundColor.setFill()
            NSRect(x: 0, y: 0, width: 1280, height: 1728).fill()
            for (index, entry) in frames.enumerated() {
                let column = index / 4
                let row = index % 4
                let origin = NSPoint(x: column * 640, y: 1728 - (row + 1) * 432)
                NSImage(cgImage: entry.1, size: NSSize(width: 640, height: 400)).draw(in: NSRect(origin: origin, size: NSSize(width: 640, height: 400)))
                (entry.0 as NSString).draw(at: NSPoint(x: origin.x + 16, y: origin.y + 407), withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor])
            }
            return true
        }
        if let image = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            try png(image).write(to: url.appendingPathComponent("contact-sheet.png"))
        }
        print("Metal check passed: 8 frames, fully black close, exact reverse-angle reproduction. Images: \(url.path)")
    }

    private static func png(_ image: CGImage) -> Data {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    }
    private enum CheckError: LocalizedError {
        case failed(String)
        var errorDescription: String? { if case .failed(let message) = self { return message }; return nil }
    }
}
