import ScreenSaver
import Foundation

final class Preferences {
    static let shared = Preferences()
    static let didChangeNotification = Notification.Name("HyperspaceBloomPreferencesDidChange")

    // ScreenSaverDefaults requires the bundle identifier, not the executable
    // or display name. Using the short module name creates a different domain
    // in the settings app and the remote screen-saver host.
    private static let moduleIdentifier = "com.proofofreach.HyperspaceBloom"

    private enum Keys {
        static let motionSpeed = "motionSpeed"
        static let paletteIndex = "paletteIndex"
        static let autoCyclePalettes = "autoCyclePalettes"
        static let symmetryIndex = "symmetryIndex"
        static let intensity = "intensity"
        static let visualQuality = "visualQuality"
        static let batterySaver = "batterySaver"
    }

    private enum Defaults {
        static let motionSpeed = 1.0
        static let paletteIndex = 0
        static let autoCyclePalettes = true
        static let symmetryIndex = 0
        static let intensity = 1
        static let visualQuality = 1
        static let batterySaver = true
    }

    private let defaults: ScreenSaverDefaults?
    private let mirrorsIntoEngineContainer: Bool

    private init() {
        let bundlePath = Bundle(for: Preferences.self).bundlePath
        mirrorsIntoEngineContainer = !bundlePath.contains(".saver")
        defaults = ScreenSaverDefaults(forModuleWithName: Self.moduleIdentifier)
        defaults?.register(defaults: [
            Keys.motionSpeed: Defaults.motionSpeed,
            Keys.paletteIndex: Defaults.paletteIndex,
            Keys.autoCyclePalettes: Defaults.autoCyclePalettes,
            Keys.symmetryIndex: Defaults.symmetryIndex,
            Keys.intensity: Defaults.intensity,
            Keys.visualQuality: Defaults.visualQuality,
            Keys.batterySaver: Defaults.batterySaver,
        ])
        if mirrorsIntoEngineContainer {
            writeEnginePlist()
        }
    }

    var motionSpeed: Double {
        get {
            let value = defaults?.double(forKey: Keys.motionSpeed) ?? Defaults.motionSpeed
            return clamp(value, min: 0.4, max: 1.6)
        }
        set {
            defaults?.set(clamp(newValue, min: 0.4, max: 1.6), forKey: Keys.motionSpeed)
            persistAndNotify()
        }
    }

    var paletteIndex: Int {
        get {
            return clamp(defaults?.integer(forKey: Keys.paletteIndex) ?? Defaults.paletteIndex,
                         min: 0, max: Self.paletteNames.count - 1)
        }
        set {
            defaults?.set(clamp(newValue, min: 0, max: Self.paletteNames.count - 1),
                          forKey: Keys.paletteIndex)
            persistAndNotify()
        }
    }

    var autoCyclePalettes: Bool {
        get { boolValue(forKey: Keys.autoCyclePalettes, default: Defaults.autoCyclePalettes) }
        set {
            defaults?.set(newValue, forKey: Keys.autoCyclePalettes)
            persistAndNotify()
        }
    }

    /// 0 = automatic; remaining indices map through `symmetryValues`.
    var symmetryIndex: Int {
        get {
            return clamp(defaults?.integer(forKey: Keys.symmetryIndex) ?? Defaults.symmetryIndex,
                         min: 0, max: Self.symmetryNames.count - 1)
        }
        set {
            defaults?.set(clamp(newValue, min: 0, max: Self.symmetryNames.count - 1),
                          forKey: Keys.symmetryIndex)
            persistAndNotify()
        }
    }

    var forcedSymmetry: Int? {
        let index = symmetryIndex
        guard index > 0 else { return nil }
        return Self.symmetryValues[index]
    }

    /// 0 = calm, 1 = visionary, 2 = maximum.
    var intensity: Int {
        get {
            return clamp(defaults?.integer(forKey: Keys.intensity) ?? Defaults.intensity,
                         min: 0, max: Self.intensityNames.count - 1)
        }
        set {
            defaults?.set(clamp(newValue, min: 0, max: Self.intensityNames.count - 1),
                          forKey: Keys.intensity)
            persistAndNotify()
        }
    }

    var intensityValue: Float {
        return [0.62, 0.92, 1.18][intensity]
    }

    /// 0 = standard, 1 = ultra.
    var visualQuality: Int {
        get {
            return clamp(defaults?.integer(forKey: Keys.visualQuality) ?? Defaults.visualQuality,
                         min: 0, max: Self.visualQualityNames.count - 1)
        }
        set {
            defaults?.set(clamp(newValue, min: 0, max: Self.visualQualityNames.count - 1),
                          forKey: Keys.visualQuality)
            persistAndNotify()
        }
    }

    var batterySaver: Bool {
        get { boolValue(forKey: Keys.batterySaver, default: Defaults.batterySaver) }
        set {
            defaults?.set(newValue, forKey: Keys.batterySaver)
            persistAndNotify()
        }
    }

    func resetToDefaults() {
        defaults?.set(Defaults.motionSpeed, forKey: Keys.motionSpeed)
        defaults?.set(Defaults.paletteIndex, forKey: Keys.paletteIndex)
        defaults?.set(Defaults.autoCyclePalettes, forKey: Keys.autoCyclePalettes)
        defaults?.set(Defaults.symmetryIndex, forKey: Keys.symmetryIndex)
        defaults?.set(Defaults.intensity, forKey: Keys.intensity)
        defaults?.set(Defaults.visualQuality, forKey: Keys.visualQuality)
        defaults?.set(Defaults.batterySaver, forKey: Keys.batterySaver)
        persistAndNotify()
    }

    private func boolValue(forKey key: String, default defaultValue: Bool) -> Bool {
        guard defaults?.object(forKey: key) != nil else { return defaultValue }
        return defaults?.bool(forKey: key) ?? defaultValue
    }

    private func clamp<T: Comparable>(_ value: T, min minValue: T, max maxValue: T) -> T {
        return max(minValue, min(maxValue, value))
    }

    private func persistAndNotify() {
        defaults?.synchronize()
        if mirrorsIntoEngineContainer {
            writeEnginePlist()
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    static let paletteNames = [
        "Cosmic Orchid",
        "Electric Lotus",
        "Solar Temple",
        "Abyssal Cyan",
        "Woven Vision",
        "Pearl Void",
    ]

    static let symmetryNames = ["Automatic", "6-fold", "7-fold", "8-fold", "10-fold", "12-fold"]
    static let symmetryValues = [0, 6, 7, 8, 10, 12]
    static let intensityNames = ["Calm", "Visionary", "Maximum"]
    static let visualQualityNames = ["Standard", "Ultra"]

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
        return dir.appendingPathComponent("\(Self.moduleIdentifier).\(uuid).plist")
    }

    private func writeEnginePlist() {
        guard let url = enginePlistURL(), let defaults else { return }
        var dict = (NSDictionary(contentsOf: url) as? [String: Any]) ?? [:]
        for key in [
            Keys.motionSpeed,
            Keys.paletteIndex,
            Keys.autoCyclePalettes,
            Keys.symmetryIndex,
            Keys.intensity,
            Keys.visualQuality,
            Keys.batterySaver
        ] {
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
