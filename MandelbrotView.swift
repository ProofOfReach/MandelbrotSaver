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
    private var computePipelineFloat: MTLComputePipelineState?
    private var computePipelineHighPrecision: MTLComputePipelineState?
    private var computePipelineOrbit: MTLComputePipelineState?
    private var computePipelinePerturbation: MTLComputePipelineState?
    private var outputTexture: MTLTexture?
    private var referenceOrbitBuffer: MTLBuffer?
    private var maxOrbitIterations: Int = 0

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
    private var centerX: DoubleDouble = DoubleDouble(-0.5)
    private var centerY: DoubleDouble = DoubleDouble(0.0)
    private var scale: DoubleDouble = DoubleDouble(3.0)

    // Target for smooth animation
    private var targetCenterX: DoubleDouble = DoubleDouble(-0.5)
    private var targetCenterY: DoubleDouble = DoubleDouble(0.0)
    private var targetScale: DoubleDouble = DoubleDouble(1e-13)

    // Animation parameters (loaded from preferences)
    private var zoomSpeed: DoubleDouble = DoubleDouble(0.990)
    private let panSpeed: DoubleDouble = DoubleDouble(0.015)

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
    // INTERESTING ZOOM TARGETS - High Precision Coordinates
    // These points lie on the boundary of the set, allowing for deep zooms (10^-14)
    // without landing in empty black space.
    // =========================================================================
    private let interestingPoints: [(x: String, y: String, minScale: String, name: String)] = [
        // Seahorse Valley Deep Zoom
        ("-0.743643887037158704752191506114774", "0.131825904205311970493132056385139", "1e-25", "Seahorse Deep"),
        
        // Scepter Valley
        ("-1.25066667543", "0.020122047495", "1e-10", "Scepter Valley"),
        
        // Quad-Spiral Valley
        ("0.276229045121426", "-0.009120804311029", "1e-14", "Quad-Spiral"),
        
        // Mini-Mandelbrot in Elephant Valley
        ("-1.768778833", "0.004238705", "1e-9", "Elephant Mini"),
        
        // Triple Spiral (Shell)
        ("-0.749767676767", "0.020113113113", "1e-11", "Triple Spiral"),
        
        // Sunburst
        ("-0.16070135", "1.0375665", "1e-7", "Sunburst"),
        
        // Starfish
        ("-0.373333333", "-0.655", "1e-4", "Starfish"),
        
        // Deep Spirals
        ("-0.74719017772", "-0.07693999233", "1e-11", "Deep Spirals"),
        
        // Julia Morph Region
        ("-0.19932130283", "-1.10099687926", "1e-11", "Julia Morph")
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

    private func loadPreferences() {
        let prefs = Preferences.shared
        zoomSpeed = DoubleDouble(prefs.zoomSpeed)
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

        do {
            // Create pipeline state for standard float precision (fast)
            let floatConstants = MTLFunctionConstantValues()
            var useHighPrecision = false
            floatConstants.setConstantValue(&useHighPrecision, type: .bool, index: 0)
            
            let floatPipelineDesc = MTLComputePipelineDescriptor()
            floatPipelineDesc.computeFunction = try library.makeFunction(name: "mandelbrotKernel", constantValues: floatConstants)
            computePipelineFloat = try device.makeComputePipelineState(descriptor: floatPipelineDesc, options: [], reflection: nil)
            
            // Create pipeline state for double-double precision (deep zoom)
            let highPrecConstants = MTLFunctionConstantValues()
            useHighPrecision = true
            highPrecConstants.setConstantValue(&useHighPrecision, type: .bool, index: 0)
            
            let highPrecPipelineDesc = MTLComputePipelineDescriptor()
            highPrecPipelineDesc.computeFunction = try library.makeFunction(name: "mandelbrotKernel", constantValues: highPrecConstants)
            computePipelineHighPrecision = try device.makeComputePipelineState(descriptor: highPrecPipelineDesc, options: [], reflection: nil)
            
            // Create pipeline state for Perturbation Theory (Deep Zoom)
            // Reuses the same kernel but with function constant index 1 set to true
            let perturbConstants = MTLFunctionConstantValues()
            var usePerturbation = true
            // Index 0: HighPrecision (Double-Double) - OFF (we use Perturbation instead)
            // Index 1: Perturbation - ON
            var useHP = false
            perturbConstants.setConstantValue(&useHP, type: .bool, index: 0)
            perturbConstants.setConstantValue(&usePerturbation, type: .bool, index: 1)
            
            let perturbPipelineDesc = MTLComputePipelineDescriptor()
            perturbPipelineDesc.computeFunction = try library.makeFunction(name: "mandelbrotKernel", constantValues: perturbConstants)
            computePipelinePerturbation = try device.makeComputePipelineState(descriptor: perturbPipelineDesc, options: [], reflection: nil)
            
            // Create pipeline state for Orbit Calculation (GPU)
            if let orbitFunction = library.makeFunction(name: "orbitKernel") {
                computePipelineOrbit = try device.makeComputePipelineState(function: orbitFunction)
            }
        } catch {
            NSLog("MandelbrotSaver: Failed to create compute pipelines: \(error)")
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
        
        // PERFORMANCE: Disable Retina scaling (render at 1x points)
        // This reduces GPU load by 4x on Retina displays while maintaining acceptable quality for fractals
        view.wantsLayer = true
        view.layer?.contentsScale = 1.0

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
        // Use drawableSize from mtkView if available (pixels), otherwise fallback to bounds * scale
        let size: CGSize
        if let mtkView = mtkView {
             size = mtkView.drawableSize
        } else {
             // Fallback: Force 1.0 scale if MTKView isn't ready
             size = bounds.size
        }

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
        targetCenterX = DoubleDouble(target.x)
        targetCenterY = DoubleDouble(target.y)
        targetScale = DoubleDouble(target.minScale)

        // Reset to initial view
        centerX = DoubleDouble(-0.5)
        centerY = DoubleDouble(0.0)
        scale = DoubleDouble(3.0)

        zoomCount += 1

        // Reset orbit iterations to safe default
        maxOrbitIterations = 0
        
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
                centerX = DoubleDouble(0.0)
                centerY = DoubleDouble(0.0)
                targetCenterX = DoubleDouble(0.0)
                targetCenterY = DoubleDouble(0.0)
                targetScale = DoubleDouble(3e-5)  // Julia sets don't need as deep zoom
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
            scale = scale * zoomSpeed

            // Smooth pan toward target using ease-out
            let dx = targetCenterX - centerX
            let dy = targetCenterY - centerY
            centerX = centerX + (dx * panSpeed)
            centerY = centerY + (dy * panSpeed)

            // When we've zoomed deep enough, start fading out
            // Use hi part for simple comparison
            if scale.hi < targetScale.hi * 2.0 {
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

    // MARK: - Perturbation Theory Helper
    
    private func updateReferenceOrbit(maxIterations: Int) {
        guard let device = metalDevice else { return }
        
        // Use SIMD4<Float> (16 bytes)
        // .xy = Reference Orbit (Float approximation)
        // .zw = Correction term (Delta) to account for float truncation
        let bufferLength = maxIterations * MemoryLayout<SIMD4<Float>>.size
        
        if referenceOrbitBuffer == nil || referenceOrbitBuffer!.length < bufferLength {
            referenceOrbitBuffer = device.makeBuffer(length: bufferLength, options: .storageModeShared)
            maxOrbitIterations = maxIterations
        }
        
        guard let buffer = referenceOrbitBuffer else { return }
        let pointer = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: maxIterations)
        
        // Use DoubleDouble for calculation
        // Mandelbrot: Z starts at 0. C is center.
        // Julia: Z starts at center. C is constant.
        
        let cx = centerX
        let cy = centerY
        let jcx = DoubleDouble(juliaCx)
        let jcy = DoubleDouble(juliaCy)
        
        var cur_zr: DoubleDouble
        var cur_zi: DoubleDouble
        let c_real: DoubleDouble
        let c_imag: DoubleDouble
        
        if juliaMode {
            cur_zr = cx
            cur_zi = cy
            c_real = jcx
            c_imag = jcy
        } else {
            cur_zr = DoubleDouble(0.0)
            cur_zi = DoubleDouble(0.0)
            c_real = cx
            c_imag = cy
        }
        
        for i in 0..<maxIterations {
            // 1. Store current truncated float value
            let f_zr = Float(cur_zr.hi)
            let f_zi = Float(cur_zi.hi)
            
            // 2. Calculate next exact value (DoubleDouble)
            let zr2 = cur_zr * cur_zr
            let zi2 = cur_zi * cur_zi
            let two = DoubleDouble(2.0)
            
            // Check escape (using hi part for speed)
            if zr2.hi + zi2.hi > 4.0 {
                // Fill remaining
                for j in i..<maxIterations {
                    pointer[j] = SIMD4<Float>(0, 0, 0, 0)
                }
                break
            }
            
            let next_zi = (cur_zr * cur_zi * two) + c_imag
            let next_zr = (zr2 - zi2) + c_real
            
            // 3. Calculate Correction Term (Drift)
            // Delta = (Z_stored^2 + c) - Z_stored_next
            // We need the next stored value to compute the difference
            let f_next_zr = Float(next_zr.hi)
            let f_next_zi = Float(next_zi.hi)
            
            // Calculate what the iteration WOULD be if we used the float values
            let f_zr2 = f_zr * f_zr
            let f_zi2 = f_zi * f_zi
            let f_iter_zr = f_zr2 - f_zi2 + Float(c_real.hi)
            let f_iter_zi = 2.0 * f_zr * f_zi + Float(c_imag.hi)
            
            let delta_r = f_iter_zr - f_next_zr
            let delta_i = f_iter_zi - f_next_zi
            
            pointer[i] = SIMD4<Float>(f_zr, f_zi, delta_r, delta_i)
            
            // Advance exact orbit
            cur_zr = next_zr
            cur_zi = next_zi
        }
    }

    /// Main rendering function - called from MTKViewDelegate
    private func renderFrame() {
        createTextureIfNeeded()

        // Smart auto-iteration: more iterations when zoomed deep
        // With perturbation, we can go very deep
        let zoomDepth = log10(3.0 / scale.hi)
        let maxIterations: Float = min(Float(zoomDepth * 80 + 200), 5000)
        let iterCount = Int(maxIterations)

        // Select Pipeline
        let usePerturbation = scale.hi < 0.003
        let pipeline = usePerturbation ? computePipelinePerturbation : computePipelineFloat

        guard let commandQueue = commandQueue,
              let pipeline = pipeline,
              let texture = outputTexture,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        // Update Reference Orbit on CPU (using DoubleDouble)
        if usePerturbation {
            updateReferenceOrbit(maxIterations: iterCount)
        }
        
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        // ... (rest of function)

        // Split center coordinates into hi/lo parts for double-double precision
        // Using the asFloatPair extension for clean encoding
        // Note: centerX is now DoubleDouble, so we take .hi and .lo directly
        let centerX_hi = Float(centerX.hi)
        let centerX_lo = Float(centerX.lo)
        let centerY_hi = Float(centerY.hi)
        let centerY_lo = Float(centerY.lo)

        // Pack parameters
        var params = simd_float4(
            centerX_hi,
            centerY_hi,
            Float(scale.hi),
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
            centerX_lo,
            centerY_lo,
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
        
        if usePerturbation, let refBuffer = referenceOrbitBuffer {
            encoder.setBuffer(refBuffer, offset: 0, index: 5)
        }

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

        let zoomDepth = log10(3.0 / scale.hi)
        let maxIterations: Float = min(Float(zoomDepth * 80 + 200), 5000)
        let iterCount = Int(maxIterations)

        let usePerturbation = scale.hi < 0.003
        let pipeline = usePerturbation ? computePipelinePerturbation : computePipelineFloat

        guard let commandQueue = commandQueue,
              let pipeline = pipeline,
              let texture = outputTexture,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        if usePerturbation {
            updateReferenceOrbit(maxIterations: iterCount)
        }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }

        let centerX_hi = Float(centerX.hi)
        let centerX_lo = Float(centerX.lo)
        let centerY_hi = Float(centerY.hi)
        let centerY_lo = Float(centerY.lo)

        var params = simd_float4(centerX_hi, centerY_hi, Float(scale.hi), maxIterations)
        let aspectRatio = Float(bounds.width / bounds.height)
        var params2 = simd_float4(colorOffset, aspectRatio, Float(currentPalette), paletteMix)
        var params3 = simd_float4(centerX_lo, centerY_lo, Float(shadingMode), time)
        var params4 = simd_float4(transitionOpacity, juliaMode ? 1.0 : 0.0, Float(juliaCx), Float(juliaCy))

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<simd_float4>.size, index: 0)
        encoder.setBytes(&params2, length: MemoryLayout<simd_float4>.size, index: 1)
        encoder.setBytes(&params3, length: MemoryLayout<simd_float4>.size, index: 2)
        encoder.setBytes(&params4, length: MemoryLayout<simd_float4>.size, index: 3)
        
        if usePerturbation, let refBuffer = referenceOrbitBuffer {
            encoder.setBuffer(refBuffer, offset: 0, index: 5)
        }
        
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
