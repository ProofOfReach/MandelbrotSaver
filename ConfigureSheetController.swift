import AppKit

final class ConfigureSheetController: NSObject, NSWindowDelegate {
    private let preferences = Preferences.shared
    private var window: NSWindow?

    private var motionSlider: NSSlider!
    private var motionLabel: NSTextField!
    private var palettePopup: NSPopUpButton!
    private var autoCycleCheckbox: NSButton!
    private var symmetryPopup: NSPopUpButton!
    private var intensityPopup: NSPopUpButton!
    private var visualQualityPopup: NSPopUpButton!
    private var batterySaverCheckbox: NSButton!

    func configureSheet() -> NSWindow? {
        if let window {
            loadPreferences()
            return window
        }

        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 382),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        sheet.title = "Hyperspace Bloom Options"
        sheet.isReleasedWhenClosed = false
        sheet.delegate = self
        let contentView = createContentView()
        sheet.contentView = contentView

        window = sheet
        loadPreferences()
        return sheet
    }

    private func createContentView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let description = makeLabel(
            "A living geometric hyperspace mandala. Changes are saved immediately.",
            size: 11
        )
        description.textColor = .secondaryLabelColor
        stack.addArrangedSubview(description)
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(createMotionSection())
        stack.addArrangedSubview(createAppearanceSection())
        stack.addArrangedSubview(createQualitySection())
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(createButtonRow())
        stack.addArrangedSubview(createAboutRow())

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 382))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func createMotionSection() -> NSView {
        let section = sectionStack(titled: "Motion")
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10

        let slow = makeLabel("Dream", size: 11)
        slow.textColor = .secondaryLabelColor
        motionSlider = NSSlider(
            value: 1.0,
            minValue: 0.4,
            maxValue: 1.6,
            target: self,
            action: #selector(motionChanged(_:))
        )
        motionSlider.widthAnchor.constraint(equalToConstant: 210).isActive = true
        let fast = makeLabel("Voyage", size: 11)
        fast.textColor = .secondaryLabelColor
        motionLabel = makeLabel("", size: 11)
        motionLabel.textColor = .secondaryLabelColor
        motionLabel.widthAnchor.constraint(equalToConstant: 72).isActive = true

        row.addArrangedSubview(slow)
        row.addArrangedSubview(motionSlider)
        row.addArrangedSubview(fast)
        row.addArrangedSubview(motionLabel)
        section.addArrangedSubview(row)
        return section
    }

    private func createAppearanceSection() -> NSView {
        let section = sectionStack(titled: "Vision")

        palettePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        palettePopup.addItems(withTitles: Preferences.paletteNames)
        palettePopup.target = self
        palettePopup.action = #selector(paletteChanged(_:))
        palettePopup.widthAnchor.constraint(equalToConstant: 180).isActive = true
        autoCycleCheckbox = NSButton(
            checkboxWithTitle: "Drift between palettes",
            target: self,
            action: #selector(autoCycleChanged(_:))
        )

        let paletteRow = NSStackView()
        paletteRow.orientation = .horizontal
        paletteRow.spacing = 10
        paletteRow.addArrangedSubview(palettePopup)
        paletteRow.addArrangedSubview(autoCycleCheckbox)
        section.addArrangedSubview(paletteRow)

        symmetryPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        symmetryPopup.addItems(withTitles: Preferences.symmetryNames)
        symmetryPopup.target = self
        symmetryPopup.action = #selector(symmetryChanged(_:))
        symmetryPopup.widthAnchor.constraint(equalToConstant: 180).isActive = true

        intensityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        intensityPopup.addItems(withTitles: Preferences.intensityNames)
        intensityPopup.target = self
        intensityPopup.action = #selector(intensityChanged(_:))
        intensityPopup.widthAnchor.constraint(equalToConstant: 180).isActive = true

        let structureRow = NSStackView()
        structureRow.orientation = .horizontal
        structureRow.spacing = 10
        structureRow.addArrangedSubview(labeledControl("Symmetry", control: symmetryPopup))
        structureRow.addArrangedSubview(labeledControl("Complexity", control: intensityPopup))
        section.addArrangedSubview(structureRow)
        return section
    }

    private func createQualitySection() -> NSView {
        let section = sectionStack(titled: "Quality & Power")
        visualQualityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        visualQualityPopup.addItems(withTitles: Preferences.visualQualityNames)
        visualQualityPopup.target = self
        visualQualityPopup.action = #selector(qualityChanged(_:))
        visualQualityPopup.widthAnchor.constraint(equalToConstant: 180).isActive = true
        section.addArrangedSubview(visualQualityPopup)

        batterySaverCheckbox = NSButton(
            checkboxWithTitle: "Reduce resolution and frame rate on battery",
            target: self,
            action: #selector(batterySaverChanged(_:))
        )
        section.addArrangedSubview(batterySaverCheckbox)

        let note = makeLabel(
            "Ultra uses four sub-pixel samples when the GPU has headroom.",
            size: 10
        )
        note.textColor = .secondaryLabelColor
        section.addArrangedSubview(note)
        return section
    }

    private func labeledControl(_ title: String, control: NSView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        let label = makeLabel(title, size: 10)
        label.textColor = .secondaryLabelColor
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(control)
        return stack
    }

    private func createButtonRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.distribution = .fill
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let reset = NSButton(
            title: "Reset to Defaults",
            target: self,
            action: #selector(resetDefaults(_:))
        )
        reset.bezelStyle = .rounded
        let done = NSButton(title: "OK", target: self, action: #selector(closeSheet(_:)))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"

        row.addArrangedSubview(spacer)
        row.addArrangedSubview(reset)
        row.addArrangedSubview(done)
        return row
    }

    private func createAboutRow() -> NSView {
        let bundle = Bundle(for: ConfigureSheetController.self)
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let label = makeLabel(
            "Hyperspace Bloom \(version) · Procedurally rendered with Metal",
            size: 10
        )
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func sectionStack(titled title: String) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        let label = makeLabel(title, size: 12)
        label.font = .boldSystemFont(ofSize: 12)
        stack.addArrangedSubview(label)
        return stack
    }

    private func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 400).isActive = true
        return separator
    }

    private func makeLabel(_ text: String, size: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        return label
    }

    private func loadPreferences() {
        motionSlider.doubleValue = preferences.motionSpeed
        updateMotionLabel()
        palettePopup.selectItem(at: preferences.paletteIndex)
        autoCycleCheckbox.state = preferences.autoCyclePalettes ? .on : .off
        symmetryPopup.selectItem(at: preferences.symmetryIndex)
        intensityPopup.selectItem(at: preferences.intensity)
        visualQualityPopup.selectItem(at: preferences.visualQuality)
        batterySaverCheckbox.state = preferences.batterySaver ? .on : .off
    }

    private func updateMotionLabel() {
        let value = motionSlider.doubleValue
        if value < 0.72 {
            motionLabel.stringValue = "Dream"
        } else if value > 1.28 {
            motionLabel.stringValue = "Voyage"
        } else {
            motionLabel.stringValue = "Flow"
        }
    }

    @objc private func motionChanged(_ sender: NSSlider) {
        preferences.motionSpeed = sender.doubleValue
        updateMotionLabel()
    }

    @objc private func paletteChanged(_ sender: NSPopUpButton) {
        preferences.paletteIndex = sender.indexOfSelectedItem
    }

    @objc private func autoCycleChanged(_ sender: NSButton) {
        preferences.autoCyclePalettes = sender.state == .on
    }

    @objc private func symmetryChanged(_ sender: NSPopUpButton) {
        preferences.symmetryIndex = sender.indexOfSelectedItem
    }

    @objc private func intensityChanged(_ sender: NSPopUpButton) {
        preferences.intensity = sender.indexOfSelectedItem
    }

    @objc private func qualityChanged(_ sender: NSPopUpButton) {
        preferences.visualQuality = sender.indexOfSelectedItem
    }

    @objc private func batterySaverChanged(_ sender: NSButton) {
        preferences.batterySaver = sender.state == .on
    }

    @objc private func resetDefaults(_ sender: NSButton) {
        preferences.resetToDefaults()
        loadPreferences()
    }

    @objc private func closeSheet(_ sender: NSButton) {
        guard let window else { return }
        if let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        } else {
            window.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else { return }
        window = nil
    }
}
