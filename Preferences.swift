import ScreenSaver
import Foundation

/// Wrapper for ScreenSaverDefaults to manage Mandelbrot screensaver preferences
final class Preferences {

    // MARK: - Singleton

    static let shared = Preferences()
    static let didChangeNotification = Notification.Name("MandelbrotPreferencesDidChange")
    private static let moduleName = "MandelbrotSaver"

    // MARK: - Keys

    private enum Keys {
        static let zoomSpeed = "zoomSpeed"
        static let paletteIndex = "paletteIndex"
        static let autoCyclePalettes = "autoCyclePalettes"
        static let shadingMode = "shadingMode"
        static let juliaMode = "juliaMode"
        static let visualQuality = "visualQuality"
        static let batterySaver = "batterySaver"
    }

    // MARK: - Defaults

    private enum Defaults {
        static let zoomSpeed: Double = 0.985
        static let paletteIndex: Int = 0
        static let autoCyclePalettes: Bool = true
        static let shadingMode: Int = 0
        static let juliaMode: Bool = false
        static let visualQuality: Int = 1
        static let batterySaver: Bool = true
    }

    // MARK: - Properties

    private let defaults: ScreenSaverDefaults?

    private func clamp<T: Comparable>(_ value: T, min minValue: T, max maxValue: T) -> T {
        return max(minValue, min(maxValue, value))
    }

    private func persistAndNotify() {
        defaults?.synchronize()
        notifyChanged()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: Preferences.didChangeNotification, object: self)
    }

    /// Zoom speed multiplier at 60fps (lower = faster, higher = slower)
    /// Range: 0.965 to 0.9975
    var zoomSpeed: Double {
        get {
            let value = defaults?.double(forKey: Keys.zoomSpeed) ?? 0
            let speed = value > 0 ? value : Defaults.zoomSpeed
            return clamp(speed, min: 0.965, max: 0.9975)
        }
        set {
            let clamped = clamp(newValue, min: 0.965, max: 0.9975)
            defaults?.set(clamped, forKey: Keys.zoomSpeed)
            persistAndNotify()
        }
    }

    /// Current palette index
    var paletteIndex: Int {
        get {
            let value = defaults?.integer(forKey: Keys.paletteIndex) ?? Defaults.paletteIndex
            return clamp(value, min: 0, max: Preferences.paletteNames.count - 1)
        }
        set {
            let clamped = clamp(newValue, min: 0, max: Preferences.paletteNames.count - 1)
            defaults?.set(clamped, forKey: Keys.paletteIndex)
            persistAndNotify()
        }
    }

    /// Whether to automatically cycle through palettes
    var autoCyclePalettes: Bool {
        get {
            // Check if the key exists, otherwise return default
            if defaults?.object(forKey: Keys.autoCyclePalettes) == nil {
                return Defaults.autoCyclePalettes
            }
            return defaults?.bool(forKey: Keys.autoCyclePalettes) ?? Defaults.autoCyclePalettes
        }
        set {
            defaults?.set(newValue, forKey: Keys.autoCyclePalettes)
            persistAndNotify()
        }
    }

    /// Shading mode: 0 = flat, 1 = 3D Blinn-Phong, 2 = angle-based, 3 = stripe
    var shadingMode: Int {
        get {
            let value = defaults?.integer(forKey: Keys.shadingMode) ?? Defaults.shadingMode
            return clamp(value, min: 0, max: Preferences.shadingModeNames.count - 1)
        }
        set {
            let clamped = clamp(newValue, min: 0, max: Preferences.shadingModeNames.count - 1)
            defaults?.set(clamped, forKey: Keys.shadingMode)
            persistAndNotify()
        }
    }

    /// Whether to render Julia sets instead of Mandelbrot
    var juliaMode: Bool {
        get {
            if defaults?.object(forKey: Keys.juliaMode) == nil {
                return Defaults.juliaMode
            }
            return defaults?.bool(forKey: Keys.juliaMode) ?? Defaults.juliaMode
        }
        set {
            defaults?.set(newValue, forKey: Keys.juliaMode)
            persistAndNotify()
        }
    }

    /// Visual quality: 0 = Standard, 1 = Ultra
    var visualQuality: Int {
        get {
            if defaults?.object(forKey: Keys.visualQuality) == nil {
                return Defaults.visualQuality
            }
            let value = defaults?.integer(forKey: Keys.visualQuality) ?? Defaults.visualQuality
            return clamp(value, min: 0, max: Preferences.visualQualityNames.count - 1)
        }
        set {
            let clamped = clamp(newValue, min: 0, max: Preferences.visualQualityNames.count - 1)
            defaults?.set(clamped, forKey: Keys.visualQuality)
            persistAndNotify()
        }
    }

    /// Cap refresh rate and quality when on battery or in Low Power Mode
    var batterySaver: Bool {
        get {
            if defaults?.object(forKey: Keys.batterySaver) == nil {
                return Defaults.batterySaver
            }
            return defaults?.bool(forKey: Keys.batterySaver) ?? Defaults.batterySaver
        }
        set {
            defaults?.set(newValue, forKey: Keys.batterySaver)
            persistAndNotify()
        }
    }

    // MARK: - Initialization

    private init() {
        defaults = ScreenSaverDefaults(forModuleWithName: Preferences.moduleName)

        // Register defaults
        defaults?.register(defaults: [
            Keys.zoomSpeed: Defaults.zoomSpeed,
            Keys.paletteIndex: Defaults.paletteIndex,
            Keys.autoCyclePalettes: Defaults.autoCyclePalettes,
            Keys.shadingMode: Defaults.shadingMode,
            Keys.juliaMode: Defaults.juliaMode,
            Keys.visualQuality: Defaults.visualQuality,
            Keys.batterySaver: Defaults.batterySaver
        ])
    }

    // MARK: - Helpers

    /// Reset all preferences to defaults
    func resetToDefaults() {
        zoomSpeed = Defaults.zoomSpeed
        paletteIndex = Defaults.paletteIndex
        autoCyclePalettes = Defaults.autoCyclePalettes
        shadingMode = Defaults.shadingMode
        juliaMode = Defaults.juliaMode
        visualQuality = Defaults.visualQuality
        batterySaver = Defaults.batterySaver
    }

    /// Palette names for UI display
    static let paletteNames = [
        "Ultra Fractal",
        "Ember",
        "Abyss",
        "Neon",
        "Aurora",
        "Graphite"
    ]

    /// Shading mode names for UI display
    static let shadingModeNames = [
        "Flat",
        "3D Blinn-Phong",
        "Angle-based",
        "Stripe"
    ]

    static let visualQualityNames = [
        "Standard",
        "Ultra"
    ]
}
