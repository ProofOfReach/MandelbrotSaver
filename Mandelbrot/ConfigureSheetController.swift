import AppKit
import ScreenSaver

/// Controller for the screensaver configuration sheet
/// Uses programmatic UI (no XIB) with NSStackView layout
final class ConfigureSheetController: NSObject {

    // MARK: - Properties

    private var window: NSWindow?
    private var preferences = Preferences.shared

    // UI Elements
    var zoomSpeedSlider: NSSlider!
    private var zoomSpeedLabel: NSTextField!
    var palettePopup: NSPopUpButton!
    var autoCycleCheckbox: NSButton!
    var visualQualityPopup: NSPopUpButton!
    var shadingModePopup: NSPopUpButton!
    private var batterySaverCheckbox: NSButton!
    private var juliaModeCheckbox: NSButton!
    private var previewView: MandelbrotView?

    // MARK: - Window Creation

    func configureSheet() -> NSWindow {
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        sheet.title = "Mandelbrot Screensaver Options"
        sheet.isReleasedWhenClosed = false

        let contentView = createContentView()
        sheet.contentView = contentView
        sheet.setContentSize(contentView.fittingSize)

        window = sheet
        loadPreferences()
        startPreview()
        return sheet
    }

    // MARK: - UI Construction

    private func createContentView() -> NSView {
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        mainStack.addArrangedSubview(createPreviewSection())
        mainStack.addArrangedSubview(makeSeparator())
        mainStack.addArrangedSubview(createMotionSection())
        mainStack.addArrangedSubview(createAppearanceSection())
        mainStack.addArrangedSubview(createQualityPowerSection())
        mainStack.addArrangedSubview(createFractalSection())
        mainStack.addArrangedSubview(makeSeparator())
        mainStack.addArrangedSubview(createButtonRow())
        mainStack.addArrangedSubview(createAboutRow())

        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 560))
        containerView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: containerView.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        return containerView
    }

    /// Small live-rendering preview so palette/shading/quality changes are visible immediately.
    private func createPreviewSection() -> NSView {
        let preview = MandelbrotView(frame: NSRect(x: 0, y: 0, width: 400, height: 170), isPreview: true)
        previewView = preview

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true

        if let preview {
            preview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(preview)
            NSLayoutConstraint.activate([
                preview.topAnchor.constraint(equalTo: container.topAnchor),
                preview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                preview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                preview.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }

        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: 400).isActive = true
        container.heightAnchor.constraint(equalToConstant: 170).isActive = true
        return container
    }

    private func startPreview() {
        guard let preview = previewView, !preview.isAnimating else { return }
        preview.startAnimation()
    }

    private func stopPreview() {
        guard let preview = previewView, preview.isAnimating else { return }
        preview.stopAnimation()
    }

    private func createMotionSection() -> NSView {
        let stack = sectionStack(titled: "Motion")

        let sliderRow = NSStackView()
        sliderRow.orientation = .horizontal
        sliderRow.spacing = 10

        let slowLabel = createLabel("Slow", bold: false, size: 11)
        slowLabel.textColor = .secondaryLabelColor

        zoomSpeedSlider = NSSlider(value: 0.5, minValue: 0.0, maxValue: 1.0, target: self, action: #selector(zoomSpeedChanged(_:)))
        zoomSpeedSlider.widthAnchor.constraint(equalToConstant: 190).isActive = true

        let fastLabel = createLabel("Fast", bold: false, size: 11)
        fastLabel.textColor = .secondaryLabelColor

        zoomSpeedLabel = createLabel("", bold: false, size: 11)
        zoomSpeedLabel.textColor = .secondaryLabelColor
        zoomSpeedLabel.widthAnchor.constraint(equalToConstant: 130).isActive = true

        sliderRow.addArrangedSubview(slowLabel)
        sliderRow.addArrangedSubview(zoomSpeedSlider)
        sliderRow.addArrangedSubview(fastLabel)
        sliderRow.addArrangedSubview(zoomSpeedLabel)

        stack.addArrangedSubview(sliderRow)
        return stack
    }

    private func createAppearanceSection() -> NSView {
        let stack = sectionStack(titled: "Appearance")

        let paletteRow = NSStackView()
        paletteRow.orientation = .horizontal
        paletteRow.spacing = 10

        palettePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        palettePopup.addItems(withTitles: Preferences.paletteNames)
        palettePopup.target = self
        palettePopup.action = #selector(paletteChanged(_:))
        palettePopup.widthAnchor.constraint(equalToConstant: 180).isActive = true

        autoCycleCheckbox = NSButton(checkboxWithTitle: "Auto-cycle palettes", target: self, action: #selector(autoCycleChanged(_:)))

        paletteRow.addArrangedSubview(palettePopup)
        paletteRow.addArrangedSubview(autoCycleCheckbox)
        stack.addArrangedSubview(paletteRow)

        shadingModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        shadingModePopup.addItems(withTitles: Preferences.shadingModeNames)
        shadingModePopup.target = self
        shadingModePopup.action = #selector(shadingModeChanged(_:))
        shadingModePopup.widthAnchor.constraint(equalToConstant: 180).isActive = true

        let shadingRow = NSStackView()
        shadingRow.orientation = .horizontal
        shadingRow.spacing = 10
        shadingRow.addArrangedSubview(shadingModePopup)

        let shadingDesc = createLabel("3D adds lighting with moving highlights", bold: false, size: 10)
        shadingDesc.textColor = .secondaryLabelColor
        shadingRow.addArrangedSubview(shadingDesc)
        stack.addArrangedSubview(shadingRow)

        return stack
    }

    private func createQualityPowerSection() -> NSView {
        let stack = sectionStack(titled: "Quality & Power")

        let qualityRow = NSStackView()
        qualityRow.orientation = .horizontal
        qualityRow.spacing = 10

        visualQualityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        visualQualityPopup.addItems(withTitles: Preferences.visualQualityNames)
        visualQualityPopup.target = self
        visualQualityPopup.action = #selector(visualQualityChanged(_:))
        visualQualityPopup.widthAnchor.constraint(equalToConstant: 180).isActive = true
        qualityRow.addArrangedSubview(visualQualityPopup)
        stack.addArrangedSubview(qualityRow)

        batterySaverCheckbox = NSButton(checkboxWithTitle: "Reduce quality on battery power", target: self, action: #selector(batterySaverChanged(_:)))
        stack.addArrangedSubview(batterySaverCheckbox)

        let desc = createLabel("Caps the frame rate and detail while on battery or in Low Power Mode", bold: false, size: 10)
        desc.textColor = .secondaryLabelColor
        stack.addArrangedSubview(desc)

        return stack
    }

    private func createFractalSection() -> NSView {
        let stack = sectionStack(titled: "Fractal")
        juliaModeCheckbox = NSButton(checkboxWithTitle: "Julia set mode", target: self, action: #selector(juliaModeChanged(_:)))
        stack.addArrangedSubview(juliaModeCheckbox)
        return stack
    }

    private func createButtonRow() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.distribution = .fill

        // Spacer to push buttons right
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetDefaults(_:)))
        resetButton.bezelStyle = .rounded

        let okButton = NSButton(title: "OK", target: self, action: #selector(closeSheet(_:)))
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"

        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(resetButton)
        stack.addArrangedSubview(okButton)

        return stack
    }

    private func createAboutRow() -> NSView {
        let bundle = Bundle(for: ConfigureSheetController.self)
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let label = createLabel("Mandelbrot Screensaver \(version) · GPU-rendered with Metal", bold: false, size: 10)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func sectionStack(titled title: String) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.addArrangedSubview(createLabel(title, bold: true, size: 12))
        return stack
    }

    private func makeSeparator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 400).isActive = true
        return box
    }

    private func createLabel(_ text: String, bold: Bool, size: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        return label
    }

    // MARK: - Preferences

    // Slider mapping: 0 (slow) = 0.9975, 1 (fast) = 0.965
    private let slowestSpeed = 0.9975
    private let fastestSpeed = 0.965

    private func sliderToSpeed(_ slider: Double) -> Double {
        return slowestSpeed - (slider * (slowestSpeed - fastestSpeed))
    }

    private func speedToSlider(_ speed: Double) -> Double {
        return max(0.0, min(1.0, (slowestSpeed - speed) / (slowestSpeed - fastestSpeed)))
    }

    private func loadPreferences() {
        zoomSpeedSlider.doubleValue = speedToSlider(preferences.zoomSpeed)
        updateZoomSpeedLabel()

        palettePopup.selectItem(at: min(preferences.paletteIndex, palettePopup.numberOfItems - 1))
        autoCycleCheckbox.state = preferences.autoCyclePalettes ? .on : .off
        visualQualityPopup.selectItem(at: min(preferences.visualQuality, visualQualityPopup.numberOfItems - 1))

        shadingModePopup.selectItem(at: min(preferences.shadingMode, shadingModePopup.numberOfItems - 1))

        batterySaverCheckbox.state = preferences.batterySaver ? .on : .off
        juliaModeCheckbox.state = preferences.juliaMode ? .on : .off
    }

    private func updateZoomSpeedLabel() {
        let value = zoomSpeedSlider.doubleValue
        let name: String
        if value < 0.33 {
            name = "Relaxed"
        } else if value < 0.67 {
            name = "Balanced"
        } else {
            name = "Fast"
        }

        // Mirror the saver's dive-duration estimate: frames to shrink from the
        // starting scale (3.0) to a typical target depth (1e-7), at 60 steps/sec,
        // clamped to the same 24-140s window used by the auto-pilot.
        let speed = sliderToSpeed(value)
        let frames = log(1e-7 / 3.0) / log(speed)
        let seconds = min(max(frames / 60.0, 24.0), 140.0)
        zoomSpeedLabel.stringValue = "\(name) · ~\(Int(seconds.rounded()))s dive"
    }

    // MARK: - Actions

    @objc private func zoomSpeedChanged(_ sender: NSSlider) {
        preferences.zoomSpeed = sliderToSpeed(sender.doubleValue)
        updateZoomSpeedLabel()
    }

    @objc private func paletteChanged(_ sender: NSPopUpButton) {
        preferences.paletteIndex = sender.indexOfSelectedItem
    }

    @objc private func autoCycleChanged(_ sender: NSButton) {
        preferences.autoCyclePalettes = (sender.state == .on)
    }

    @objc private func visualQualityChanged(_ sender: NSPopUpButton) {
        preferences.visualQuality = sender.indexOfSelectedItem
    }

    @objc private func shadingModeChanged(_ sender: NSPopUpButton) {
        preferences.shadingMode = sender.indexOfSelectedItem
    }

    @objc private func batterySaverChanged(_ sender: NSButton) {
        preferences.batterySaver = (sender.state == .on)
    }

    @objc private func juliaModeChanged(_ sender: NSButton) {
        preferences.juliaMode = (sender.state == .on)
    }

    @objc private func resetDefaults(_ sender: NSButton) {
        preferences.resetToDefaults()
        loadPreferences()
    }

    @objc private func closeSheet(_ sender: NSButton) {
        stopPreview()
        previewView = nil
        guard let window = window,
              let sheetParent = window.sheetParent else {
            window?.close()
            self.window = nil
            return
        }
        sheetParent.endSheet(window)
        self.window = nil
    }
}
