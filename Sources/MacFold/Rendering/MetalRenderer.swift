import AppKit
import MetalKit
import MetalPerformanceShaders
import FoldCore

enum RenderError: LocalizedError {
    case unavailable, shaderMissing, textureUnavailable
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Metal rendering is unavailable on this Mac."
        case .shaderMissing: return "MacFold’s shader resource is missing. Rebuild the app bundle."
        case .textureUnavailable: return "Unable to prepare the desktop image."
        }
    }
}

final class MetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var source: MTLTexture?
    private var blurLevels: [MTLTexture] = []
    private var output: MTLTexture?
    private var lastBlur: Float = -1
    private var frameProgress = 0.0
    private var frameConfiguration = FoldConfiguration()
    private var frameSubmitted = false
    private(set) var lastDrawableID: Int?

    init(metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device = metalDevice, let queue = device.makeCommandQueue() else {
            throw RenderError.unavailable
        }
        self.device = device
        self.queue = queue
        let shaderURL: URL?
        if Bundle.main.bundleURL.pathExtension == "app" {
            // SwiftPM's generated accessor falls back to an absolute build
            // path. A distributed .app must load only its bundled resources.
            shaderURL = Bundle.main.resourceURL?.appendingPathComponent("MacFold_MacFold.bundle/FoldShader.metal")
        } else {
            shaderURL = Bundle.module.url(forResource: "FoldShader", withExtension: "metal")
        }
        guard let url = shaderURL, FileManager.default.fileExists(atPath: url.path) else {
            throw RenderError.shaderMissing
        }
        let library = try device.makeLibrary(source: String(contentsOf: url), options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "foldVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "foldFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        super.init()
    }

    func setImage(_ image: CGImage) throws {
        // ScreenCaptureKit and AppKit can return wide-gamut / extended formats
        // that MTKTextureLoader cannot decode. Normalize once per snapshot.
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let normalized = normalizedImage(image, in: context) else { throw RenderError.textureUnavailable }
        source = try MTKTextureLoader(device: device).newTexture(cgImage: normalized, options: [
            .SRGB: false, .origin: MTKTextureLoader.Origin.topLeft,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
        ])
        guard let source else { throw RenderError.textureUnavailable }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: source.pixelFormat,
                                                                  width: source.width, height: source.height,
                                                                  mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        blurLevels = try (0..<3).map { _ in
            guard let texture = device.makeTexture(descriptor: descriptor) else { throw RenderError.textureUnavailable }
            return texture
        }
        lastBlur = -1
    }

    private func normalizedImage(_ image: CGImage, in context: CGContext) -> CGImage? {
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    func clear() { source = nil; blurLevels = []; output = nil; lastBlur = -1 }

    /// Encodes one frame only when angle/settings change. No display timer or
    /// duration-based animation continues while the lid is stationary.
    @discardableResult
    func draw(in view: MTKView, progress: Double, configuration: FoldConfiguration) -> Bool {
        frameProgress = progress
        frameConfiguration = configuration
        frameSubmitted = false
        view.delegate = self
        // MTKView releases its cached drawable only when its draw callback
        // returns. Reading currentDrawable outside this cycle reuses an already
        // presented frame (or caches a nil drawable from a zero-sized view).
        view.draw()
        return frameSubmitted
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = makeFrame(pass: pass, progress: frameProgress, configuration: frameConfiguration,
                                      scale: Double(view.window?.backingScaleFactor ?? 2)) else { return }
        lastDrawableID = drawable.drawableID
        command.present(drawable)
        command.commit()
        frameSubmitted = true
    }

    func renderOffscreen(width: Int, height: Int, progress: Double, configuration: FoldConfiguration, scale: Double = 1) throws -> CGImage {
        guard width > 0, height > 0 else { throw RenderError.textureUnavailable }
        if output?.width != width || output?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget]
            descriptor.storageMode = .shared
            output = device.makeTexture(descriptor: descriptor)
        }
        guard let texture = output else { throw RenderError.textureUnavailable }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        guard let command = makeFrame(pass: pass, progress: progress, configuration: configuration, scale: scale) else {
            throw RenderError.textureUnavailable
        }
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { lastBlur = -1; throw error }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw RenderError.textureUnavailable
        }
        return image
    }

    private func makeFrame(pass: MTLRenderPassDescriptor, progress: Double,
                           configuration: FoldConfiguration, scale: Double) -> MTLCommandBuffer? {
        guard let source, blurLevels.count == 3, let command = queue.makeCommandBuffer() else { return nil }
        let config = configuration.validated()
        let p = Float(min(1, max(0, progress)))
        let sigma = Float(config.blur * scale)
        // Cache the frost pyramid per snapshot/settings change. Angle changes
        // only resample these levels, avoiding three Gaussian passes per frame.
        if sigma > 0.25, sigma != lastBlur {
            for (index, amount) in [Float(0.20), 0.50, 1.0].enumerated() {
                let blur = MPSImageGaussianBlur(device: device, sigma: max(0.1, sigma * amount))
                blur.edgeMode = .clamp
                blur.encode(commandBuffer: command, sourceTexture: source, destinationTexture: blurLevels[index])
            }
            lastBlur = sigma
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        let uniforms = [SIMD4<Float>(p, config.fold ? Float(config.perspective) : 0,
                                    config.fold ? Float(config.compression) : 0, Float(config.darkening)),
                        SIMD4<Float>(sigma > 0.25 ? 1 : 0, 0, 0, 0)]
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        for index in 0..<3 {
            encoder.setFragmentTexture(sigma > 0.25 ? blurLevels[index] : source, index: index + 1)
        }
        uniforms.withUnsafeBytes { bytes in
            encoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 0)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return command
    }
}
