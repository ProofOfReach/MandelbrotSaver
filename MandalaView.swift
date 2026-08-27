import ScreenSaver
import Metal
import QuartzCore
import simd
import IOKit.ps

@objc(MandalaView)
final class MandalaView: ScreenSaverView {
    // MARK: - Metal

    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var computePipeline: MTLComputePipelineState?
    private var metalLayer: CAMetalLayer?

    private struct MandalaUniforms {
        var viewport: SIMD4<Float> // globalTime, sceneTime, sceneProgress, aspectRatio
        var scene: SIMD4<Float>    // seed, symmetry, motif, rotationDirection
        var motion: SIMD4<Float>   // flowSpeed, intensity, twist, tunnelRate
        var palette: SIMD4<Float>  // paletteIndex, paletteMix, colorPhase, EDR headroom
        var quality: SIMD4<Float>  // sampleCount, heldWeight, breathRate, exposure
    }

    // MARK: - Presentation

    private var heldTexture: MTLTexture?
    private var dummyHeldTexture: MTLTexture?

    private struct RenderTarget {
        let texture: MTLTexture
        let drawable: CAMetalDrawable
    }

    // MARK: - Scene state

    private enum TransitionState {
        case playing
        case capturePending
    }

    private var sceneGenerator = MandalaSceneGenerator(seed: UInt64.random(in: 1...UInt64.max))
    private var currentScene = MandalaScene.initial
    private var transitionState: TransitionState = .playing
    private var sceneRefreshRequested = false
    private var sceneElapsed: CFAbsoluteTime = 0.0
    private var crossfadeProgress: Float = 1.0
    private let crossfadeDuration: CFAbsoluteTime = 2.4

    private var globalTime: Float = 0.0
    private var colorPhase: Float = 0.0
    private var paletteTimer: Float = 0.0
    private var currentPalette = 0
    private var paletteMix: Float = 0.0
    private let paletteCycleDuration: CFAbsoluteTime = 28.0

    // MARK: - Preferences

    private var motionSpeed: Float = 1.0
    private var intensity: Float = 0.92
    private var forcedSymmetry: Int?
    private var autoCyclePalettes = true
    private var visualQuality = 1
    private var batterySaver = true
    private var lastLoadedPalette: Int?
    private var lastLoadedAutoCycle: Bool?
    private var lastPreferenceReload: CFAbsoluteTime = 0.0
    private let preferenceReloadInterval: CFAbsoluteTime = 5.0

    private lazy var configureSheetController = ConfigureSheetController()

    // MARK: - Timing, power, and performance

    private var lastFrameTime: CFAbsoluteTime = 0.0
    private var powerConstrained = false
    private var lastPowerCheck: CFAbsoluteTime = 0.0
    private let powerCheckInterval: CFAbsoluteTime = 2.0
    private var edrHeadroom: Float = 1.0

    private struct GovernorLevel {
        let scaleFactor: CGFloat
        let allowSupersampling: Bool
    }

    private static let governorLevels = [
        GovernorLevel(scaleFactor: 1.0, allowSupersampling: true),
        GovernorLevel(scaleFactor: 1.0, allowSupersampling: false),
        GovernorLevel(scaleFactor: 0.75, allowSupersampling: false),
        GovernorLevel(scaleFactor: 0.67, allowSupersampling: false),
    ]

    private var governorIndex = 0
    private var governorLastChange: CFAbsoluteTime = 0.0
    private var gpuTimeEMA = 0.0
    private let gpuTimeLock = NSLock()
    private var latestGPUFrameTime = 0.0
    private let governorHighBudget = 0.028
    private let governorLowBudget = 0.010
    private let governorDwell: CFAbsoluteTime = 3.0

    // MARK: - Lifecycle

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        initializeSaver()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        initializeSaver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func initializeSaver() {
        wantsLayer = true
        loadPreferences()
        observePreferenceChanges()
        setupMetal()
        selectNextScene()
        refreshPowerState()
        updateAnimationPacing()
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

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateMetalLayerGeometry()
    }

    // MARK: - Preferences

    private func observePreferenceChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange(_:)),
            name: Preferences.didChangeNotification,
            object: nil
        )
    }

    @objc private func preferencesDidChange(_ notification: Notification) {
        loadPreferences()
        refreshPowerState()
        updateAnimationPacing()
    }

    private func loadPreferences() {
        let prefs = Preferences.shared
        let previousQuality = visualQuality
        let previousSymmetry = forcedSymmetry
        let newPalette = prefs.paletteIndex
        let newAutoCycle = prefs.autoCyclePalettes

        motionSpeed = Float(prefs.motionSpeed)
        intensity = prefs.intensityValue
        forcedSymmetry = prefs.forcedSymmetry
        autoCyclePalettes = newAutoCycle
        visualQuality = prefs.visualQuality
        batterySaver = prefs.batterySaver

        if lastLoadedPalette != newPalette {
            currentPalette = newPalette
            paletteTimer = 0.0
            paletteMix = 0.0
            lastLoadedPalette = newPalette
        }
        if lastLoadedAutoCycle != newAutoCycle {
            paletteTimer = 0.0
            paletteMix = 0.0
            lastLoadedAutoCycle = newAutoCycle
        }

        if lastFrameTime > 0.0, previousSymmetry != forcedSymmetry {
            sceneRefreshRequested = true
        }
        if previousQuality != visualQuality {
            updateMetalLayerGeometry()
        }
    }

    private func reloadPreferencesIfNeeded(now: CFAbsoluteTime) {
        guard now - lastPreferenceReload >= preferenceReloadInterval else { return }
        lastPreferenceReload = now
        loadPreferences()
    }

    // MARK: - Metal setup

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            NSLog("HyperspaceBloom: failed to create a Metal device")
            return
        }

        metalDevice = device
        commandQueue = device.makeCommandQueue()

        let bundle = Bundle(for: type(of: self))
        guard let libraryURL = bundle.url(forResource: "default", withExtension: "metallib") else {
            NSLog("HyperspaceBloom: default.metallib is missing")
            return
        }

        do {
            let library = try device.makeLibrary(URL: libraryURL)
            guard let function = library.makeFunction(name: "mandalaKernel") else {
                NSLog("HyperspaceBloom: mandalaKernel is missing")
                return
            }
            computePipeline = try device.makeComputePipelineState(function: function)
        } catch {
            NSLog("HyperspaceBloom: failed to create the compute pipeline: \(error)")
            return
        }

        setupDirectMetalLayer(device: device)
    }

    private func setupDirectMetalLayer(device: MTLDevice) {
        let directLayer = CAMetalLayer()
        directLayer.device = device
        directLayer.pixelFormat = .rgba16Float
        directLayer.framebufferOnly = false
        directLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        directLayer.wantsExtendedDynamicRangeContent = true
        directLayer.isOpaque = true
        directLayer.maximumDrawableCount = 3

        layer = directLayer
        metalLayer = directLayer
        updateMetalLayerGeometry()
    }

    private func currentRenderSize() -> CGSize {
        if bounds.width >= 2.0, bounds.height >= 2.0 {
            return bounds.size
        }
        if let contentBounds = window?.contentView?.bounds,
           contentBounds.width >= 2.0, contentBounds.height >= 2.0 {
            return contentBounds.size
        }
        return isPreview ? CGSize(width: 400, height: 240) : CGSize(width: 800, height: 600)
    }

    private func currentRenderScale() -> CGFloat {
        let governorScale = Self.governorLevels[governorIndex].scaleFactor
        if isPreview { return governorScale }

        let backingScale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2.0
        let qualityCap: CGFloat = visualQuality == 0 ? 1.5 : 2.0
        let cap: CGFloat = powerConstrained ? min(qualityCap, 1.5) : qualityCap
        return min(max(backingScale, 1.0), cap) * governorScale
    }

    private func updateMetalLayerGeometry() {
        guard let metalLayer else { return }
        metalLayer.frame = bounds
        let size = currentRenderSize()
        let scale = currentRenderScale()
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: max(1, Int(size.width * scale)),
            height: max(1, Int(size.height * scale))
        )
    }

    // MARK: - Power and pacing

    private var displayMaxFramesPerSecond: Int {
        let fps = window?.screen?.maximumFramesPerSecond
            ?? NSScreen.main?.maximumFramesPerSecond
            ?? 60
        return max(fps, 30)
    }

    private func updateAnimationPacing() {
        let qualityLimitedFPS = governorIndex == Self.governorLevels.count - 1 ? 30 : displayMaxFramesPerSecond
        let fps = powerConstrained
            ? min(qualityLimitedFPS, 60)
            : qualityLimitedFPS
        animationTimeInterval = 1.0 / Double(fps)
        metalLayer?.maximumDrawableCount = powerConstrained ? 2 : 3
    }

    private func refreshPowerState() {
        let screen = window?.screen ?? NSScreen.main
        let headroom = screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0
        edrHeadroom = Float(min(max(Double(headroom), 1.0), 2.0))

        guard batterySaver else {
            setPowerConstrained(false)
            return
        }

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            setPowerConstrained(true)
            return
        }

        var onBattery = false
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? {
            onBattery = source == kIOPSBatteryPowerValue
        }
        setPowerConstrained(onBattery)
    }

    private func refreshPowerStateIfNeeded(now: CFAbsoluteTime) {
        guard now - lastPowerCheck >= powerCheckInterval else { return }
        lastPowerCheck = now
        refreshPowerState()
    }

    private func setPowerConstrained(_ constrained: Bool) {
        guard constrained != powerConstrained else { return }
        powerConstrained = constrained
        governorIndex = constrained ? max(governorIndex, 1) : governorIndex
        updateAnimationPacing()
        updateMetalLayerGeometry()
    }

    // MARK: - Scene animation

    private func selectNextScene() {
        currentScene = sceneGenerator.next(forcedSymmetry: forcedSymmetry)
        sceneElapsed = 0.0
        sceneRefreshRequested = false
    }

    private func updateAnimation() {
        let now = CFAbsoluteTimeGetCurrent()
        let frameDelta: CFAbsoluteTime
        if lastFrameTime > 0.0 {
            frameDelta = min(max(now - lastFrameTime, 1.0 / 240.0), 0.1)
        } else {
            frameDelta = animationTimeInterval
        }
        lastFrameTime = now

        reloadPreferencesIfNeeded(now: now)
        refreshPowerStateIfNeeded(now: now)
        updateGovernor(now: now)

        globalTime += Float(frameDelta)
        sceneElapsed += frameDelta
        colorPhase = (colorPhase + Float(frameDelta) * 0.0045 * motionSpeed)
            .truncatingRemainder(dividingBy: 1.0)

        if (sceneElapsed >= currentScene.duration || sceneRefreshRequested),
           transitionState == .playing, crossfadeProgress >= 1.0 {
            transitionState = .capturePending
        }

        if crossfadeProgress < 1.0 {
            crossfadeProgress = min(
                crossfadeProgress + Float(frameDelta / crossfadeDuration),
                1.0
            )
        }

        updatePaletteCycle(frameDelta: frameDelta)
    }

    private func updatePaletteCycle(frameDelta: CFAbsoluteTime) {
        guard autoCyclePalettes else {
            paletteMix = 0.0
            return
        }

        paletteTimer += Float(frameDelta / paletteCycleDuration)
        if paletteTimer >= 1.0 {
            paletteTimer = paletteTimer.truncatingRemainder(dividingBy: 1.0)
            currentPalette = (currentPalette + 1) % Preferences.paletteNames.count
        }

        // Keep complementary palettes from lingering in a desaturated middle.
        // At the 28-second cadence this yields a roughly three-second blend.
        let fadeStart: Float = 0.89
        if paletteTimer <= fadeStart {
            paletteMix = 0.0
        } else {
            let x = (paletteTimer - fadeStart) / (1.0 - fadeStart)
            paletteMix = x * x * (3.0 - 2.0 * x)
        }
    }

    // MARK: - Performance governor

    private var supersamplingAllowed: Bool {
        return visualQuality > 0
            && !powerConstrained
            && Self.governorLevels[governorIndex].allowSupersampling
    }

    private func updateGovernor(now: CFAbsoluteTime) {
        gpuTimeLock.lock()
        let sample = latestGPUFrameTime
        latestGPUFrameTime = 0.0
        gpuTimeLock.unlock()

        if sample > 0.0 {
            gpuTimeEMA = gpuTimeEMA == 0.0 ? sample : gpuTimeEMA * 0.82 + sample * 0.18
        }

        guard gpuTimeEMA > 0.0,
              crossfadeProgress >= 1.0,
              now - governorLastChange >= governorDwell else { return }

        var nextIndex = governorIndex
        if gpuTimeEMA > governorHighBudget, governorIndex < Self.governorLevels.count - 1 {
            nextIndex += 1
        } else if gpuTimeEMA < governorLowBudget, governorIndex > 0, !powerConstrained {
            nextIndex -= 1
        }

        guard nextIndex != governorIndex else { return }
        governorIndex = nextIndex
        governorLastChange = now
        gpuTimeEMA = 0.0
        updateMetalLayerGeometry()
        updateAnimationPacing()
    }

    // MARK: - Render resources

    private func ensureDummyHeldTexture() -> MTLTexture? {
        if let dummyHeldTexture { return dummyHeldTexture }
        guard let device = metalDevice else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        var clearPixel: UInt64 = 0
        withUnsafeBytes(of: &clearPixel) { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: 8
            )
        }
        dummyHeldTexture = texture
        return texture
    }

    private func ensureHeldTexture(width: Int, height: Int) -> MTLTexture? {
        if let heldTexture, heldTexture.width == width, heldTexture.height == height {
            return heldTexture
        }
        guard let device = metalDevice, width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        heldTexture = device.makeTexture(descriptor: descriptor)
        return heldTexture
    }


    private func acquireRenderTarget() -> RenderTarget? {
        guard let metalLayer, let drawable = metalLayer.nextDrawable() else { return nil }
        return RenderTarget(texture: drawable.texture, drawable: drawable)
    }

    // MARK: - Encoding

    private func makeUniforms(for texture: MTLTexture, heldWeight: Float) -> MandalaUniforms {
        let progress = Float(min(max(sceneElapsed / max(currentScene.duration, 0.001), 0.0), 1.0))
        let aspect = Float(texture.width) / Float(max(texture.height, 1))
        let samples: Float = supersamplingAllowed ? 4.0 : 1.0
        return MandalaUniforms(
            viewport: SIMD4<Float>(globalTime, Float(sceneElapsed), progress, aspect),
            scene: SIMD4<Float>(
                currentScene.seed,
                Float(currentScene.symmetry),
                Float(currentScene.motif.rawValue),
                currentScene.rotationDirection
            ),
            motion: SIMD4<Float>(
                motionSpeed,
                intensity,
                currentScene.twist,
                currentScene.tunnelRate
            ),
            palette: SIMD4<Float>(
                Float(currentPalette),
                paletteMix,
                colorPhase,
                edrHeadroom
            ),
            quality: SIMD4<Float>(samples, heldWeight, currentScene.breathRate, 0.96)
        )
    }

    private func encodeMandala(
        into texture: MTLTexture,
        held: MTLTexture,
        heldWeight: Float,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard let computePipeline,
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }

        var uniforms = makeUniforms(for: texture, heldWeight: heldWeight)
        encoder.setComputePipelineState(computePipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setTexture(held, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<MandalaUniforms>.size, index: 0)

        let threads = MTLSize(width: 16, height: 16, depth: 1)
        let groups = MTLSize(
            width: (texture.width + threads.width - 1) / threads.width,
            height: (texture.height + threads.height - 1) / threads.height,
            depth: 1
        )
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
        encoder.endEncoding()
        return true
    }

    private func captureOutgoingFrame() -> Bool {
        guard let metalLayer,
              let commandQueue,
              let held = ensureHeldTexture(
                width: Int(metalLayer.drawableSize.width),
                height: Int(metalLayer.drawableSize.height)
              ),
              let dummy = ensureDummyHeldTexture(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              encodeMandala(
                into: held,
                held: dummy,
                heldWeight: 0.0,
                commandBuffer: commandBuffer
              ) else { return false }

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

        if transitionState == .capturePending {
            let captured = captureOutgoingFrame()
            selectNextScene()
            transitionState = .playing
            crossfadeProgress = captured ? 0.0 : 1.0
        }

        guard let dummy = ensureDummyHeldTexture(),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return false }

        var held = dummy
        var heldWeight: Float = 0.0
        if crossfadeProgress < 1.0,
           let heldTexture,
           heldTexture.width == target.texture.width,
           heldTexture.height == target.texture.height {
            let x = crossfadeProgress
            heldWeight = 1.0 - x * x * (3.0 - 2.0 * x)
            held = heldTexture
        }

        guard encodeMandala(
            into: target.texture,
            held: held,
            heldWeight: heldWeight,
            commandBuffer: commandBuffer
        ) else { return false }

        commandBuffer.present(target.drawable)
        commandBuffer.addCompletedHandler { [weak self] completedBuffer in
            guard let self else { return }
            let gpuTime = completedBuffer.gpuEndTime - completedBuffer.gpuStartTime
            guard gpuTime > 0.0 else { return }
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

    // MARK: - Configuration sheet

    override var hasConfigureSheet: Bool {
        // macOS 26.5's legacyScreenSaver extension crashes inside Apple's
        // presentConfiguration path before loading third-party bundle code.
        // Hide the broken system button on affected releases; build.sh also
        // installs a standalone settings app using the same controller.
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return !(version.majorVersion == 26 && version.minorVersion <= 5)
    }

    override var configureSheet: NSWindow? {
        return configureSheetController.configureSheet()
    }
}
