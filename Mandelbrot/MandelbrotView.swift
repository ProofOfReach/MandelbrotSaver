import ScreenSaver
import Metal
import QuartzCore
import simd
import IOKit.ps

@objc(MandelbrotView)
class MandelbrotView: ScreenSaverView {
    // Use a CAMetalLayer directly on ScreenSaverView; avoids legacyScreenSaver subview compositing issues.
    // Pacing stays on ScreenSaverView's animateOneFrame timer (no CVDisplayLink): display-link teardown
    // is fragile in the out-of-process legacyScreenSaver host, and CAMetalLayer's nextDrawable()
    // back-pressure already vsync-locks presentation. ProMotion is reached by matching
    // animationTimeInterval to the screen's maximumFramesPerSecond.
    private let preferDirectMetalLayer = true

    // MARK: - Metal
    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var computePipelineFloat: MTLComputePipelineState?
    private var computePipelinePerturbation: MTLComputePipelineState?
    // Orbit uploads rotate through a small ring so the CPU never rewrites a
    // buffer that a still-in-flight frame may be reading (Julia morphing and
    // the approach pan recompute the orbit every frame; up to
    // maximumDrawableCount frames plus a transition capture can be in flight).
    private var referenceOrbitBuffers: [MTLBuffer?] = [nil, nil, nil, nil]
    private var referenceOrbitRingIndex = 0
    /// The ring slot holding the most recent orbit; bound by encodeFractal.
    private var referenceOrbitBuffer: MTLBuffer?

    private struct OrbitKey {
        var centerXHi: Double, centerXLo: Double
        var centerYHi: Double, centerYLo: Double
        var julia: Bool, juliaCx: Double, juliaCy: Double
        var length: Int
    }
    private var cachedOrbitKey: OrbitKey?
    /// Iterations before the reference orbit escapes (== requested length if
    /// it never escapes). Past this the buffer is zero-padded and the
    /// perturbation math silently drops `c`, so rendering must not exceed it.
    private var referenceOrbitValidLength: Int = 0

    private struct ShaderUniforms {
        var geometry: SIMD4<Float> // centerX_hi, centerY_hi, scale, maxIterations
        var palette: SIMD4<Float>  // colorOffset, aspectRatio, paletteIndex, paletteMix
        var view: SIMD4<Float>     // centerX_lo, centerY_lo, shadingMode, time
        var mode: SIMD4<Float>     // heldBlendWeight, juliaMode, juliaCx, juliaCy
        var quality: SIMD4<Float>  // aaSamples, lightingQuality, edrHeadroom, rotationAngle
        var extra: SIMD4<Float>    // referenceOrbitValidLength, reserved, reserved, reserved
    }

    // Direct display path
    private var metalLayer: CAMetalLayer?


    // MARK: - Configuration Sheet
    private lazy var configureSheetController = ConfigureSheetController()

    // MARK: - Transition State for Freeze-Dissolve Between Dives
    // Instead of fading through black, the outgoing dive's last frame is
    // captured into heldTexture and the incoming dive dissolves in over it.
    private enum TransitionState {
        case zooming
        case capturePending
    }
    private var transitionState: TransitionState = .zooming
    /// 0 → 1 while dissolving away from the held frame; >= 1 means idle.
    private var crossfadeProgress: Float = 1.0
    private let crossfadeDuration: CFAbsoluteTime = 1.4
    private var heldTexture: MTLTexture?
    /// 1x1 black texture bound whenever no real held frame should be read.
    private var dummyHeldTexture: MTLTexture?

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

    // Visual effects
    private var colorOffset: Float = 0.0
    private var currentPalette: Int = 0
    private var paletteMix: Float = 0.0
    private var paletteTimer: Float = 0.0
    private var shadingMode: Int = 0
    private var visualQuality: Int = 1
    private var time: Float = 0.0
    // Slow view rotation; direction and rate re-rolled per dive.
    private var rotationAngle: Float = 0.0
    private var rotationSpeed: Float = 0.012
    // Display EDR headroom (1.0 on SDR panels), refreshed with the power poll.
    private var edrHeadroom: Float = 1.0
    private var autoCyclePalettes: Bool = true
    private var lastPreferenceReload: CFAbsoluteTime = 0
    private var lastLoadedPalettePreference: Int?
    private var lastLoadedAutoCyclePreference: Bool?
    private var lastFrameTime: CFAbsoluteTime = 0
    private var slowFrameCount: Int = 0
    private var zoomStartTime: CFAbsoluteTime = 0
    private let minZoomDuration: CFAbsoluteTime = 24
    private let maxZoomDuration: CFAbsoluteTime = 140
    private let paletteCycleDuration: CFAbsoluteTime = 18

    // MARK: - Power State
    // On battery or in Low Power Mode we cap refresh at 60Hz, lower render
    // scale, and disable supersampling so the saver doesn't drain laptops.
    // Iteration caps stay intact: reducing them can turn near-boundary Julia
    // windows into a solid palette field with no visible fractal.
    private var powerConstrained: Bool = false
    private var lastPowerCheck: CFAbsoluteTime = 0
    private let powerCheckInterval: CFAbsoluteTime = 2.0

    // MARK: - Performance Governor
    // Deep frames are expensive (measured on an M4 at 3024×1964: up to ~1s
    // at the 1600-iteration cap with 4× supersampling — 106 of 238 audited
    // dive frames exceeded 80ms). No fixed quality setting fits every GPU
    // and every depth, so a closed loop watches measured GPU frame time and
    // steps down a quality ladder (supersampling off, then internal
    // resolution) to hold ~30fps, stepping back up when frames are cheap.
    // Iteration budgets are never reduced: cutting them changes what the
    // fractal looks like (audited), while resolution/AA only soften it.
    private struct GovernorLevel {
        let scaleFactor: CGFloat
        let allowSupersampling: Bool
    }
    private static let governorLevels: [GovernorLevel] = [
        GovernorLevel(scaleFactor: 1.0, allowSupersampling: true),
        GovernorLevel(scaleFactor: 1.0, allowSupersampling: false),
        GovernorLevel(scaleFactor: 0.75, allowSupersampling: false),
        GovernorLevel(scaleFactor: 0.5, allowSupersampling: false),
        GovernorLevel(scaleFactor: 0.375, allowSupersampling: false),
    ]
    private var governorIndex: Int = 0
    private var governorLastChange: CFAbsoluteTime = 0
    private var gpuTimeEMA: Double = 0
    private let gpuTimeLock = NSLock()
    private var latestGPUFrameTime: Double = 0
    // Step down above 33ms (below ~30fps), back up below 12ms, with a dwell
    // so a single resize/orbit hitch doesn't thrash the drawable size.
    private let governorHighBudget: Double = 0.033
    private let governorLowBudget: Double = 0.012
    private let governorDwell: CFAbsoluteTime = 2.0

    private struct RenderPolicy {
        var lightingQuality: Int
        var maxFloatIterations: Int
        var maxPerturbationIterations: Int
        var aaSamples: Int
    }

    // MARK: - Julia Set Mode
    private var juliaEnabled: Bool = false
    private var juliaMode: Bool = false
    private var juliaCx: Double = 0.0
    private var juliaCy: Double = 0.0
    // The curated constant this dive orbits around; juliaCx/Cy morph on a
    // small circle whose radius shrinks with the zoom scale, so the set
    // visibly "breathes" at every depth without leaving the audited anchor.
    private var juliaBaseCx: Double = 0.0
    private var juliaBaseCy: Double = 0.0
    private var juliaMorphPhase: Double = 0.0

    private let interestingJuliaC = FractalTargets.julia
    private let interestingPoints = FractalTargets.mandelbrot

    // Next dive's Julia anchor, boundary-searched on a background queue so
    // selectRandomTarget() never runs the multi-ms search on the animation
    // thread. The slot is kept warm even in Mandelbrot mode so toggling the
    // Julia preference mid-run also finds a ready anchor.
    private struct PreparedJuliaAnchor {
        let constantIndex: Int
        let x: Double
        let y: Double
    }
    private var preparedJuliaAnchor: PreparedJuliaAnchor?
    private var juliaAnchorSearchInFlight = false
    private let juliaAnchorLock = NSLock()
    private let juliaAnchorQueue = DispatchQueue(
        label: "MandelbrotSaver.julia-anchor", qos: .utility)

    private var currentTargetIndex: Int = 0
    private var zoomCount: Int = 0
    private var diveStartScale: Double = 3.0

    // MARK: - Initialization

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        loadPreferences()
        observePreferenceChanges()
        setupMetal()
        selectRandomTarget()
        refreshPowerState()
        updateAnimationPacing()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        loadPreferences()
        observePreferenceChanges()
        setupMetal()
        selectRandomTarget()
        refreshPowerState()
        updateAnimationPacing()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimationPacing()
        updateMetalLayerGeometry()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateAnimationPacing()
        updateMetalLayerGeometry()
    }

    // MARK: - Frame Pacing & Power

    /// Native refresh rate of the screen hosting this view (120 on ProMotion).
    private var displayMaxFramesPerSecond: Int {
        let fps = window?.screen?.maximumFramesPerSecond ?? NSScreen.main?.maximumFramesPerSecond ?? 60
        return max(fps, 30)
    }

    /// Target refresh: native rate on AC, capped at 60 when power-constrained.
    private func updateAnimationPacing() {
        let fps = powerConstrained ? min(displayMaxFramesPerSecond, 60) : displayMaxFramesPerSecond
        animationTimeInterval = 1.0 / Double(fps)
        metalLayer?.maximumDrawableCount = powerConstrained ? 2 : 3
    }

    /// Current display EDR headroom, capped so highlights sparkle without
    /// searing at night. 1.0 on SDR panels (tonemap knees at the top of SDR).
    private func refreshEDRHeadroom() {
        let screen = window?.screen ?? NSScreen.main
        let headroom = screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0
        edrHeadroom = Float(min(max(Double(headroom), 1.0), 2.0))
    }

    /// True when running on battery power or Low Power Mode is enabled,
    /// and the user hasn't opted out via the Battery Saver preference.
    private func refreshPowerState() {
        refreshEDRHeadroom()
        guard Preferences.shared.batterySaver else {
            setPowerConstrained(false)
            return
        }

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            setPowerConstrained(true)
            return
        }

        var onBattery = false
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           // Get rule: the returned string is not owned by us — takeUnretainedValue.
           let sourceType = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? {
            onBattery = (sourceType == kIOPSBatteryPowerValue)
        }
        setPowerConstrained(onBattery)
    }

    private func setPowerConstrained(_ constrained: Bool) {
        guard constrained != powerConstrained else { return }
        powerConstrained = constrained
        updateAnimationPacing()
        updateMetalLayerGeometry()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
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
        var policy: RenderPolicy
        if visualQuality >= 1 {
            policy = RenderPolicy(
                lightingQuality: 2,
                maxFloatIterations: 650,
                maxPerturbationIterations: 1600,
                aaSamples: 4
            )
        } else {
            policy = RenderPolicy(
                lightingQuality: 1,
                maxFloatIterations: 450,
                maxPerturbationIterations: 1000,
                aaSamples: 1
            )
        }
        if powerConstrained || !Self.governorLevels[governorIndex].allowSupersampling {
            policy.aaSamples = 1
        }
        return policy
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
        // 16-bit float, linear extended-sRGB: no 8-bit banding anywhere in
        // the pipeline, and components > 1.0 light up EDR headroom on XDR
        // panels (the shader tonemaps into the queried headroom).
        layer.pixelFormat = .rgba16Float
        layer.framebufferOnly = false
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        layer.wantsExtendedDynamicRangeContent = true
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
        let cap: CGFloat = powerConstrained ? 1.5 : 2.0
        let base = min(max(backingScale, 1.0), cap)
        return base * Self.governorLevels[governorIndex].scaleFactor
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
        zoomStartTime = CFAbsoluteTimeGetCurrent()

        if juliaEnabled {
            juliaMode = true
            // Zoom toward a point ON the Julia set boundary. Several curated
            // constants have set-interior at the origin, so diving into (0,0)
            // ended black; the boundary is fractal everywhere, so it always
            // has structure at depth. The anchor was boundary-searched in the
            // background during the previous dive; the inline fallback only
            // fires on the very first selection after init or a mode toggle.
            let anchor = takePreparedJuliaAnchor() ?? searchJuliaAnchorNow()
            let juliaC = interestingJuliaC[anchor.constantIndex]
            juliaBaseCx = juliaC.cx
            juliaBaseCy = juliaC.cy
            juliaMorphPhase = Double.random(in: 0..<(2.0 * .pi))
            juliaCx = juliaBaseCx
            juliaCy = juliaBaseCy
            targetCenterX = DoubleDouble(anchor.x)
            targetCenterY = DoubleDouble(anchor.y)
            // Julia anchors are precision-fragile (the reference orbit and
            // budget depend on the exact boundary point), so Julia dives
            // start centered rather than panning in.
            centerX = targetCenterX
            centerY = targetCenterY
            targetScale = DoubleDouble(3e-5)
            diveStartScale = 3.0
        } else {
            juliaMode = false
            let target = interestingPoints[currentTargetIndex]
            targetCenterX = DoubleDouble(target.x)
            targetCenterY = DoubleDouble(target.y)
            targetScale = DoubleDouble(target.minScale)
            // Targets whose approach crosses a black bottleneck open below it
            // (see MandelbrotTarget.startScale) so no shown frame is a black
            // screen or a featureless color wash.
            diveStartScale = Double(target.startScale) ?? 3.0
            // Off-center approach: open with the anchor away from screen
            // center and let the pan easing carry it in, so dives aren't all
            // fixed-center zooms. The offset is a fraction of the start scale
            // (anchor stays comfortably on screen) and decays in view units
            // (see updateAnimation), so it can never outrun the zoom.
            let offsetAngle = Double.random(in: 0..<(2.0 * .pi))
            let offsetMag = 0.18 * diveStartScale
            centerX = targetCenterX + DoubleDouble(cos(offsetAngle) * offsetMag * 1.4)
            centerY = targetCenterY + DoubleDouble(sin(offsetAngle) * offsetMag)
        }

        // Fresh slow-rotation direction and rate for this dive.
        rotationSpeed = Float(Double.random(in: 0.006...0.018)) * (Bool.random() ? 1.0 : -1.0)

        scale = DoubleDouble(diveStartScale)
        prepareNextJuliaAnchor()
    }

    /// Consumes the background-prepared Julia anchor, if one is ready.
    private func takePreparedJuliaAnchor() -> PreparedJuliaAnchor? {
        juliaAnchorLock.lock()
        defer { juliaAnchorLock.unlock() }
        let anchor = preparedJuliaAnchor
        preparedJuliaAnchor = nil
        return anchor
    }

    /// Boundary-searches the next dive's Julia anchor on a background queue.
    /// No-op while a result is already waiting or a search is running.
    private func prepareNextJuliaAnchor() {
        juliaAnchorLock.lock()
        if preparedJuliaAnchor != nil || juliaAnchorSearchInFlight {
            juliaAnchorLock.unlock()
            return
        }
        juliaAnchorSearchInFlight = true
        juliaAnchorLock.unlock()

        let constantIndex = Int.random(in: 0..<interestingJuliaC.count)
        let constant = interestingJuliaC[constantIndex]
        juliaAnchorQueue.async { [weak self] in
            let point = JuliaAnchor.boundaryPoint(cx: constant.cx, cy: constant.cy)
            guard let self else { return }
            self.juliaAnchorLock.lock()
            self.preparedJuliaAnchor = PreparedJuliaAnchor(
                constantIndex: constantIndex, x: point.x, y: point.y)
            self.juliaAnchorSearchInFlight = false
            self.juliaAnchorLock.unlock()
        }
    }

    /// Inline anchor search, used only when no background result is ready
    /// (first selection after init, or a Julia toggle racing the first
    /// prepare). A few ms of CPU.
    private func searchJuliaAnchorNow() -> PreparedJuliaAnchor {
        let constantIndex = Int.random(in: 0..<interestingJuliaC.count)
        let constant = interestingJuliaC[constantIndex]
        let point = JuliaAnchor.boundaryPoint(cx: constant.cx, cy: constant.cy)
        return PreparedJuliaAnchor(constantIndex: constantIndex, x: point.x, y: point.y)
    }

    private func updateAnimation() {
        // Track frame time - bail out if rendering is too slow
        let now = CFAbsoluteTimeGetCurrent()
        let frameDelta: CFAbsoluteTime
        if lastFrameTime > 0 {
            let dt = now - lastFrameTime
            frameDelta = min(max(dt, 1.0 / 120.0), 0.1)
            // True-stall detector only. Expected load (deep frames on a slow
            // GPU) is the governor's job; with 0.08s here every deep dive
            // got aborted mid-way and the saver degenerated into an endless
            // shallow zoom-pan-dissolve loop.
            if dt > 0.4 {
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
        refreshPowerStateIfNeeded(now: now)
        updateGovernor(now: now)

        switch transitionState {
        case .zooming:
            let zoomElapsed = now - zoomStartTime
            let diveFinished = scale.hi < targetScale.hi * 2.0
            // Stalls only count once the governor has nothing left to give;
            // while it's still stepping down, slow frames are being handled.
            let governorAtFloor = governorIndex == Self.governorLevels.count - 1
            let diveStalled = ((slowFrameCount >= 3 && governorAtFloor) || zoomElapsed > zoomDurationLimit)
                && crossfadeProgress >= 1.0
            if diveFinished || diveStalled {
                slowFrameCount = 0
                // renderFrame captures the outgoing frame into heldTexture,
                // selects the next target, and starts the dissolve.
                transitionState = .capturePending
            } else {
                scale = scale * pow(zoomSpeed.hi, frameScale)

                // Off-center approach: decay the center → anchor offset a
                // touch faster than the zoom shrinks the view, so the anchor
                // glides toward screen center and can never fall behind the
                // zoom at any configured speed. Snap once sub-pixel so the
                // perturbation orbit cache stops missing.
                let dx = centerX - targetCenterX
                let dy = centerY - targetCenterY
                if max(abs(dx.hi), abs(dy.hi)) < scale.hi * 2e-4 {
                    centerX = targetCenterX
                    centerY = targetCenterY
                } else {
                    let keep = pow(zoomSpeed.hi * 0.995, frameScale)
                    centerX = targetCenterX + dx * keep
                    centerY = targetCenterY + dy * keep
                }
            }

        case .capturePending:
            break
        }

        if crossfadeProgress < 1.0 {
            crossfadeProgress = min(crossfadeProgress + Float(frameDelta / crossfadeDuration), 1.0)
        }

        rotationAngle += rotationSpeed * Float(frameDelta)

        if juliaMode {
            // Morph the Julia constant on a small circle; the radius shrinks
            // with the view so the structural "flow" stays gentle on screen
            // and the audited boundary anchor remains valid at depth.
            juliaMorphPhase += frameDelta * 0.3
            let radius = min(0.004, 0.15 * scale.hi)
            juliaCx = juliaBaseCx + radius * cos(juliaMorphPhase)
            juliaCy = juliaBaseCy + radius * sin(juliaMorphPhase)
        }

        colorOffset += Float(frameDelta * 8.0)
        if colorOffset > 10000.0 {
            colorOffset = 0.0
        }

        if autoCyclePalettes {
            paletteTimer += Float(frameDelta / paletteCycleDuration)
            if paletteTimer >= 1.0 {
                paletteTimer = paletteTimer.truncatingRemainder(dividingBy: 1.0)
                currentPalette = (currentPalette + 1) % Preferences.paletteNames.count
            }
            // Dwell on each palette, then a short smoothstep crossfade at the
            // end of the cycle. The previous linear full-cycle ramp kept the
            // display in muddy two-palette blends almost all of the time.
            let fadeStart: Float = 0.8
            if paletteTimer <= fadeStart {
                paletteMix = 0.0
            } else {
                let f = (paletteTimer - fadeStart) / (1.0 - fadeStart)
                paletteMix = f * f * (3.0 - 2.0 * f)
            }
        } else {
            paletteMix = 0.0
        }

        time += Float(frameDelta)
    }

    // Same-process changes arrive via Preferences.didChangeNotification; this
    // slow poll only catches writes from another process (System Settings).
    private func reloadPreferencesIfNeeded(now: CFAbsoluteTime) {
        guard now - lastPreferenceReload >= 5.0 else { return }
        lastPreferenceReload = now
        loadPreferences()
    }

    private func refreshPowerStateIfNeeded(now: CFAbsoluteTime) {
        guard now - lastPowerCheck >= powerCheckInterval else { return }
        lastPowerCheck = now
        refreshPowerState()
    }

    private var zoomDurationLimit: CFAbsoluteTime {
        let target = max(targetScale.hi * 2.0, 1e-12)
        let start = diveStartScale
        let speed = min(max(zoomSpeed.hi, 0.0001), 0.9999)
        let estimatedFrames = log(target / start) / log(speed)
        // 1.25× grace: frameDelta is clamped to 0.1s, so heavy frames make
        // zoom progress lag wall time a little — without slack the dive
        // would be cut just before reaching depth.
        let estimatedSeconds = estimatedFrames / 60.0 * 1.25
        return min(max(estimatedSeconds, minZoomDuration), maxZoomDuration)
    }

    /// Closed-loop quality control: folds the latest measured GPU frame time
    /// into an EMA and walks the governor ladder to hold the frame budget.
    /// Level changes resize the drawable, which breaks held-frame dissolve
    /// dimensions, so they only happen between crossfades and after a dwell.
    private func updateGovernor(now: CFAbsoluteTime) {
        gpuTimeLock.lock()
        let sample = latestGPUFrameTime
        latestGPUFrameTime = 0
        gpuTimeLock.unlock()
        if sample > 0 {
            gpuTimeEMA = gpuTimeEMA == 0 ? sample : gpuTimeEMA * 0.8 + sample * 0.2
        }

        guard gpuTimeEMA > 0,
              crossfadeProgress >= 1.0,
              now - governorLastChange >= governorDwell else { return }

        var newIndex = governorIndex
        if gpuTimeEMA > governorHighBudget, governorIndex < Self.governorLevels.count - 1 {
            newIndex += 1
        } else if gpuTimeEMA < governorLowBudget, governorIndex > 0 {
            newIndex -= 1
        }
        guard newIndex != governorIndex else { return }
        governorIndex = newIndex
        governorLastChange = now
        // Old-level samples no longer describe the new cost; re-measure.
        gpuTimeEMA = 0
        updateMetalLayerGeometry()
    }

    // MARK: - Perturbation Theory Helper

    private func updateReferenceOrbit(maxIterations: Int) -> Bool {
        guard let device = metalDevice else { return false }

        // The reference orbit depends only on the anchor point (center / Julia c)
        // and length. The auto-pilot pins the center to the target for the whole
        // zoom, so this cache makes the DD orbit a once-per-target cost instead
        // of a per-frame one.
        if let cached = cachedOrbitKey,
           cached.centerXHi == centerX.hi, cached.centerXLo == centerX.lo,
           cached.centerYHi == centerY.hi, cached.centerYLo == centerY.lo,
           cached.julia == juliaMode,
           cached.juliaCx == juliaCx, cached.juliaCy == juliaCy,
           cached.length >= maxIterations,
           referenceOrbitBuffer != nil {
            return true
        }

        let bufferLength = maxIterations * MemoryLayout<SIMD4<Float>>.size
        let nextIndex = (referenceOrbitRingIndex + 1) % referenceOrbitBuffers.count
        var slot = referenceOrbitBuffers[nextIndex]
        if slot == nil || slot!.length < bufferLength {
            slot = device.makeBuffer(length: bufferLength, options: .storageModeShared)
            referenceOrbitBuffers[nextIndex] = slot
        }
        guard let buffer = slot else { return false }
        referenceOrbitRingIndex = nextIndex
        referenceOrbitBuffer = buffer
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

            // Same escape radius (256) as the shader, so pixels that shadow
            // the reference can escape at the exact matching index.
            if zr2.hi + zi2.hi > 65536.0 {
                referenceOrbitValidLength = i
                for j in i..<maxIterations {
                    pointer[j] = SIMD4<Float>(0, 0, 0, 0)
                }
                break
            }
            referenceOrbitValidLength = i + 1

            let next_zi = (cur_zr * cur_zi * two) + c_imag
            let next_zr = (zr2 - zi2) + c_real

            let f_next_zr = Float(next_zr.hi)
            let f_next_zi = Float(next_zi.hi)

            // Residual the shader adds each step so the delta recurrence
            // stays consistent with the float-rounded orbit it iterates
            // against: (Z_f² + c) − Z_next_f. The two sides agree to ~ULP,
            // so the cancellation must happen in double — evaluated in float
            // the residual is mostly rounding noise of its own magnitude.
            let d_zr = Double(f_zr)
            let d_zi = Double(f_zi)
            let d_iter_zr = d_zr * d_zr - d_zi * d_zi + c_real.hi
            let d_iter_zi = 2.0 * d_zr * d_zi + c_imag.hi
            let delta_r = Float(d_iter_zr - Double(f_next_zr))
            let delta_i = Float(d_iter_zi - Double(f_next_zi))

            pointer[i] = SIMD4<Float>(f_zr, f_zi, delta_r, delta_i)

            cur_zr = next_zr
            cur_zi = next_zi
        }

        cachedOrbitKey = OrbitKey(
            centerXHi: centerX.hi, centerXLo: centerX.lo,
            centerYHi: centerY.hi, centerYLo: centerY.lo,
            julia: juliaMode, juliaCx: juliaCx, juliaCy: juliaCy,
            length: maxIterations
        )
        return true
    }

    private struct RenderTarget {
        let texture: MTLTexture
        let drawable: CAMetalDrawable
    }

    private func acquireRenderTarget() -> RenderTarget? {
        guard let metalLayer, let drawable = metalLayer.nextDrawable() else { return nil }
        return RenderTarget(texture: drawable.texture, drawable: drawable)
    }

    private func makeUniforms(width: Int, height: Int, maxIterations: Int, policy: RenderPolicy, heldWeight: Float) -> ShaderUniforms {
        let aspectRatio = Float(width) / Float(max(height, 1))
        return ShaderUniforms(
            geometry: SIMD4<Float>(Float(centerX.hi), Float(centerY.hi), Float(scale.hi), Float(maxIterations)),
            palette: SIMD4<Float>(colorOffset, aspectRatio, Float(currentPalette), paletteMix),
            view: SIMD4<Float>(Float(centerX.lo), Float(centerY.lo), Float(shadingMode), time),
            mode: SIMD4<Float>(heldWeight, juliaMode ? 1.0 : 0.0, Float(juliaCx), Float(juliaCy)),
            quality: SIMD4<Float>(Float(policy.aaSamples), Float(policy.lightingQuality), edrHeadroom, rotationAngle),
            extra: SIMD4<Float>(Float(referenceOrbitValidLength), 0.0, 0.0, 0.0)
        )
    }

    private struct FramePlan {
        let pipeline: MTLComputePipelineState
        let maxIterations: Int
        let policy: RenderPolicy
        let usesReferenceOrbit: Bool
    }

    /// Picks the precision path and iteration budget for the current state,
    /// refreshing the reference orbit when the perturbation path is chosen.
    private func planFrame(textureHeight: Int) -> FramePlan? {
        let currentScale = scale.hi
        let policy = renderPolicy

        // Skip the DD tier for real-time — it's too slow per-pixel. Hand off
        // from float32 to perturbation while float still has margin: c
        // quantizes to the ULP at the center's magnitude, so switch as soon
        // as a pixel spans fewer than ~8 quanta on this display. (A fixed
        // 1e-4 handoff left up to a half-decade of visibly blocky frames for
        // targets with |c| > 1 on Retina panels.) Perturbation costs about
        // the same per iteration, so switching early is safe.
        let coordinateMagnitude = max(abs(centerX.hi), abs(centerY.hi)) + currentScale
        let ulp = Double(Float(coordinateMagnitude).ulp)
        let handoffScale = min(5e-3, max(1e-4, 8.0 * ulp * Double(max(textureHeight, 1))))
        let usePerturbation = currentScale <= handoffScale

        // The float-path depth ramp, tuned for the Mandelbrot exterior
        // approach. Julia dives anchor to boundary points whose mid-dive
        // windows can need most of the anchor's escape time well before the
        // handoff (audited: Pinwheel needs p95≈556 at scale 9.5e-4, where the
        // ramp gives ~300 — a black screen), so Julia frames get the full
        // float budget. Also the anchor the perturbation ramp continues from,
        // so the handoff frame has budget continuity (no detail "pop" when
        // crossing the precision boundary).
        func floatBudget(at scale: Double) -> Int {
            if juliaMode { return policy.maxFloatIterations }
            let depth = max(0.0, log10(3.0 / scale))
            return min(policy.maxFloatIterations, 220 + Int(depth * 24.0))
        }

        let pipeline: MTLComputePipelineState?
        let maxIterations: Int
        let usesReferenceOrbit: Bool
        if usePerturbation && updateReferenceOrbit(maxIterations: policy.maxPerturbationIterations) {
            // Compute at the full cap so the cached orbit stays valid for the
            // entire zoom into this target.
            pipeline = computePipelinePerturbation
            usesReferenceOrbit = true
            // Continue the float ramp from the handoff, doubling the budget
            // per decade of further depth: full cap by end-of-dive scales
            // (curated views need median escape counts of 300-1400) with no
            // single-frame jump at the handoff.
            let decadesPast = max(0.0, log10(handoffScale / max(currentScale, 1e-300)))
            let ramp = Double(floatBudget(at: handoffScale)) * pow(2.0, decadesPast)
            var budget = min(policy.maxPerturbationIterations, max(Int(ramp), 64))
            if juliaMode {
                // Julia references can't rebase (their orbit starts at the
                // anchor, not 0), so the budget must never exceed the orbit's
                // pre-escape length — past it the zero-padded buffer silently
                // drops c from the recurrence. No 64-iteration floor here for
                // the same reason. Mandelbrot wraps via rebasing instead.
                budget = min(budget, max(referenceOrbitValidLength, 1))
            }
            maxIterations = budget
        } else {
            pipeline = computePipelineFloat
            usesReferenceOrbit = false
            maxIterations = floatBudget(at: currentScale)
        }
        guard let pipeline else { return nil }
        return FramePlan(
            pipeline: pipeline,
            maxIterations: maxIterations,
            policy: policy,
            usesReferenceOrbit: usesReferenceOrbit
        )
    }

    private func ensureDummyHeldTexture() -> MTLTexture? {
        if let dummy = dummyHeldTexture { return dummy }
        guard let device = metalDevice else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        var zero: UInt64 = 0
        withUnsafeBytes(of: &zero) { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                withBytes: bytes.baseAddress!, bytesPerRow: 8)
        }
        dummyHeldTexture = texture
        return texture
    }

    private func ensureHeldTexture(width: Int, height: Int) -> MTLTexture? {
        if let held = heldTexture, held.width == width, held.height == height {
            return held
        }
        guard let device = metalDevice, width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        heldTexture = device.makeTexture(descriptor: descriptor)
        return heldTexture
    }

    private func encodeFractal(
        into texture: MTLTexture,
        held: MTLTexture,
        heldWeight: Float,
        plan: FramePlan,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }

        if plan.usesReferenceOrbit {
            guard let refBuffer = referenceOrbitBuffer else {
                encoder.endEncoding()
                return false
            }
            encoder.setBuffer(refBuffer, offset: 0, index: 1)
        }

        var uniforms = makeUniforms(
            width: texture.width,
            height: texture.height,
            maxIterations: plan.maxIterations,
            policy: plan.policy,
            heldWeight: heldWeight
        )

        encoder.setComputePipelineState(plan.pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setTexture(held, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.size, index: 0)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (texture.width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (texture.height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        return true
    }

    /// Renders the outgoing dive's frame into heldTexture so the next dive
    /// can dissolve in over it. Returns false when no direct-layer target is
    /// available.
    private func captureOutgoingFrame() -> Bool {
        guard let layer = metalLayer, let commandQueue else { return false }
        let size = layer.drawableSize
        guard let held = ensureHeldTexture(width: Int(size.width), height: Int(size.height)),
              let dummy = ensureDummyHeldTexture(),
              let plan = planFrame(textureHeight: held.height),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              encodeFractal(into: held, held: dummy, heldWeight: 0.0, plan: plan, commandBuffer: commandBuffer)
        else { return false }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return true
    }

    @discardableResult
    private func renderFrame() -> Bool {
        guard let commandQueue else { return false }

        // A missing drawable means this frame cannot be presented, including
        // a pending transition. Leave its state intact for the next frame.
        guard let target = acquireRenderTarget() else { return false }

        // Dive boundary: freeze the outgoing frame, move to the next target,
        // and dissolve into it. Hard cut when capture isn't possible.
        if transitionState == .capturePending {
            let captured = captureOutgoingFrame()
            selectRandomTarget()
            transitionState = .zooming
            crossfadeProgress = captured ? 0.0 : 1.0
        }

        guard let plan = planFrame(textureHeight: target.texture.height),
              let dummy = ensureDummyHeldTexture(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return false
        }

        var held: MTLTexture = dummy
        var heldWeight: Float = 0.0
        if crossfadeProgress < 1.0,
           let heldFrame = heldTexture,
           heldFrame.width == target.texture.width,
           heldFrame.height == target.texture.height {
            let p = crossfadeProgress
            heldWeight = 1.0 - (p * p * (3.0 - 2.0 * p))
            held = heldFrame
        }

        guard encodeFractal(
            into: target.texture, held: held, heldWeight: heldWeight,
            plan: plan, commandBuffer: commandBuffer)
        else { return false }

        commandBuffer.present(target.drawable)
        // Feed the performance governor. The handler runs on Metal's
        // completion queue; the animation thread consumes the sample on
        // its next tick.
        commandBuffer.addCompletedHandler { [weak self] cb in
            guard let self else { return }
            let gpuTime = cb.gpuEndTime - cb.gpuStartTime
            guard gpuTime > 0 else { return }
            self.gpuTimeLock.lock()
            self.latestGPUFrameTime = gpuTime
            self.gpuTimeLock.unlock()
        }
        commandBuffer.commit()
        return false
    }


    override func animateOneFrame() {
        updateAnimation()
        renderFrame()
    }

    // MARK: - Configuration Sheet

    override var hasConfigureSheet: Bool {
        // macOS 26.5's legacyScreenSaver extension crashes inside Apple's
        // presentConfiguration path before loading third-party bundle code.
        // Hide the broken system button on affected releases; build.sh also
        // installs a standalone settings app using the same controller.
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return !(version.majorVersion == 26 && version.minorVersion <= 5)
    }

    override var configureSheet: NSWindow? {
        configureSheetController.configureSheet()
    }
}
