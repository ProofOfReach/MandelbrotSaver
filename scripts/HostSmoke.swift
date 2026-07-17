import AppKit
import ScreenSaver
import QuartzCore

private func descendants(of view: NSView) -> [NSView] {
    return view.subviews.flatMap { [$0] + descendants(of: $0) }
}

@main
private enum HostSmoke {
    static func main() throws {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)

        let bundleURL = URL(fileURLWithPath: "HyperspaceBloom.saver", isDirectory: true)
        guard let bundle = Bundle(url: bundleURL) else {
            fatalError("Could not create the screen saver bundle")
        }
        try bundle.loadAndReturnError()

        guard let saverClass = bundle.principalClass as? ScreenSaverView.Type,
              let saver = saverClass.init(
                frame: NSRect(x: 0, y: 0, width: 480, height: 300),
                isPreview: true
              ) else {
            fatalError("Could not instantiate NSPrincipalClass as ScreenSaverView")
        }

        precondition(saver.layer is CAMetalLayer, "screen saver did not install a CAMetalLayer")
        let os = ProcessInfo.processInfo.operatingSystemVersion
        if os.majorVersion == 26 && os.minorVersion <= 5 {
            precondition(!saver.hasConfigureSheet, "broken macOS 26.5 system options path should be hidden")
        } else {
            precondition(saver.hasConfigureSheet, "configuration sheet is unavailable")
        }

        saver.startAnimation()
        for _ in 0..<4 {
            saver.animateOneFrame()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.015))
        }
        saver.stopAnimation()

        guard let sheet = saver.configureSheet else {
            fatalError("configuration sheet could not be created")
        }
        precondition(sheet.title == "Hyperspace Bloom Options", "configuration sheet has the wrong title")

        guard let contentView = sheet.contentView else {
            fatalError("configuration sheet has no content view")
        }
        let controls = descendants(of: contentView)
        guard let motionSlider = controls.compactMap({ $0 as? NSSlider }).first else {
            fatalError("configuration sheet has no motion slider")
        }
        precondition(motionSlider.target != nil && motionSlider.action != nil, "motion slider is not wired")

        let preferencesIdentifier = "com.proofofreach.HyperspaceBloom"
        let originalMotion = ScreenSaverDefaults(forModuleWithName: preferencesIdentifier)?.double(forKey: "motionSpeed") ?? 1.0
        let testMotion = originalMotion < 1.3 ? 1.6 : 0.4
        motionSlider.doubleValue = testMotion
        precondition(
            NSApplication.shared.sendAction(motionSlider.action!, to: motionSlider.target, from: motionSlider),
            "motion slider action was rejected"
        )
        let persistedMotion = ScreenSaverDefaults(forModuleWithName: preferencesIdentifier)?.double(forKey: "motionSpeed") ?? -1.0
        precondition(abs(persistedMotion - testMotion) < 0.001, "motion slider did not persist its value")

        motionSlider.doubleValue = originalMotion
        _ = NSApplication.shared.sendAction(motionSlider.action!, to: motionSlider.target, from: motionSlider)
        sheet.close()

        print("Host smoke test passed (bundle load, principal class, Metal frames, interactive options).")
    }
}
