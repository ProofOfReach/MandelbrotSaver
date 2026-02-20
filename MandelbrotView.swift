import ScreenSaver
import Metal
import QuartzCore
import simd

// Debug logging to file (NSLog is swallowed by unified log privacy)
private func dbg(_ msg: String) {
    let s = "\(Date()): \(msg)\n"
    let path = "/tmp/mandelbrot_debug.log"
    if let fh = FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile()
        fh.write(s.data(using: .utf8)!)
        fh.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: s.data(using: .utf8))
    }
}

@objc(MandelbrotView)
class MandelbrotView: ScreenSaverView {
    // Use a CAMetalLayer directly on ScreenSaverView; avoids legacyScreenSaver subview compositing issues.
    private let preferDirectMetalLayer = true

    // MARK: - Metal
    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var computePipelineFloat: MTLComputePipelineState?
    private var computePipelineHighPrecision: MTLComputePipelineState?
    private var computePipelinePerturbation: MTLComputePipelineState?
    private var referenceOrbitBuffer: MTLBuffer?
    private var maxOrbitIterations: Int = 0

    // Direct display path
    private var metalLayer: CAMetalLayer?

    // CPU fallback path (for preview edge-cases / when no drawable is available)
    private var fallbackTexture: MTLTexture?
    private var lastTextureSize: CGSize = .zero
    private var readbackPixels: [UInt8] = []
    private var latestFallbackImage: CGImage?

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
    private var zoomSpeed: DoubleDouble = DoubleDouble(0.985)
    private let panSpeed: DoubleDouble = DoubleDouble(0.015)

    // Visual effects
    private var colorOffset: Float = 0.0
    private var currentPalette: Int = 0
    private var paletteMix: Float = 0.0
    private var paletteTimer: Float = 0.0
    private var shadingMode: Int = 0
    private var time: Float = 0.0
    private var autoCyclePalettes: Bool = true
    private var frameCount: Int = 0
    private var lastFrameTime: CFAbsoluteTime = 0
    private var slowFrameCount: Int = 0
    private var zoomStartTime: CFAbsoluteTime = 0
    private let maxZoomDuration: CFAbsoluteTime = 20

    // MARK: - Julia Set Mode
    private var juliaEnabled: Bool = false
    private var juliaMode: Bool = false
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

    // MARK: - Interesting zoom targets
    // At speed 0.985, 60fps, 20s: scale reaches ~3.7e-8 (7.4 decades from 3.0)
    // Target scales set to 1e-5 .. 1e-7 so zoom reaches them and triggers natural fade
    private let interestingPoints: [(x: String, y: String, minScale: String, name: String)] = [
        // Seahorse Valley - the most iconic Mandelbrot region
        ("-0.7445388635959773", "0.1217247190726782", "1e-7", "Seahorse Valley Deep Spiral"),
        ("-0.7451968299999999", "0.10186988500000009", "1e-6", "Seahorse Valley Classic"),
        ("-0.7463", "0.1102", "1e-5", "Seahorse Valley Wide"),
        // Elephant Valley - trunk structures and mini-brots
        ("0.2777323864244548", "0.0073446267400780795", "1e-6", "Elephant Trunk"),
        ("0.33698444648740383", "0.048778219678026105", "1e-6", "Elephant Eye"),
        ("0.250006", "0.00000045", "1e-7", "Elephant Valley Cusp"),
        // Spirals and vortices
        ("-0.0875937321188787", "0.6550902802386774", "1e-6", "Triple Spiral Valley"),
        ("-0.5360670633819427", "-0.5255257785409202", "1e-6", "Turbulence"),
        ("-0.22163951090127437", "-0.7115537848292754", "1e-6", "LSD Spiral"),
        ("0.452721018749286", "0.39649427698014", "1e-6", "Galaxies"),
        ("0.35787121400640803", "-0.10813970113434704", "1e-6", "Carousel Spirals"),
        ("-0.16070135", "1.0375665", "1e-5", "Sunburst"),
        // Antenna and needle region
        ("-1.7397156556930304", "-9.157504622931403e-8", "1e-7", "Wormhole"),
        ("-1.7397082221332807", "-4.768199679090003e-6", "1e-6", "Praline"),
        ("-1.4011551890920506", "0.0", "1e-6", "Feigenbaum Point"),
        // Mini-brots and satellite copies
        ("-1.25066", "0.02012", "1e-6", "Scepter Valley"),
        ("-1.768778833", "0.004238705", "1e-6", "Elephant Mini"),
        ("-0.1528", "1.0397", "1e-5", "Period-3 Boundary"),
        // Filaments and dendrites
        ("-0.374004139", "-0.659792175", "1e-5", "Starfish Filament"),
        ("-0.749767676767", "0.020113113113", "1e-6", "Triple Spiral Tendril"),
        // Scepter region - hooks and branches
        ("-1.25709", "0.02500", "1e-6", "Seahorse West Entrance"),
        ("-1.249783", "0.029353", "1e-6", "Scepter Double-Hook"),
        ("-1.2494989", "0.0303330", "1e-7", "Scepter Hook Core"),
        // Mini-Mandelbrot copies and satellites
        ("-1.749086", "0.0", "1e-6", "Period-3 Minibrot Cusp"),
        ("-1.76733", "0.00002", "1e-6", "Largest Minibrot Rim"),
        ("-1.7891690186048231", "-0.0000003393685157672", "1e-7", "11 Dimensions Anchor"),
        // Unusual morphologies and alien geometry
        ("-0.7528585928145695", "0.04314319321653719", "1e-6", "Hidden Teddy Boundary"),
        ("0.36024044343761436", "-0.6413130610648032", "1e-6", "Eye of the Universe"),
        ("0.274", "0.482", "1e-5", "Quad Spiral Cusp"),
        // Real-axis and antenna structures
        ("-1.79032749199934", "0.0", "1e-7", "Period-3 Tip"),
        ("-1.7868562072981548", "0.0", "1e-7", "Real-Line Minibrot Corridor"),
        ("-1.6690", "0.0029", "1e-5", "Main Antenna Filament"),
        // Period boundaries and weaves
        ("-1.2067", "0.0001", "1e-5", "Period-2 Boundary Weave"),
        ("-0.1267", "0.8442", "1e-5", "Double Scepter Valley"),
        ("-1.9999944848854987", "0.0", "1e-7", "End-of-Line Edge"),
        ("0.3191", "0.6007", "1e-5", "Northeast Radical Basin"),
        ("-0.1296", "0.8394", "1e-6", "Double Scepter Filament Knot"),
        ("-1.9999858811837755", "0.00000000001583008566655028", "1e-7", "End-of-Line Off-Axis"),
    ]

    private var currentTargetIndex: Int = 0
    private var zoomCount: Int = 0

    // MARK: - Initialization

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        dbg("init frame=\(frame) isPreview=\(isPreview)")
        wantsLayer = true
        loadPreferences()
        setupMetal()
        selectRandomTarget()
        animationTimeInterval = 1.0 / 60.0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        loadPreferences()
        setupMetal()
        selectRandomTarget()
        animationTimeInterval = 1.0 / 60.0
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMetalLayerGeometry()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        lastTextureSize = .zero
        updateMetalLayerGeometry()
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

        let bundle = Bundle(for: type(of: self))
        guard let libraryURL = bundle.url(forResource: "default", withExtension: "metallib"),
              let library = try? device.makeLibrary(URL: libraryURL) else {
            NSLog("MandelbrotSaver: Failed to load Metal library")
            return
        }

        do {
            // float precision
            let floatConstants = MTLFunctionConstantValues()
            var useHighPrecision = false
            var usePerturbation = false
            floatConstants.setConstantValue(&useHighPrecision, type: .bool, index: 0)
            floatConstants.setConstantValue(&usePerturbation, type: .bool, index: 1)
            computePipelineFloat = try device.makeComputePipelineState(function: try library.makeFunction(name: "mandelbrotKernel", constantValues: floatConstants))

            // double-double precision
            let highPrecConstants = MTLFunctionConstantValues()
            useHighPrecision = true
            usePerturbation = false
            highPrecConstants.setConstantValue(&useHighPrecision, type: .bool, index: 0)
            highPrecConstants.setConstantValue(&usePerturbation, type: .bool, index: 1)
            computePipelineHighPrecision = try device.makeComputePipelineState(function: try library.makeFunction(name: "mandelbrotKernel", constantValues: highPrecConstants))

            // perturbation path
            let perturbConstants = MTLFunctionConstantValues()
            useHighPrecision = false
            usePerturbation = true
            perturbConstants.setConstantValue(&useHighPrecision, type: .bool, index: 0)
            perturbConstants.setConstantValue(&usePerturbation, type: .bool, index: 1)
            computePipelinePerturbation = try device.makeComputePipelineState(function: try library.makeFunction(name: "mandelbrotKernel", constantValues: perturbConstants))
        } catch {
            NSLog("MandelbrotSaver: Failed to create compute pipelines: \(error)")
        }

        if preferDirectMetalLayer {
            setupDirectMetalLayer(device: device)
        }

        dbg("setupMetal done: device=\(metalDevice?.name ?? "nil") directLayer=\(metalLayer != nil)")
    }

    private func setupDirectMetalLayer(device: MTLDevice) {
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.isOpaque = true
        layer.maximumDrawableCount = 3

        self.layer = layer
        metalLayer = layer
        updateMetalLayerGeometry()
    }

    private func updateMetalLayerGeometry() {
        guard let metalLayer else { return }

        metalLayer.frame = bounds

        // Render at 1x point size regardless of Retina scale - 4x fewer pixels, smooth animation
        let size = currentRenderSize()
        metalLayer.contentsScale = 1.0
        metalLayer.drawableSize = CGSize(width: max(1, Int(size.width)),
                                         height: max(1, Int(size.height)))
    }

    private func currentRenderSize() -> CGSize {
        if bounds.width >= 2, bounds.height >= 2 {
            return bounds.size
        }
        if let contentBounds = window?.contentView?.bounds, contentBounds.width >= 2, contentBounds.height >= 2 {
            return contentBounds.size
        }
        return isPreview ? CGSize(width: 320, height: 240) : CGSize(width: 800, height: 600)
    }

    private func createFallbackTextureIfNeeded() {
        let size = currentRenderSize()
        guard size.width > 0, size.height > 0 else { return }

        if size == lastTextureSize, fallbackTexture != nil { return }
        lastTextureSize = size

        guard let device = metalDevice else { return }

        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderWrite, .shaderRead]
        descriptor.storageMode = .shared

        fallbackTexture = device.makeTexture(descriptor: descriptor)
        readbackPixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    // MARK: - Auto-Pilot

    private func selectRandomTarget() {
        var newIndex: Int
        repeat {
            newIndex = Int.random(in: 0..<interestingPoints.count)
        } while newIndex == currentTargetIndex && interestingPoints.count > 1

        currentTargetIndex = newIndex
        let target = interestingPoints[currentTargetIndex]
        targetCenterX = DoubleDouble(target.x)
        targetCenterY = DoubleDouble(target.y)
        targetScale = DoubleDouble(target.minScale)

        centerX = DoubleDouble(-0.5)
        centerY = DoubleDouble(0.0)
        scale = DoubleDouble(3.0)

        zoomCount += 1
        maxOrbitIterations = 0
        slowFrameCount = 0
        zoomStartTime = CFAbsoluteTimeGetCurrent()

        if juliaEnabled && zoomCount % 4 == 0 {
            juliaMode = !juliaMode
            if juliaMode {
                let juliaIndex = Int.random(in: 0..<interestingJuliaC.count)
                let juliaC = interestingJuliaC[juliaIndex]
                juliaCx = juliaC.cx
                juliaCy = juliaC.cy
                centerX = DoubleDouble(0.0)
                centerY = DoubleDouble(0.0)
                targetCenterX = DoubleDouble(0.0)
                targetCenterY = DoubleDouble(0.0)
                targetScale = DoubleDouble(3e-5)
            }
        } else if !juliaEnabled {
            juliaMode = false
        }

        if zoomCount % 3 == 0 {
            shadingMode = (shadingMode + 1) % 4
        }
    }

    private func updateAnimation() {
        // Track frame time - bail out if rendering is too slow
        let now = CFAbsoluteTimeGetCurrent()
        if lastFrameTime > 0 {
            let dt = now - lastFrameTime
            if dt > 0.08 { // slower than ~12fps
                slowFrameCount += 1
            } else {
                slowFrameCount = 0
            }
        }
        lastFrameTime = now

        switch transitionState {
        case .zooming:
            // Bail if too slow or zoom has run long enough
            let zoomElapsed = now - zoomStartTime
            if slowFrameCount >= 3 || zoomElapsed > maxZoomDuration {
                slowFrameCount = 0
                transitionState = .fadingOut
            }

            scale = scale * zoomSpeed

            let dx = targetCenterX - centerX
            let dy = targetCenterY - centerY
            centerX = centerX + (dx * panSpeed)
            centerY = centerY + (dy * panSpeed)

            if scale.hi < targetScale.hi * 2.0 {
                transitionState = .fadingOut
            }

        case .fadingOut:
            transitionOpacity -= fadeSpeed
            if transitionOpacity <= 0.0 {
                transitionOpacity = 0.0
                selectRandomTarget()
                transitionState = .fadingIn
            }

        case .fadingIn:
            transitionOpacity += fadeSpeed
            if transitionOpacity >= 1.0 {
                transitionOpacity = 1.0
                transitionState = .zooming
            }
        }

        colorOffset += 0.3
        if colorOffset > 10000.0 {
            colorOffset = 0.0
        }

        if autoCyclePalettes {
            paletteTimer += 0.001
            if paletteTimer >= 1.0 {
                paletteTimer = 0.0
                currentPalette = (currentPalette + 1) % Preferences.paletteNames.count
            }
            paletteMix = paletteTimer
        } else {
            paletteMix = 0.0
        }

        frameCount += 1
        if frameCount % 60 == 0 {
            loadPreferences()
        }

        time += 0.016
    }

    // MARK: - Perturbation Theory Helper

    private func updateReferenceOrbit(maxIterations: Int) {
        guard let device = metalDevice else { return }

        let bufferLength = maxIterations * MemoryLayout<SIMD4<Float>>.size
        if referenceOrbitBuffer == nil || referenceOrbitBuffer!.length < bufferLength {
            referenceOrbitBuffer = device.makeBuffer(length: bufferLength, options: .storageModeShared)
            maxOrbitIterations = maxIterations
        }

        guard let buffer = referenceOrbitBuffer else { return }
        let pointer = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: maxIterations)

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

        let two = DoubleDouble(2.0)

        for i in 0..<maxIterations {
            let f_zr = Float(cur_zr.hi)
            let f_zi = Float(cur_zi.hi)

            let zr2 = cur_zr * cur_zr
            let zi2 = cur_zi * cur_zi

            if zr2.hi + zi2.hi > 4.0 {
                for j in i..<maxIterations {
                    pointer[j] = SIMD4<Float>(0, 0, 0, 0)
                }
                break
            }

            let next_zi = (cur_zr * cur_zi * two) + c_imag
            let next_zr = (zr2 - zi2) + c_real

            let f_next_zr = Float(next_zr.hi)
            let f_next_zi = Float(next_zi.hi)

            let f_zr2 = f_zr * f_zr
            let f_zi2 = f_zi * f_zi
            let f_iter_zr = f_zr2 - f_zi2 + Float(c_real.hi)
            let f_iter_zi = 2.0 * f_zr * f_zi + Float(c_imag.hi)

            let delta_r = f_iter_zr - f_next_zr
            let delta_i = f_iter_zi - f_next_zi

            pointer[i] = SIMD4<Float>(f_zr, f_zi, delta_r, delta_i)

            cur_zr = next_zr
            cur_zi = next_zi
        }
    }

    private struct RenderTarget {
        let texture: MTLTexture
        let drawable: CAMetalDrawable?
        let size: CGSize
        let usesFallback: Bool
    }

    private func acquireRenderTarget() -> RenderTarget? {
        if let layer = metalLayer, let drawable = layer.nextDrawable() {
            let size = CGSize(width: drawable.texture.width, height: drawable.texture.height)
            return RenderTarget(texture: drawable.texture, drawable: drawable, size: size, usesFallback: false)
        }

        createFallbackTextureIfNeeded()
        guard let texture = fallbackTexture else { return nil }
        let size = CGSize(width: texture.width, height: texture.height)
        return RenderTarget(texture: texture, drawable: nil, size: size, usesFallback: true)
    }

    // Returns true if NSView draw() should be triggered for CPU fallback presentation.
    @discardableResult
    private func renderFrame() -> Bool {
        guard let commandQueue,
              let target = acquireRenderTarget() else {
            return false
        }

        let depth = max(0.0, log10(3.0 / scale.hi))
        let currentScale = scale.hi

        // Skip DD tier for real-time — it's too slow per-pixel.
        // Go directly from float to perturbation at scale <= 1e-6.
        let usePerturbation = currentScale <= 1e-6
        let pipeline: MTLComputePipelineState?
        let maxIterations: Int
        if usePerturbation {
            pipeline = computePipelinePerturbation
            maxIterations = min(900, Int(320 + depth * 36))
        } else {
            pipeline = computePipelineFloat
            maxIterations = min(450, Int(220 + depth * 24))
        }
        let iterCount = maxIterations

        guard let pipeline,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return false
        }

        if usePerturbation {
            updateReferenceOrbit(maxIterations: iterCount)
        }

        let centerX_hi = Float(centerX.hi)
        let centerX_lo = Float(centerX.lo)
        let centerY_hi = Float(centerY.hi)
        let centerY_lo = Float(centerY.lo)

        var params = simd_float4(centerX_hi, centerY_hi, Float(scale.hi), Float(maxIterations))
        let aspectRatio = Float(target.size.width / target.size.height)
        var params2 = simd_float4(colorOffset, aspectRatio, Float(currentPalette), paletteMix)
        var params3 = simd_float4(centerX_lo, centerY_lo, Float(shadingMode), time)
        var params4 = simd_float4(transitionOpacity, juliaMode ? 1.0 : 0.0, Float(juliaCx), Float(juliaCy))

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(target.texture, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<simd_float4>.size, index: 0)
        encoder.setBytes(&params2, length: MemoryLayout<simd_float4>.size, index: 1)
        encoder.setBytes(&params3, length: MemoryLayout<simd_float4>.size, index: 2)
        encoder.setBytes(&params4, length: MemoryLayout<simd_float4>.size, index: 3)

        if usePerturbation, let refBuffer = referenceOrbitBuffer {
            encoder.setBuffer(refBuffer, offset: 0, index: 5)
        } else {
            if referenceOrbitBuffer == nil {
                referenceOrbitBuffer = metalDevice?.makeBuffer(length: 16, options: .storageModeShared)
            }
            if let refBuffer = referenceOrbitBuffer {
                encoder.setBuffer(refBuffer, offset: 0, index: 5)
            }
        }

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (target.texture.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (target.texture.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()

        if let drawable = target.drawable {
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return false
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        updateFallbackImage(from: target.texture)
        return true
    }

    private func updateFallbackImage(from texture: MTLTexture) {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4

        if readbackPixels.count != width * height * 4 {
            readbackPixels = [UInt8](repeating: 0, count: width * height * 4)
        }

        texture.getBytes(
            &readbackPixels,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                            size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0
        )

        guard let dataProvider = CGDataProvider(data: Data(readbackPixels) as CFData) else {
            latestFallbackImage = nil
            return
        }

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(.init(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))

        latestFallbackImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    // MARK: - Drawing / Animation

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()

        guard let context = NSGraphicsContext.current?.cgContext,
              let image = latestFallbackImage else { return }

        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: bounds)
        context.restoreGState()
    }

    override func animateOneFrame() {
        updateAnimation()

        if frameCount <= 5 {
            dbg("animateOneFrame #\(frameCount) bounds=\(bounds) directLayer=\(metalLayer != nil) scale=\(scale.hi)")
        }

        let needsCPUDisplay = renderFrame()
        if needsCPUDisplay {
            setNeedsDisplay(bounds)
        }
    }

    // MARK: - Configuration Sheet

    override var hasConfigureSheet: Bool {
        true
    }

    override var configureSheet: NSWindow? {
        configureSheetController.configureSheet()
    }
}
