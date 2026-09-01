import CoreGraphics
import Foundation

/// What Lumen remembers about one display.
public struct DisplayPreferences: Codable, Equatable {
    public var brightness: Double?
    public var contrast: Double?
    public var warmth: Double?
    public var followsBuiltIn: Bool?
    public var followRatio: Double?
    public var volume: Double?
    public var modeID: String?
    public var rotation: Int?
    /// When set, an outside change to mode or rotation is put back.
    public var protected: Bool?
    public var updatedAt: Date = .init()

    public var isEmpty: Bool {
        brightness == nil && contrast == nil && warmth == nil
            && volume == nil && modeID == nil && rotation == nil
    }
}

/// Per-display memory, keyed by identity rather than display ID.
///
/// Display IDs are reassigned on every reconnect, so a laptop that gets docked
/// and undocked twice a day would never match its own saved settings. The
/// EDID-derived `persistentKey` survives.
public final class DisplaySettingsStore {
    public static let shared = DisplaySettingsStore()

    private static let storageKey = "displayPreferences"
    private static let enabledKey = "rememberPerDisplay"

    private let lock = NSLock()

    private init() {}

    /// Read through to the shared store on every access rather than caching a
    /// snapshot at launch. The app and `lumenctl` are separate processes; a
    /// cached copy meant a display locked from one was never enforced by the
    /// other, and the staleness was invisible until something depended on it.
    private var storage: [String: DisplayPreferences] {
        get {
            guard let data = Defaults.shared.data(forKey: Self.storageKey),
                  let decoded = try? JSONDecoder().decode([String: DisplayPreferences].self, from: data)
            else { return [:] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            Defaults.shared.set(data, forKey: Self.storageKey)
        }
    }

    /// Off by default: restoring a resolution the user did not ask for is the
    /// kind of surprise that makes a utility feel haunted.
    public var isEnabled: Bool {
        get { Defaults.shared.bool(forKey: Self.enabledKey) }
        set { Defaults.shared.set(newValue, forKey: Self.enabledKey) }
    }

    public func preferences(for key: String) -> DisplayPreferences? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    /// Writes regardless of the global remember switch — for state the user
    /// asked for explicitly, like a protection lock.
    public func writeAlways(_ key: String, _ mutate: (inout DisplayPreferences) -> Void) {
        lock.lock()
        var preferences = storage[key] ?? DisplayPreferences()
        mutate(&preferences)
        preferences.updatedAt = Date()
        storage[key] = preferences
        lock.unlock()
    }

    public func update(_ key: String, _ mutate: (inout DisplayPreferences) -> Void) {
        guard isEnabled else { return }
        lock.lock()
        var preferences = storage[key] ?? DisplayPreferences()
        mutate(&preferences)
        preferences.updatedAt = Date()
        storage[key] = preferences
        lock.unlock()
    }

    public func forget(_ key: String) {
        lock.lock()
        storage.removeValue(forKey: key)
        lock.unlock()
    }

    public func forgetAll() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }

    public var rememberedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return storage.count
    }

    /// Put a protected display back to the mode and orientation it was locked
    /// at. Unlike `restore(to:)` this runs on every reconfiguration, so an
    /// external change — macOS resetting a monitor on wake, another app,
    /// anything — is undone rather than merely remembered.
    @discardableResult
    public func enforceProtection(on display: DisplayInfo) -> [String] {
        guard let preferences = preferences(for: display.persistentKey),
              preferences.protected == true else { return [] }
        var corrected: [String] = []

        if let modeID = preferences.modeID, display.currentMode?.id != modeID,
           let mode = ModeEngine.allModes(for: display.id).first(where: { $0.id == modeID }),
           ModeEngine.apply(mode, to: display.id) {
            corrected.append(L10n.t("分辨率", "resolution"))
        }
        if let rotation = preferences.rotation, let angle = Rotation(rawValue: rotation),
           angle != display.rotation, RotationEngine.isSupported(for: display),
           RotationEngine.rotate(display, to: angle) {
            corrected.append(L10n.t("方向", "orientation"))
        }
        if !corrected.isEmpty {
            Log.info("protection restored \(corrected.joined(separator: ",")) on \(display.name)")
        }
        return corrected
    }

    public func isProtected(_ key: String) -> Bool {
        preferences(for: key)?.protected == true
    }

    /// Locking captures what is on screen right now as the state to hold.
    ///
    /// Protection writes through `writeAlways` rather than switching on the
    /// separate "remember every display" preference: locking one monitor is not
    /// consent to start remembering settings for every other one.
    public func setProtected(_ on: Bool, for display: DisplayInfo) {
        writeAlways(display.persistentKey) { preferences in
            preferences.protected = on
            if on {
                preferences.modeID = display.currentMode?.id
                preferences.rotation = display.rotation.rawValue
            }
        }
    }

    /// What was actually put back, so the UI can say so rather than acting
    /// invisibly. A saved mode is only reapplied if the display still offers
    /// that exact mode — a monitor on a different cable may not.
    @discardableResult
    public func restore(to display: DisplayInfo) -> [String] {
        guard isEnabled, let preferences = preferences(for: display.persistentKey) else { return [] }
        var restored: [String] = []

        if let modeID = preferences.modeID,
           let mode = ModeEngine.allModes(for: display.id).first(where: { $0.id == modeID }),
           mode.id != display.currentMode?.id,
           ModeEngine.apply(mode, to: display.id) {
            restored.append(L10n.t("分辨率", "resolution"))
        }

        if let rotation = preferences.rotation,
           let angle = Rotation(rawValue: rotation),
           angle != display.rotation,
           RotationEngine.isSupported(for: display),
           RotationEngine.rotate(display, to: angle) {
            restored.append(L10n.t("方向", "orientation"))
        }

        if let brightness = preferences.brightness,
           BrightnessEngine.shared.setBrightness(brightness, for: display) {
            restored.append(L10n.t("亮度", "brightness"))
        }

        if let contrast = preferences.contrast,
           BrightnessEngine.shared.setContrast(contrast, for: display) {
            restored.append(L10n.t("对比度", "contrast"))
        }

        if let warmth = preferences.warmth, warmth > 0.001,
           BrightnessEngine.shared.setWarmth(warmth, for: display) {
            restored.append(L10n.t("色温", "colour temperature"))
        }

        if let volume = preferences.volume,
           AudioEngine.shared.setVolume(volume, for: display) {
            restored.append(L10n.t("音量", "volume"))
        }

        if !restored.isEmpty {
            Log.info("restored \(restored.joined(separator: ",")) for \(display.name)")
        }
        return restored
    }
}
