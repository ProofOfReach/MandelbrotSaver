import ScreenSaver
import Metal
import MetalKit
import simd

// MARK: - Double Precision Extension for Shader Communication
extension Double {
    /// Encodes a Double as two Floats (hi, lo) for transmission to Metal shaders.
    /// The shader reconstructs: Double(hi) + Double(lo) with full precision.
    var asFloatPair: (hi: Float, lo: Float) {
        let hi = Float(self)
        let lo = Float(self - Double(hi))
        return (hi, lo)
    }
}

@objc(MandelbrotView)
class MandelbrotView: ScreenSaverView, MTKViewDelegate {

    // MARK: - Metal Properties
    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var computePipeline: MTLComputePipelineState?
    private var outputTexture: MTLTexture?

    // MARK: - P3 Wide Gamut Rendering
    private var mtkView: MTKView?
    private var renderPipeline: MTLRenderPipelineState?

    // MARK: - Configuration Sheet
    private lazy var configureSheetController = ConfigureSheetController()

    // MARK: - Transition State for Smooth Fades
    private enum TransitionState {
        case zooming
        case fadingOut
        case fadingIn
    }
    private var transitionState: TransitionState = .zooming
    private var transitionOpacity: Float = 1.0
    private let fadeSpeed: Float = 0.02

    // MARK: - Zoom State (using Double for precision)
    private var centerX: Double = -0.5
    private var centerY: Double = 0.0
    private var scale: Double = 3.0

    // Target for smooth animation
    private var targetCenterX: Double = -0.5
    private var targetCenterY: Double = 0.0
    private var targetScale: Double = 1e-13

    // Animation parameters (loaded from preferences)
    private var zoomSpeed: Double = 0.990
    private let panSpeed: Double = 0.015

    // Visual effects (partially loaded from preferences)
    private var colorOffset: Float = 0.0
    private var currentPalette: Int = 0
    private var paletteMix: Float = 0.0
    private var paletteTimer: Float = 0.0
    private var shadingMode: Int = 0
    private var shadingTimer: Float = 0.0
    private var time: Float = 0.0
    private var autoCyclePalettes: Bool = true

    // Palette names for reference (24 palettes total)
    private let paletteNames = [
        "Ultra", "Fire", "Ocean", "Electric", "Sunset", "Glacial",
        "Rainbow", "Plasma", "Lava", "Forest", "Midnight", "Aurora",
        "Copper", "Emerald", "Amethyst", "Gold", "Silver", "Bronze",
        "Neon", "Vapor", "Thermal", "Spectrum", "Monochrome", "Candy"
    ]

    // MARK: - Julia Set Mode
    private var juliaEnabled: Bool = false  // Preference: allow Julia sets?
    private var juliaMode: Bool = false     // Current state: showing Julia?
    private var juliaCx: Double = 0.0
    private var juliaCy: Double = 0.0

    // Interesting Julia c values for visually striking fractals
    private let interestingJuliaC: [(cx: Double, cy: Double, name: String)] = [
        (-0.7, 0.27015, "Classic Spiral"),
        (-0.4, 0.6, "Dendrite"),
        (0.285, 0.01, "Snail Shell"),
        (-0.8, 0.156, "Rabbit"),
        (-0.70176, -0.3842, "Dragon"),
        (0.285, 0.535, "Galaxy"),
        (-0.835, -0.2321, "Lightning"),
        (-0.1, 0.651, "Seahorse Tail"),
        (-0.74543, 0.11301, "Seahorse Julia"),
        (0.0, -0.8, "San Marco"),
        (-1.476, 0.0, "Cauliflower"),
        (-0.12, -0.77, "Starfish"),
        (0.28, 0.008, "Siegel Disk"),
        (-0.194, 0.6557, "Pinwheel"),
        (-0.12, 0.74, "Spiral Galaxy"),
        (0.3, 0.5, "Feathers")
    ]

    // =========================================================================
    // INTERESTING ZOOM TARGETS - Curated beautiful locations only
    // Reset 15% earlier (1e-5) to stay crisp
    // =========================================================================
    private let interestingPoints: [(x: Double, y: Double, minScale: Double, name: String)] = [
        // Classic spirals - always beautiful
        (-0.74529, 0.113075, 1e-5, "Seahorse Valley"),
        (-1.25066, 0.02012, 1e-5, "Elephant Valley"),
        (0.360240443437614, -0.641313061064803, 1e-5, "Triple Spiral"),

        // Mini-Mandelbrots - guaranteed beautiful
        (-1.401155, 0.0, 1e-5, "Western Mini"),
        (-0.761574, -0.0847596, 1e-5, "Mini at Period-3"),

        // Seahorse details
        (-0.745289, 0.113075, 1e-5, "Seahorse Detail"),
        (-0.75, 0.1, 1e-5, "Classic Seahorse"),

        // Clean spirals
        (-0.235125, 0.827215, 1e-5, "Julia Spiral"),
    ]

    private var currentTargetIndex: Int = 0
    private var lastTextureSize: CGSize = .zero
    private var zoomCount: Int = 0

    // MARK: - Initialization

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        loadPreferences()
        setupMetal()
        selectRandomTarget()
        self.animationTimeInterval = 1.0 / 60.0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadPreferences()
        setupMetal()
        selectRandomTarget()
        self.animationTimeInterval = 1.0 / 60.0
    }

    /// Load preferences from ScreenSaverDefaults
    private func loadPreferences() {
        let prefs = Preferences.shared
        zoomSpeed = prefs.zoomSpeed
        currentPalette = prefs.paletteIndex
        autoCyclePalettes = prefs.autoCyclePalettes
        shadingMode = prefs.shadingMode
        juliaEnabled = prefs.juliaMode
    }

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            NSLog("MandelbrotSaver: Failed to create Metal device")
            return
        }
        metalDevice = device
        commandQueue = device.makeCommandQueue()

        // Load the shader library from the bundle
        let bundle = Bundle(for: type(of: self))
        guard let libraryURL = bundle.url(forResource: "default", withExtension: "metallib"),
              let library = try? device.makeLibrary(URL: libraryURL) else {
            NSLog("MandelbrotSaver: Failed to load Metal library")
            return
        }

        guard let kernelFunction = library.makeFunction(name: "mandelbrotKernel") else {
            NSLog("MandelbrotSaver: Failed to find kernel function")
            return
        }

        do {
            computePipeline = try device.makeComputePipelineState(function: kernelFunction)
        } catch {
            NSLog("MandelbrotSaver: Failed to create compute pipeline: \(error)")
        }

        // Setup MTKView for P3 Wide Gamut rendering
        setupMTKView(device: device, library: library)
    }

    private func setupMTKView(device: MTLDevice, library: MTLLibrary) {
        // Create MTKView as subview for P3 wide gamut rendering
        // Use a reasonable initial frame if bounds is zero
        var initialFrame = bounds
        if initialFrame.width < 1 || initialFrame.height < 1 {
            initialFrame = NSRect(x: 0, y: 0, width: 800, height: 600)
        }

        let view = MTKView(frame: initialFrame, device: device)
        view.autoresizingMask = [.width, .height]
        view.isPaused = true  // We control rendering via animateOneFrame
        view.enableSetNeedsDisplay = false

        // Configure for P3 Wide Gamut with 16-bit float precision
        view.colorPixelFormat = .rgba16Float
        view.colorspace = CGColorSpace(name: CGColorSpace.displayP3)

        // Set clear color to dark blue so we can see if view is rendering
        view.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.1, alpha: 1.0)

        // Disable depth/stencil - not needed for 2D fractal
        view.depthStencilPixelFormat = .invalid

        // Layer-backed for better compositing
        view.wantsLayer = true
        view.layer?.isOpaque = true

        view.delegate = self
        addSubview(view)
        mtkView = view

        // Create render pipeline for blitting compute texture to screen
        guard let vertexFunction = library.makeFunction(name: "blitVertex"),
              let fragmentFunction = library.makeFunction(name: "blitFragment") else {
            NSLog("MandelbrotSaver: Blit shaders not found, using fallback rendering")
            return
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba16Float

        do {
            renderPipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            NSLog("MandelbrotSaver: Failed to create render pipeline: \(error)")
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Texture will be recreated on next frame
        lastTextureSize = .zero
    }

    func draw(in view: MTKView) {
        renderFrame()
    }

    private func createTextureIfNeeded() {
        let size = bounds.size
        guard size.width > 0 && size.height > 0 else { return }

        if size == lastTextureSize && outputTexture != nil { return }
        lastTextureSize = size

        guard let device = metalDevice else { return }

        // Use rgba16Float for P3 wide gamut color support (values > 1.0)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        descriptor.usage = [.shaderWrite, .shaderRead]
        outputTexture = device.makeTexture(descriptor: descriptor)
    }

    // MARK: - Auto-Pilot

    private func selectRandomTarget() {
        // Avoid repeating the same target
        var newIndex: Int
        repeat {
            newIndex = Int.random(in: 0..<interestingPoints.count)
        } while newIndex == currentTargetIndex && interestingPoints.count > 1

        currentTargetIndex = newIndex
        let target = interestingPoints[currentTargetIndex]
        targetCenterX = target.x
        targetCenterY = target.y
        targetScale = target.minScale

        // Reset to initial view
        centerX = -0.5
        centerY = 0.0
        scale = 3.0

        zoomCount += 1

        // Alternate between Mandelbrot and Julia every 4 zooms (if Julia enabled)
        if juliaEnabled && zoomCount % 4 == 0 {
            juliaMode = !juliaMode
            if juliaMode {
                // Select a random interesting Julia c value
                let juliaIndex = Int.random(in: 0..<interestingJuliaC.count)
                let juliaC = interestingJuliaC[juliaIndex]
                juliaCx = juliaC.cx
                juliaCy = juliaC.cy
                // For Julia sets, we start centered at origin
                centerX = 0.0
                centerY = 0.0
                targetCenterX = 0.0
                targetCenterY = 0.0
                targetScale = 3e-5  // Julia sets don't need as deep zoom
            }
        } else if !juliaEnabled {
            juliaMode = false  // Ensure Julia is off if disabled
        }

        // Change shading mode every few zooms
        if zoomCount % 3 == 0 {
            shadingMode = (shadingMode + 1) % 4
        }
    }

    private func updateAnimation() {
        // Handle transition state machine for smooth fades
        switch transitionState {
        case .zooming:
            // Exponential zoom
            scale *= zoomSpeed

            // Smooth pan toward target using ease-out
            let dx = targetCenterX - centerX
            let dy = targetCenterY - centerY
            centerX += dx * panSpeed
            centerY += dy * panSpeed

            // When we've zoomed deep enough, start fading out
            if scale < targetScale * 2.0 {
                transitionState = .fadingOut
            }

        case .fadingOut:
            // Fade to black
            transitionOpacity -= fadeSpeed
            if transitionOpacity <= 0.0 {
                transitionOpacity = 0.0
                // Select new target while screen is black
                selectRandomTarget()
                transitionState = .fadingIn
            }

        case .fadingIn:
            // Fade back in
            transitionOpacity += fadeSpeed
            if transitionOpacity >= 1.0 {
                transitionOpacity = 1.0
                transitionState = .zooming
            }
        }

        // Cycle colors
        colorOffset += 0.3
        if colorOffset > 10000.0 {
            colorOffset = 0.0
        }

        // Slowly transition between palettes (if auto-cycle is enabled)
        if autoCyclePalettes {
            paletteTimer += 0.001
            if paletteTimer >= 1.0 {
                paletteTimer = 0.0
                currentPalette = (currentPalette + 1) % paletteNames.count
            }
            paletteMix = paletteTimer
        } else {
            paletteMix = 0.0  // No transition when not auto-cycling
        }

        // Reload preferences periodically to pick up config changes
        if Int(time * 1000) % 1000 == 0 {
            loadPreferences()
        }

        // Increment time for animated shading effects
        time += 0.016
    }

    // MARK: - Rendering

    override func draw(_ rect: NSRect) {
        // Fill background black in case MTKView fails
        NSColor.black.setFill()
        rect.fill()

        // If MTKView isn't set up, try fallback rendering
        if mtkView == nil {
            renderFrameFallback()
        }
    }

    /// Main rendering function - called from MTKViewDelegate
    private func renderFrame() {
        createTextureIfNeeded()

        guard let commandQueue = commandQueue,
              let pipeline = computePipeline,
              let texture = outputTexture,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        // Smart auto-iteration: more iterations when zoomed deep
        // With double-double precision, we can support 10^15 zoom
        let zoomDepth = log10(3.0 / scale)
        let maxIterations: Float = min(Float(zoomDepth * 80 + 200), 5000)

        // Split center coordinates into hi/lo parts for double-double precision
        // Using the asFloatPair extension for clean encoding
        let centerXPair = centerX.asFloatPair
        let centerYPair = centerY.asFloatPair

        // Pack parameters
        var params = simd_float4(
            centerXPair.hi,
            centerYPair.hi,
            Float(scale),
            maxIterations
        )

        let aspectRatio = Float(bounds.width / bounds.height)
        var params2 = simd_float4(
            colorOffset,
            aspectRatio,
            Float(currentPalette),
            paletteMix
        )

        var params3 = simd_float4(
            centerXPair.lo,
            centerYPair.lo,
            Float(shadingMode),
            time
        )

        // params4: opacity (x), juliaMode flag (y), juliaCx (z), juliaCy (w)
        var params4 = simd_float4(
            transitionOpacity,
            juliaMode ? 1.0 : 0.0,
            Float(juliaCx),
            Float(juliaCy)
        )

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<simd_float4>.size, index: 0)
        encoder.setBytes(&params2, length: MemoryLayout<simd_float4>.size, index: 1)
        encoder.setBytes(&params3, length: MemoryLayout<simd_float4>.size, index: 2)
        encoder.setBytes(&params4, length: MemoryLayout<simd_float4>.size, index: 3)

        // Dispatch threads
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (texture.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (texture.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()

        // Render to MTKView for P3 Wide Gamut display
        if let mtkView = mtkView,
           let drawable = mtkView.currentDrawable,
           let renderPipeline = renderPipeline,
           let renderPassDescriptor = mtkView.currentRenderPassDescriptor,
           let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {

            renderEncoder.setRenderPipelineState(renderPipeline)
            renderEncoder.setFragmentTexture(texture, index: 0)
            // Draw fullscreen quad (6 vertices for 2 triangles)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            renderEncoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
            // Don't wait - async GPU rendering for better performance
        } else {
            // Fallback: render without P3
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            drawTextureToViewFallback(texture)
        }
    }

    /// Fallback rendering when MTKView isn't available
    private func renderFrameFallback() {
        createTextureIfNeeded()

        guard let commandQueue = commandQueue,
              let pipeline = computePipeline,
              let texture = outputTexture,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        let zoomDepth = log10(3.0 / scale)
        let maxIterations: Float = min(Float(zoomDepth * 80 + 200), 5000)
        let centerXPair = centerX.asFloatPair
        let centerYPair = centerY.asFloatPair

        var params = simd_float4(centerXPair.hi, centerYPair.hi, Float(scale), maxIterations)
        let aspectRatio = Float(bounds.width / bounds.height)
        var params2 = simd_float4(colorOffset, aspectRatio, Float(currentPalette), paletteMix)
        var params3 = simd_float4(centerXPair.lo, centerYPair.lo, Float(shadingMode), time)
        var params4 = simd_float4(transitionOpacity, juliaMode ? 1.0 : 0.0, Float(juliaCx), Float(juliaCy))

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<simd_float4>.size, index: 0)
        encoder.setBytes(&params2, length: MemoryLayout<simd_float4>.size, index: 1)
        encoder.setBytes(&params3, length: MemoryLayout<simd_float4>.size, index: 2)
        encoder.setBytes(&params4, length: MemoryLayout<simd_float4>.size, index: 3)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (texture.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (texture.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        drawTextureToViewFallback(texture)
    }

    /// Fallback rendering when MTKView is not available
    private func drawTextureToViewFallback(_ texture: MTLTexture) {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 8  // 16-bit float RGBA = 8 bytes per pixel

        var pixels = [Float16](repeating: 0, count: width * height * 4)
        texture.getBytes(
            &pixels,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                           size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0
        )

        // Convert to 8-bit for CGImage (loses P3 extended range)
        var pixels8 = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height * 4) {
            let val = Float(pixels[i])
            pixels8[i] = UInt8(max(0, min(255, val * 255.0)))
        }

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let dataProvider = CGDataProvider(data: Data(pixels8) as CFData) else { return }

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return }

        // Flip vertically since Metal texture origin is top-left
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: bounds)
        context.restoreGState()
    }

    // MARK: - Animation

    override func animateOneFrame() {
        updateAnimation()

        // Primary rendering path: use MTKView for P3 wide gamut
        if let mtkView = mtkView {
            mtkView.draw()
        } else {
            // Fallback if MTKView not available
            setNeedsDisplay(bounds)
        }
    }

    // MARK: - Configuration Sheet

    override var hasConfigureSheet: Bool {
        return true
    }

    override var configureSheet: NSWindow? {
        return configureSheetController.configureSheet()
    }
}
