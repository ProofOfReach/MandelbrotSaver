import AppKit
import ScreenSaver

/// Controller for the screensaver configuration sheet
/// Uses programmatic UI (no XIB) with NSStackView for layout
final class ConfigureSheetController: NSObject {

    // MARK: - Properties

    private var window: NSWindow?
    private var preferences = Preferences.shared

    // UI Elements
    private var zoomSpeedSlider: NSSlider!
    private var zoomSpeedLabel: NSTextField!
    private var palettePopup: NSPopUpButton!
    private var autoCycleCheckbox: NSButton!
    private var shadingModePopup: NSPopUpButton!
    private var juliaModeCheckbox: NSButton!

    // MARK: - Window Creation

    func configureSheet() -> NSWindow {
        if let existingWindow = window {
            return existingWindow
        }

        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        sheet.title = "Mandelbrot Screensaver Options"

        let contentView = createContentView()
        sheet.contentView = contentView

        window = sheet
        loadPreferences()
        return sheet
    }

    // MARK: - UI Construction

    private func createContentView() -> NSView {
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 16
        mainStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        // Title
        let titleLabel = createLabel("Mandelbrot Screensaver", bold: true, size: 14)
        mainStack.addArrangedSubview(titleLabel)

        // Zoom Speed Section
        let zoomSection = createZoomSpeedSection()
        mainStack.addArrangedSubview(zoomSection)

        // Palette Section
        let paletteSection = createPaletteSection()
        mainStack.addArrangedSubview(paletteSection)

        // Shading Section
        let shadingSection = createShadingSection()
        mainStack.addArrangedSubview(shadingSection)

        // Julia Mode Section
        let juliaSection = createJuliaSection()
        mainStack.addArrangedSubview(juliaSection)

        // Buttons
        let buttonRow = createButtonRow()
        mainStack.addArrangedSubview(buttonRow)

        // Set up constraints
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 320))
        containerView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: containerView.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        return containerView
    }

    private func createZoomSpeedSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        let headerLabel = createLabel("Zoom Speed", bold: true, size: 12)

        let sliderRow = NSStackView()
        sliderRow.orientation = .horizontal
        sliderRow.spacing = 10

        let slowLabel = createLabel("Slow", bold: false, size: 11)
        slowLabel.textColor = .secondaryLabelColor

        // Slider: left=slow (0.997), right=fast (0.975) - we invert when reading
        zoomSpeedSlider = NSSlider(value: 0.5, minValue: 0.0, maxValue: 1.0, target: self, action: #selector(zoomSpeedChanged(_:)))
        zoomSpeedSlider.widthAnchor.constraint(equalToConstant: 200).isActive = true

        let fastLabel = createLabel("Fast", bold: false, size: 11)
        fastLabel.textColor = .secondaryLabelColor

        zoomSpeedLabel = createLabel("0.988", bold: false, size: 11)
        zoomSpeedLabel.widthAnchor.constraint(equalToConstant: 50).isActive = true

        sliderRow.addArrangedSubview(slowLabel)
        sliderRow.addArrangedSubview(zoomSpeedSlider)
        sliderRow.addArrangedSubview(fastLabel)
        sliderRow.addArrangedSubview(zoomSpeedLabel)

        stack.addArrangedSubview(headerLabel)
        stack.addArrangedSubview(sliderRow)

        return stack
    }

    private func createPaletteSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        let headerLabel = createLabel("Color Palette", bold: true, size: 12)

        let paletteRow = NSStackView()
        paletteRow.orientation = .horizontal
        paletteRow.spacing = 10

        palettePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        palettePopup.addItems(withTitles: Preferences.paletteNames)
        palettePopup.target = self
        palettePopup.action = #selector(paletteChanged(_:))
        palettePopup.widthAnchor.constraint(equalToConstant: 200).isActive = true

        autoCycleCheckbox = NSButton(checkboxWithTitle: "Auto-cycle palettes", target: self, action: #selector(autoCycleChanged(_:)))

        paletteRow.addArrangedSubview(palettePopup)
        paletteRow.addArrangedSubview(autoCycleCheckbox)

        stack.addArrangedSubview(headerLabel)
        stack.addArrangedSubview(paletteRow)

        return stack
    }

    private func createShadingSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        let headerLabel = createLabel("Shading Mode", bold: true, size: 12)

        shadingModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        shadingModePopup.addItems(withTitles: Preferences.shadingModeNames)
        shadingModePopup.target = self
        shadingModePopup.action = #selector(shadingModeChanged(_:))
        shadingModePopup.widthAnchor.constraint(equalToConstant: 200).isActive = true

        let descLabel = createLabel("3D Blinn-Phong provides realistic lighting with rotating light sources", bold: false, size: 10)
        descLabel.textColor = .secondaryLabelColor

        stack.addArrangedSubview(headerLabel)
        stack.addArrangedSubview(shadingModePopup)
        stack.addArrangedSubview(descLabel)

        return stack
    }

    private func createJuliaSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        let headerLabel = createLabel("Fractal Mode", bold: true, size: 12)

        juliaModeCheckbox = NSButton(checkboxWithTitle: "Julia set mode (experimental)", target: self, action: #selector(juliaModeChanged(_:)))

        stack.addArrangedSubview(headerLabel)
        stack.addArrangedSubview(juliaModeCheckbox)

        return stack
    }

    private func createButtonRow() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.distribution = .fill

        // Spacer to push buttons to the right
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

    private func createLabel(_ text: String, bold: Bool, size: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        return label
    }

    // MARK: - Preferences

    // Slider mapping: 0 (slow) = 0.997, 1 (fast) = 0.975
    private let slowestSpeed = 0.997
    private let fastestSpeed = 0.975

    private func sliderToSpeed(_ slider: Double) -> Double {
        return slowestSpeed - (slider * (slowestSpeed - fastestSpeed))
    }

    private func speedToSlider(_ speed: Double) -> Double {
        return (slowestSpeed - speed) / (slowestSpeed - fastestSpeed)
    }

    private func loadPreferences() {
        zoomSpeedSlider.doubleValue = speedToSlider(preferences.zoomSpeed)
        updateZoomSpeedLabel()

        palettePopup.selectItem(at: preferences.paletteIndex)
        autoCycleCheckbox.state = preferences.autoCyclePalettes ? .on : .off

        shadingModePopup.selectItem(at: preferences.shadingMode)

        juliaModeCheckbox.state = preferences.juliaMode ? .on : .off
    }

    private func updateZoomSpeedLabel() {
        let pct = Int(zoomSpeedSlider.doubleValue * 100)
        zoomSpeedLabel.stringValue = "\(pct)%"
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

    @objc private func shadingModeChanged(_ sender: NSPopUpButton) {
        preferences.shadingMode = sender.indexOfSelectedItem
    }

    @objc private func juliaModeChanged(_ sender: NSButton) {
        preferences.juliaMode = (sender.state == .on)
    }

    @objc private func resetDefaults(_ sender: NSButton) {
        preferences.resetToDefaults()
        loadPreferences()
    }

    @objc private func closeSheet(_ sender: NSButton) {
        guard let window = window,
              let sheetParent = window.sheetParent else {
            window?.close()
            return
        }
        sheetParent.endSheet(window)
    }
}
