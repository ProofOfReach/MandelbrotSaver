import ScreenSaver
import Foundation

/// Wrapper for ScreenSaverDefaults to manage Mandelbrot screensaver preferences
final class Preferences {

    // MARK: - Singleton

    static let shared = Preferences()

    // MARK: - Keys

    private enum Keys {
        static let zoomSpeed = "zoomSpeed"
        static let paletteIndex = "paletteIndex"
        static let autoCyclePalettes = "autoCyclePalettes"
        static let shadingMode = "shadingMode"
        static let juliaMode = "juliaMode"
        static let enableAntialiasing = "enableAntialiasing"
    }

    // MARK: - Defaults

    private enum Defaults {
        static let zoomSpeed: Double = 0.990
        static let paletteIndex: Int = 0
        static let autoCyclePalettes: Bool = true
        static let shadingMode: Int = 0
        static let juliaMode: Bool = false
        static let enableAntialiasing: Bool = true
    }

    // MARK: - Properties

    private let defaults: ScreenSaverDefaults?

    /// Zoom speed (0.98 = faster, 0.995 = slower)
    /// Range: 0.98 to 0.995
    var zoomSpeed: Double {
        get {
            let value = defaults?.double(forKey: Keys.zoomSpeed) ?? 0
            return value > 0 ? value : Defaults.zoomSpeed
        }
        set {
            let clamped = max(0.98, min(0.995, newValue))
            defaults?.set(clamped, forKey: Keys.zoomSpeed)
            defaults?.synchronize()
        }
    }

    /// Current palette index (0-8 for standard + P3 palettes)
    var paletteIndex: Int {
        get {
            return defaults?.integer(forKey: Keys.paletteIndex) ?? Defaults.paletteIndex
        }
        set {
            let clamped = max(0, min(8, newValue))
            defaults?.set(clamped, forKey: Keys.paletteIndex)
            defaults?.synchronize()
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
            defaults?.synchronize()
        }
    }

    /// Shading mode: 0 = flat, 1 = 3D Blinn-Phong, 2 = angle-based, 3 = stripe
    var shadingMode: Int {
        get {
            return defaults?.integer(forKey: Keys.shadingMode) ?? Defaults.shadingMode
        }
        set {
            let clamped = max(0, min(3, newValue))
            defaults?.set(clamped, forKey: Keys.shadingMode)
            defaults?.synchronize()
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
            defaults?.synchronize()
        }
    }

    /// Whether to use 2x2 Supersampling (4x cost, better quality)
    var enableAntialiasing: Bool {
        get {
            if defaults?.object(forKey: Keys.enableAntialiasing) == nil {
                return Defaults.enableAntialiasing
            }
            return defaults?.bool(forKey: Keys.enableAntialiasing) ?? Defaults.enableAntialiasing
        }
        set {
            defaults?.set(newValue, forKey: Keys.enableAntialiasing)
            defaults?.synchronize()
        }
    }

    // MARK: - Initialization

    private init() {
        // Use the screensaver's bundle identifier for defaults
        let bundleIdentifier = Bundle(for: Preferences.self).bundleIdentifier ?? "com.mandelbrot.saver"
        defaults = ScreenSaverDefaults(forModuleWithName: bundleIdentifier)

        // Register defaults
        defaults?.register(defaults: [
            Keys.zoomSpeed: Defaults.zoomSpeed,
            Keys.paletteIndex: Defaults.paletteIndex,
            Keys.autoCyclePalettes: Defaults.autoCyclePalettes,
            Keys.shadingMode: Defaults.shadingMode,
            Keys.juliaMode: Defaults.juliaMode,
            Keys.enableAntialiasing: Defaults.enableAntialiasing
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
        enableAntialiasing = Defaults.enableAntialiasing
    }

    /// Palette names for UI display
    static let paletteNames = [
        "Ultra Fractal",
        "Fire",
        "Ocean",
        "Electric",
        "Sunset",
        "Glacial",
        "P3 Electric (Wide Gamut)",
        "P3 Fire (Wide Gamut)",
        "P3 Ocean (Wide Gamut)"
    ]

    /// Shading mode names for UI display
    static let shadingModeNames = [
        "Flat",
        "3D Blinn-Phong",
        "Angle-based",
        "Stripe"
    ]
}
