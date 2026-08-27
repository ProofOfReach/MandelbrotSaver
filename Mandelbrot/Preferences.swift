import ScreenSaver
import Foundation

/// Wrapper for ScreenSaverDefaults to manage Mandelbrot screensaver preferences.
///
/// The standalone settings app is not inside the legacyScreenSaver sandbox, so
/// ScreenSaverDefaults there writes ~/Library/Preferences/ByHost while the
/// running saver reads the same module name from the engine container. Writes
/// from the app are mirrored into that container plist so the host sees them.
final class Preferences {

    static let shared = Preferences()
    static let didChangeNotification = Notification.Name("MandelbrotPreferencesDidChange")
    private static let moduleName = "com.proofofreach.MandelbrotSaver"

    private enum Keys {
        static let zoomSpeed = "zoomSpeed"
        static let paletteIndex = "paletteIndex"
        static let autoCyclePalettes = "autoCyclePalettes"
        static let shadingMode = "shadingMode"
        static let juliaMode = "juliaMode"
        static let visualQuality = "visualQuality"
        static let batterySaver = "batterySaver"
    }

    private enum Defaults {
        static let zoomSpeed: Double = 0.985
        static let paletteIndex: Int = 0
        static let autoCyclePalettes: Bool = true
        static let shadingMode: Int = 0
        static let juliaMode: Bool = false
        static let visualQuality: Int = 1
        static let batterySaver: Bool = true
    }

    private let defaults: ScreenSaverDefaults?

    /// True when this code is compiled into Mandelbrot Settings.app, not the .saver.
    private let mirrorsIntoEngineContainer: Bool

    private func clamp<T: Comparable>(_ value: T, min minValue: T, max maxValue: T) -> T {
        return max(minValue, min(maxValue, value))
    }


    private func persistAndNotify() {
        defaults?.synchronize()
        if mirrorsIntoEngineContainer {
            writeEnginePlist()
        }
        notifyChanged()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: Preferences.didChangeNotification, object: self)
    }

    var zoomSpeed: Double {
        get {
            let value = storedDouble(forKey: Keys.zoomSpeed) ?? 0
            let speed = value > 0 ? value : Defaults.zoomSpeed
            return clamp(speed, min: 0.965, max: 0.9975)
        }
        set {
            let clamped = clamp(newValue, min: 0.965, max: 0.9975)
            defaults?.set(clamped, forKey: Keys.zoomSpeed)
            persistAndNotify()
        }
    }

    var paletteIndex: Int {
        get {
            let value = storedInt(forKey: Keys.paletteIndex) ?? Defaults.paletteIndex
            return clamp(value, min: 0, max: Preferences.paletteNames.count - 1)
        }
        set {
            let clamped = clamp(newValue, min: 0, max: Preferences.paletteNames.count - 1)
            defaults?.set(clamped, forKey: Keys.paletteIndex)
            persistAndNotify()
        }
    }

    var autoCyclePalettes: Bool {
        get {
            storedBool(forKey: Keys.autoCyclePalettes) ?? Defaults.autoCyclePalettes
        }
        set {
            defaults?.set(newValue, forKey: Keys.autoCyclePalettes)
            persistAndNotify()
        }
    }

    /// Shading mode: 0 = flat, 1 = 3D Blinn-Phong, 2 = angle-based, 3 = stripe
    var shadingMode: Int {
        get {
            let value = storedInt(forKey: Keys.shadingMode) ?? Defaults.shadingMode
            return clamp(value, min: 0, max: Preferences.shadingModeNames.count - 1)
        }
        set {
            let clamped = clamp(newValue, min: 0, max: Preferences.shadingModeNames.count - 1)
            defaults?.set(clamped, forKey: Keys.shadingMode)
            persistAndNotify()
        }
    }

    var juliaMode: Bool {
        get {
            storedBool(forKey: Keys.juliaMode) ?? Defaults.juliaMode
        }
        set {
            defaults?.set(newValue, forKey: Keys.juliaMode)
            persistAndNotify()
        }
    }

    /// Visual quality: 0 = Standard, 1 = Ultra
    var visualQuality: Int {
        get {
            let value = storedInt(forKey: Keys.visualQuality) ?? Defaults.visualQuality
            return clamp(value, min: 0, max: Preferences.visualQualityNames.count - 1)
        }
        set {
            let clamped = clamp(newValue, min: 0, max: Preferences.visualQualityNames.count - 1)
            defaults?.set(clamped, forKey: Keys.visualQuality)
            persistAndNotify()
        }
    }

    var batterySaver: Bool {
        get {
            storedBool(forKey: Keys.batterySaver) ?? Defaults.batterySaver
        }
        set {
            defaults?.set(newValue, forKey: Keys.batterySaver)
            persistAndNotify()
        }
    }

    private init() {
        let bundlePath = Bundle(for: Preferences.self).bundlePath
        mirrorsIntoEngineContainer = !bundlePath.contains(".saver")
        defaults = ScreenSaverDefaults(forModuleWithName: Preferences.moduleName)
        defaults?.register(defaults: [
            Keys.zoomSpeed: Defaults.zoomSpeed,
            Keys.paletteIndex: Defaults.paletteIndex,
            Keys.autoCyclePalettes: Defaults.autoCyclePalettes,
            Keys.shadingMode: Defaults.shadingMode,
            Keys.juliaMode: Defaults.juliaMode,
            Keys.visualQuality: Defaults.visualQuality,
            Keys.batterySaver: Defaults.batterySaver
        ])
        if mirrorsIntoEngineContainer {
            writeEnginePlist()
        }
    }

    func resetToDefaults() {
        defaults?.set(Defaults.zoomSpeed, forKey: Keys.zoomSpeed)
        defaults?.set(Defaults.paletteIndex, forKey: Keys.paletteIndex)
        defaults?.set(Defaults.autoCyclePalettes, forKey: Keys.autoCyclePalettes)
        defaults?.set(Defaults.shadingMode, forKey: Keys.shadingMode)
        defaults?.set(Defaults.juliaMode, forKey: Keys.juliaMode)
        defaults?.set(Defaults.visualQuality, forKey: Keys.visualQuality)
        defaults?.set(Defaults.batterySaver, forKey: Keys.batterySaver)
        persistAndNotify()
    }

    static let paletteNames = [
        "Ultra Fractal",
        "Ember",
        "Abyss",
        "Neon",
        "Aurora",
        "Graphite"
    ]

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

    // MARK: - Engine container store

    private static var engineByHostDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences/ByHost")
    }

    private static func byHostUUID(in directory: URL) -> String? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return nil }
        for url in urls where url.pathExtension == "plist" {
            let base = url.deletingPathExtension().lastPathComponent
            guard let dot = base.lastIndex(of: ".") else { continue }
            let uuid = String(base[base.index(after: dot)...])
            if uuid.count == 36 { return uuid }
        }
        return nil
    }

    private func enginePlistURL() -> URL? {
        let dir = Self.engineByHostDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let uuid = Self.byHostUUID(in: dir)
            ?? Self.byHostUUID(in: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/ByHost"))
        guard let uuid else { return nil }
        return dir.appendingPathComponent("\(Self.moduleName).\(uuid).plist")
    }

    private func engineDictionary() -> [String: Any]? {
        guard let url = enginePlistURL() else { return nil }
        return NSDictionary(contentsOf: url) as? [String: Any]
    }

    private func storedObject(forKey key: String) -> Any? {
        if mirrorsIntoEngineContainer, let value = engineDictionary()?[key] {
            return value
        }
        return defaults?.object(forKey: key)
    }

    private func storedDouble(forKey key: String) -> Double? {
        (storedObject(forKey: key) as? NSNumber)?.doubleValue
    }

    private func storedInt(forKey key: String) -> Int? {
        (storedObject(forKey: key) as? NSNumber)?.intValue
    }

    private func storedBool(forKey key: String) -> Bool? {
        guard storedObject(forKey: key) != nil else { return nil }
        if let number = storedObject(forKey: key) as? NSNumber {
            return number.boolValue
        }
        return storedObject(forKey: key) as? Bool
    }

    private func writeEnginePlist() {
        guard let url = enginePlistURL(), let defaults else { return }
        var dict = engineDictionary() ?? [:]
        let keys = [
            Keys.zoomSpeed,
            Keys.paletteIndex,
            Keys.autoCyclePalettes,
            Keys.shadingMode,
            Keys.juliaMode,
            Keys.visualQuality,
            Keys.batterySaver
        ]
        for key in keys {
            if let value = defaults.object(forKey: key) {
                dict[key] = value
            }
        }
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: dict,
            format: .binary,
            options: 0
        ) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
