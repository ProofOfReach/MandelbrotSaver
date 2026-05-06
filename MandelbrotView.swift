import ScreenSaver
import Metal
import QuartzCore
import simd

@objc(MandelbrotView)
class MandelbrotView: ScreenSaverView {
    // Use a CAMetalLayer directly on ScreenSaverView; avoids legacyScreenSaver subview compositing issues.
    private let preferDirectMetalLayer = true

    // MARK: - Metal
    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var computePipelineFloat: MTLComputePipelineState?
    private var computePipelinePerturbation: MTLComputePipelineState?
    private var referenceOrbitBuffer: MTLBuffer?
    private var qualityProbeTexture: MTLTexture?
    private var qualityProbePixels: [UInt8] = []

    private struct ShaderUniforms {
        var geometry: SIMD4<Float> // centerX_hi, centerY_hi, scale, maxIterations
        var palette: SIMD4<Float>  // colorOffset, aspectRatio, paletteIndex, paletteMix
        var view: SIMD4<Float>     // centerX_lo, centerY_lo, shadingMode, time
        var mode: SIMD4<Float>     // opacity, juliaMode, juliaCx, juliaCy
        var quality: SIMD4<Float>  // aaSamples, lightingQuality, reserved, reserved
    }

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

    // MARK: - Zoom State
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
    private var visualQuality: Int = 1
    private var time: Float = 0.0
    private var autoCyclePalettes: Bool = true
    private var lastPreferenceReload: CFAbsoluteTime = 0
    private var lastLoadedPalettePreference: Int?
    private var lastLoadedAutoCyclePreference: Bool?
    private var lastFrameTime: CFAbsoluteTime = 0
    private var lastQualityProbeTime: CFAbsoluteTime = 0
    private var poorQualityFrameCount: Int = 0
    private var slowFrameCount: Int = 0
    private var zoomStartTime: CFAbsoluteTime = 0
    private let minZoomDuration: CFAbsoluteTime = 24
    private let maxZoomDuration: CFAbsoluteTime = 140
    private let paletteCycleDuration: CFAbsoluteTime = 18
    private let qualityProbeInterval: CFAbsoluteTime = 0.75
    private let qualityProbeWidth = 96
    private let qualityProbeHeight = 64

    private struct RenderPolicy {
        let antialiasSamples: Int
        let lightingQuality: Int
        let maxFloatIterations: Int
        let maxPerturbationIterations: Int
    }

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
    // Curated for screensaver value: dense structure, low empty-center risk, and stable real-time depth.
    private let interestingPoints: [(x: String, y: String, minScale: String, name: String)] = [
        ("-0.7445388635959773", "0.1217247190726782", "1e-7", "Seahorse Valley Deep Spiral"),
        ("-0.7451968299999999", "0.10186988500000009", "1e-6", "Seahorse Valley Classic"),
        ("-0.7463", "0.1102", "1e-5", "Seahorse Valley Wide"),
        ("0.2777323864244548", "0.0073446267400780795", "1e-6", "Elephant Trunk"),
        ("0.33698444648740383", "0.048778219678026105", "1e-6", "Elephant Eye"),
        ("-0.0875937321188787", "0.6550902802386774", "1e-6", "Triple Spiral Valley"),
        ("-0.5360670633819427", "-0.5255257785409202", "1e-6", "Turbulence"),
        ("-0.22163951090127437", "-0.7115537848292754", "1e-6", "LSD Spiral"),
        ("0.452721018749286", "0.39649427698014", "1e-6", "Galaxies"),
        ("0.35787121400640803", "-0.10813970113434704", "1e-6", "Carousel Spirals"),
        ("-0.16070135", "1.0375665", "1e-5", "Sunburst"),
        ("-1.25066", "0.02012", "1e-6", "Scepter Valley"),
        ("-0.1528", "1.0397", "1e-5", "Period-3 Boundary"),
        ("-0.374004139", "-0.659792175", "1e-5", "Starfish Filament"),
        ("-0.749767676767", "0.020113113113", "1e-6", "Triple Spiral Tendril"),
        ("-1.249783", "0.029353", "1e-6", "Scepter Double-Hook"),
        ("-1.2494989", "0.0303330", "1e-7", "Scepter Hook Core"),
        ("-0.7528585928145695", "0.04314319321653719", "1e-6", "Hidden Teddy Boundary"),
        ("0.36024044343761436", "-0.6413130610648032", "1e-6", "Eye of the Universe"),
        ("0.274", "0.482", "1e-5", "Quad Spiral Cusp"),
        ("-0.1267", "0.8442", "1e-5", "Double Scepter Valley"),
    ]

    private var currentTargetIndex: Int = 0
    private var zoomCount: Int = 0

    // MARK: - Initialization

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        loadPreferences()
        observePreferenceChanges()
        setupMetal()
        selectRandomTarget()
        animationTimeInterval = 1.0 / 60.0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        loadPreferences()
        observePreferenceChanges()
        setupMetal()
        selectRandomTarget()
        animationTimeInterval = 1.0 / 60.0
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
        let previousJuliaEnabled = juliaEnabled
        let newPalette = prefs.paletteIndex
        let newAutoCycle = prefs.autoCyclePalettes
        zoomSpeed = DoubleDouble(prefs.zoomSpeed)

        if lastLoadedPalettePreference != newPalette {
            currentPalette = newPalette
            paletteTimer = 0.0
            paletteMix = 0.0
            lastLoadedPalettePreference = newPalette
        }

        if lastLoadedAutoCyclePreference != newAutoCycle {
            autoCyclePalettes = newAutoCycle
            paletteTimer = 0.0
            paletteMix = 0.0
            lastLoadedAutoCyclePreference = newAutoCycle
        }

        shadingMode = prefs.shadingMode
        juliaEnabled = prefs.juliaMode
        visualQuality = prefs.visualQuality

        if previousJuliaEnabled != juliaEnabled && zoomStartTime > 0 {
            selectRandomTarget()
        }
    }

    private var renderPolicy: RenderPolicy {
        if visualQuality >= 1 {
            return RenderPolicy(
                antialiasSamples: 1,
                lightingQuality: 2,
                maxFloatIterations: 650,
                maxPerturbationIterations: 1200
            )
        }
        return RenderPolicy(
            antialiasSamples: 1,
            lightingQuality: 1,
            maxFloatIterations: 450,
            maxPerturbationIterations: 900
        )
    }

    private func observePreferenceChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: Preferences.didChangeNotification,
            object: nil
        )
    }

    @objc private func preferencesDidChange(_ notification: Notification) {
        let previousQuality = visualQuality
        loadPreferences()
        if previousQuality != visualQuality {
            lastTextureSize = .zero
            updateMetalLayerGeometry()
        }
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
            var usePerturbation = false
            floatConstants.setConstantValue(&usePerturbation, type: .bool, index: 0)
            computePipelineFloat = try device.makeComputePipelineState(function: try library.makeFunction(name: "mandelbrotKernel", constantValues: floatConstants))

            // perturbation path
            let perturbConstants = MTLFunctionConstantValues()
            usePerturbation = true
            perturbConstants.setConstantValue(&usePerturbation, type: .bool, index: 0)
            computePipelinePerturbation = try device.makeComputePipelineState(function: try library.makeFunction(name: "mandelbrotKernel", constantValues: perturbConstants))
        } catch {
            NSLog("MandelbrotSaver: Failed to create compute pipelines: \(error)")
        }

        if preferDirectMetalLayer {
            setupDirectMetalLayer(device: device)
        }
    }

    private func setupDirectMetalLayer(device: MTLDevice) {
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm_srgb
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

        let size = currentRenderSize()
        let renderScale = currentRenderScale()
        metalLayer.contentsScale = renderScale
        metalLayer.drawableSize = CGSize(width: max(1, Int(size.width * renderScale)),
                                         height: max(1, Int(size.height * renderScale)))
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

    private func currentRenderScale() -> CGFloat {
        if isPreview || visualQuality <= 0 {
            return 1.0
        }

        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        return min(max(backingScale, 1.0), 2.0)
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

        zoomCount += 1
        slowFrameCount = 0
        poorQualityFrameCount = 0
        zoomStartTime = CFAbsoluteTimeGetCurrent()

        if juliaEnabled {
            juliaMode = true
            let juliaIndex = Int.random(in: 0..<interestingJuliaC.count)
            let juliaC = interestingJuliaC[juliaIndex]
            juliaCx = juliaC.cx
            juliaCy = juliaC.cy
            centerX = DoubleDouble(0.0)
            centerY = DoubleDouble(0.0)
            targetCenterX = DoubleDouble(0.0)
            targetCenterY = DoubleDouble(0.0)
            targetScale = DoubleDouble(3e-5)
        } else {
            juliaMode = false
            let target = interestingPoints[currentTargetIndex]
            targetCenterX = DoubleDouble(target.x)
            targetCenterY = DoubleDouble(target.y)
            targetScale = DoubleDouble(target.minScale)
            centerX = targetCenterX
            centerY = targetCenterY
        }

        scale = DoubleDouble(3.0)
    }

    private func updateAnimation() {
        // Track frame time - bail out if rendering is too slow
        let now = CFAbsoluteTimeGetCurrent()
        let frameDelta: CFAbsoluteTime
        if lastFrameTime > 0 {
            let dt = now - lastFrameTime
            frameDelta = min(max(dt, 1.0 / 120.0), 0.1)
            if dt > 0.08 { // slower than ~12fps
                slowFrameCount += 1
            } else {
                slowFrameCount = 0
            }
        } else {
            frameDelta = animationTimeInterval
        }
        lastFrameTime = now
        let frameScale = frameDelta * 60.0
        reloadPreferencesIfNeeded(now: now)

        switch transitionState {
        case .zooming:
            let zoomElapsed = now - zoomStartTime
            if slowFrameCount >= 3 || zoomElapsed > zoomDurationLimit {
                slowFrameCount = 0
                transitionState = .fadingOut
            }

            scale = scale * pow(zoomSpeed.hi, frameScale)

            let dx = targetCenterX - centerX
            let dy = targetCenterY - centerY
            let panFactor = 1.0 - pow(1.0 - panSpeed.hi, frameScale)
            centerX = centerX + (dx * panFactor)
            centerY = centerY + (dy * panFactor)

            if scale.hi < targetScale.hi * 2.0 {
                transitionState = .fadingOut
            }

        case .fadingOut:
            transitionOpacity -= fadeSpeed * Float(frameScale)
            if transitionOpacity <= 0.0 {
                transitionOpacity = 0.0
                selectRandomTarget()
                transitionState = .fadingIn
            }

        case .fadingIn:
            transitionOpacity += fadeSpeed * Float(frameScale)
            if transitionOpacity >= 1.0 {
                transitionOpacity = 1.0
                transitionState = .zooming
            }
        }

        colorOffset += Float(frameDelta * 18.0)
        if colorOffset > 10000.0 {
            colorOffset = 0.0
        }

        if autoCyclePalettes {
            paletteTimer += Float(frameDelta / paletteCycleDuration)
            if paletteTimer >= 1.0 {
                paletteTimer = paletteTimer.truncatingRemainder(dividingBy: 1.0)
                currentPalette = (currentPalette + 1) % Preferences.paletteNames.count
            }
            paletteMix = paletteTimer
        } else {
            paletteMix = 0.0
        }

        time += Float(frameDelta)
    }

    private func reloadPreferencesIfNeeded(now: CFAbsoluteTime) {
        guard now - lastPreferenceReload >= 0.25 else { return }
        lastPreferenceReload = now
        loadPreferences()
    }

    private var zoomDurationLimit: CFAbsoluteTime {
        let target = max(targetScale.hi * 2.0, 1e-12)
        let start = 3.0
        let speed = min(max(zoomSpeed.hi, 0.0001), 0.9999)
        let estimatedFrames = log(target / start) / log(speed)
        let estimatedSeconds = estimatedFrames / 60.0
        return min(max(estimatedSeconds, minZoomDuration), maxZoomDuration)
    }

    // MARK: - Perturbation Theory Helper

    private func updateReferenceOrbit(maxIterations: Int) {
        guard let device = metalDevice else { return }

        let bufferLength = maxIterations * MemoryLayout<SIMD4<Float>>.size
        if referenceOrbitBuffer == nil || referenceOrbitBuffer!.length < bufferLength {
            referenceOrbitBuffer = device.makeBuffer(length: bufferLength, options: .storageModeShared)
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
    }

    private func acquireRenderTarget() -> RenderTarget? {
        if let layer = metalLayer, let drawable = layer.nextDrawable() {
            let size = CGSize(width: drawable.texture.width, height: drawable.texture.height)
            return RenderTarget(texture: drawable.texture, drawable: drawable, size: size)
        }

        createFallbackTextureIfNeeded()
        guard let texture = fallbackTexture else { return nil }
        let size = CGSize(width: texture.width, height: texture.height)
        return RenderTarget(texture: texture, drawable: nil, size: size)
    }

    private func makeUniforms(width: Int, height: Int, maxIterations: Int, policy: RenderPolicy) -> ShaderUniforms {
        let aspectRatio = Float(width) / Float(max(height, 1))
        return ShaderUniforms(
            geometry: SIMD4<Float>(Float(centerX.hi), Float(centerY.hi), Float(scale.hi), Float(maxIterations)),
            palette: SIMD4<Float>(colorOffset, aspectRatio, Float(currentPalette), paletteMix),
            view: SIMD4<Float>(Float(centerX.lo), Float(centerY.lo), Float(shadingMode), time),
            mode: SIMD4<Float>(transitionOpacity, juliaMode ? 1.0 : 0.0, Float(juliaCx), Float(juliaCy)),
            quality: SIMD4<Float>(Float(policy.antialiasSamples), Float(policy.lightingQuality), 0.0, 0.0)
        )
    }

    private func createQualityProbeTextureIfNeeded() {
        guard qualityProbeTexture == nil, let device = metalDevice else { return }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: qualityProbeWidth,
            height: qualityProbeHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderWrite, .shaderRead]
        descriptor.storageMode = .shared

        qualityProbeTexture = device.makeTexture(descriptor: descriptor)
        qualityProbePixels = [UInt8](repeating: 0, count: qualityProbeWidth * qualityProbeHeight * 4)
    }

    private func shouldEndForVisualQuality(
        pipeline: MTLComputePipelineState,
        maxIterations: Int,
        policy: RenderPolicy,
        now: CFAbsoluteTime
    ) -> Bool {
        guard transitionState == .zooming,
              now - lastQualityProbeTime >= qualityProbeInterval,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return false
        }

        lastQualityProbeTime = now
        createQualityProbeTextureIfNeeded()
        guard let texture = qualityProbeTexture else { return false }

        var uniforms = makeUniforms(
            width: qualityProbeWidth,
            height: qualityProbeHeight,
            maxIterations: maxIterations,
            policy: policy
        )

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 0)

        if referenceOrbitBuffer == nil {
            referenceOrbitBuffer = metalDevice?.makeBuffer(length: 16, options: .storageModeShared)
        }
        if let refBuffer = referenceOrbitBuffer {
            encoder.setBuffer(refBuffer, offset: 0, index: 1)
        }

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (qualityProbeWidth + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (qualityProbeHeight + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if commandBuffer.error != nil {
            poorQualityFrameCount += 1
            return poorQualityFrameCount >= 2
        }

        texture.getBytes(
            &qualityProbePixels,
            bytesPerRow: qualityProbeWidth * 4,
            from: MTLRegionMake2D(0, 0, qualityProbeWidth, qualityProbeHeight),
            mipmapLevel: 0
        )

        var nonBlack = 0
        var bright = 0
        var sum = 0.0
        var sumSquares = 0.0
        let pixelCount = qualityProbeWidth * qualityProbeHeight

        for offset in stride(from: 0, to: qualityProbePixels.count, by: 4) {
            let b = Double(qualityProbePixels[offset]) / 255.0
            let g = Double(qualityProbePixels[offset + 1]) / 255.0
            let r = Double(qualityProbePixels[offset + 2]) / 255.0
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            if luminance > 0.025 { nonBlack += 1 }
            if luminance > 0.20 { bright += 1 }
            sum += luminance
            sumSquares += luminance * luminance
        }

        let count = Double(pixelCount)
        let mean = sum / count
        let variance = max(0.0, (sumSquares / count) - mean * mean)
        let nonBlackRatio = Double(nonBlack) / count
        let brightRatio = Double(bright) / count

        let mostlyEmpty = nonBlackRatio < 0.06 || brightRatio < 0.015
        let collapsedContrast = nonBlackRatio < 0.20 && variance < 0.0012
        let tooDeep = scale.hi < targetScale.hi * 3.0

        if tooDeep || mostlyEmpty || collapsedContrast {
            poorQualityFrameCount += 1
        } else {
            poorQualityFrameCount = 0
        }

        return poorQualityFrameCount >= 2
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
        let policy = renderPolicy

        // Skip DD tier for real-time — it's too slow per-pixel.
        // Go directly from float to perturbation at scale <= 1e-6.
        let usePerturbation = currentScale <= 1e-6
        let pipeline: MTLComputePipelineState?
        let maxIterations: Int
        if usePerturbation {
            pipeline = computePipelinePerturbation
            maxIterations = min(policy.maxPerturbationIterations, Int(320 + depth * 36))
        } else {
            pipeline = computePipelineFloat
            maxIterations = min(policy.maxFloatIterations, Int(220 + depth * 24))
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

        if shouldEndForVisualQuality(
            pipeline: pipeline,
            maxIterations: maxIterations,
            policy: policy,
            now: CFAbsoluteTimeGetCurrent()
        ) {
            transitionState = .fadingOut
            poorQualityFrameCount = 0
        }

        var uniforms = makeUniforms(
            width: target.texture.width,
            height: target.texture.height,
            maxIterations: maxIterations,
            policy: policy
        )

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(target.texture, index: 0)
        encoder.setBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 0)

        if usePerturbation, let refBuffer = referenceOrbitBuffer {
            encoder.setBuffer(refBuffer, offset: 0, index: 1)
        } else {
            if referenceOrbitBuffer == nil {
                referenceOrbitBuffer = metalDevice?.makeBuffer(length: 16, options: .storageModeShared)
            }
            if let refBuffer = referenceOrbitBuffer {
                encoder.setBuffer(refBuffer, offset: 0, index: 1)
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
