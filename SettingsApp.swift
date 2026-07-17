import AppKit

private func descendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants(of: $0) }
}

private final class SettingsAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = ConfigureSheetController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let window = controller.configureSheet() else {
            NSApp.terminate(nil)
            return
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
private enum SettingsApp {
    static func main() {
        let app = NSApplication.shared

        if CommandLine.arguments.contains("--smoke-test") {
            app.setActivationPolicy(.prohibited)
            runSmokeTest()
            return
        }

        app.setActivationPolicy(.regular)
        let delegate = SettingsAppDelegate()
        app.delegate = delegate
        app.run()
        _ = delegate
    }

    private static func runSmokeTest() {
        let controller = ConfigureSheetController()
        guard let window = controller.configureSheet(),
              let contentView = window.contentView else {
            fatalError("Settings window could not be created")
        }

        let controls = descendants(of: contentView)
        let sliders = controls.compactMap { $0 as? NSSlider }
        let popups = controls.compactMap { $0 as? NSPopUpButton }
        let buttons = controls.compactMap { $0 as? NSButton }

        precondition(window.title == "Hyperspace Bloom Options")
        precondition(sliders.count == 1, "Expected one motion slider")
        precondition(popups.count == 4, "Expected four option menus")
        precondition(buttons.count >= 4, "Expected checkboxes and action buttons")
        precondition(sliders[0].target != nil && sliders[0].action != nil)

        print("Settings app smoke test passed (window, controls, and actions).")
    }
}
