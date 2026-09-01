import CoreGraphics
import Foundation

/// One display's state inside a preset.
public struct DisplaySnapshot: Codable, Equatable {
    public var persistentKey: String
    public var displayName: String
    public var brightness: Double?
    public var contrast: Double?
    public var warmth: Double?
    public var volume: Double?
    public var modeID: String?
    public var rotation: Int?
    public var colorProfilePath: String?
    public var originX: Double?
    public var originY: Double?
}

/// A named arrangement of every attached display.
public struct Preset: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var displays: [DisplaySnapshot]
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, displays: [DisplaySnapshot], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.displays = displays
        self.createdAt = createdAt
    }
}

/// Saving and restoring whole-desk states.
///
/// Every individual control already exists; a preset is what turns "adjust six
/// things across two screens" into one click. Order of application matters and
/// is fixed here: resolution first because it changes a display's size, then
/// positions computed against those new sizes, then everything cosmetic.
public final class PresetStore {
    public static let shared = PresetStore()

    private static let storageKey = "presets"
    private let lock = NSLock()

    private init() {}

    /// Read through, so a preset saved in the menu is immediately visible to
    /// `lumenctl` and the other way round.
    private var storage: [Preset] {
        get {
            guard let data = Defaults.shared.data(forKey: Self.storageKey),
                  let decoded = try? JSONDecoder().decode([Preset].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            Defaults.shared.set(data, forKey: Self.storageKey)
        }
    }

    public var presets: [Preset] {
        lock.lock(); defer { lock.unlock() }
        return storage.sorted { $0.createdAt < $1.createdAt }
    }

    public func preset(named name: String) -> Preset? {
        presets.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: - Capture

    /// Snapshot everything currently on the desk.
    public func capture(name: String) -> Preset {
        let snapshots = DisplayRegistry.shared.onlineDisplays().map { display in
            DisplaySnapshot(
                persistentKey: display.persistentKey,
                displayName: display.name,
                brightness: BrightnessEngine.shared.brightness(of: display),
                contrast: BrightnessEngine.shared.contrast(of: display),
                warmth: BrightnessEngine.shared.warmth(of: display),
                volume: AudioEngine.shared.volume(of: display),
                modeID: display.currentMode?.id,
                rotation: display.rotation.rawValue,
                colorProfilePath: ColorEngine.currentProfileURL(for: display.id)?.path,
                originX: Double(display.bounds.origin.x),
                originY: Double(display.bounds.origin.y)
            )
        }
        let preset = Preset(name: name, displays: snapshots)
        lock.lock()
        // Replacing a same-named preset is what people expect from "save".
        storage.removeAll { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        storage.append(preset)
        lock.unlock()
        Log.info("captured preset '\(name)' with \(snapshots.count) display(s)")
        return preset
    }

    public func delete(_ id: UUID) {
        lock.lock()
        storage.removeAll { $0.id == id }
        lock.unlock()
    }

    public func rename(_ id: UUID, to name: String) {
        lock.lock()
        if let index = storage.firstIndex(where: { $0.id == id }) {
            storage[index].name = name
            }
        lock.unlock()
    }

    // MARK: - Apply

    /// Returns the names of displays that were matched and restored. Displays
    /// in the preset that are not currently attached are skipped silently —
    /// a "laptop only" preset should still work while docked.
    @discardableResult
    public func apply(_ preset: Preset) -> [String] {
        let online = DisplayRegistry.shared.onlineDisplays()
        var applied: [String] = []

        // 1. Resolution — changes each display's size, so it has to go first.
        var changedMode = false
        for snapshot in preset.displays {
            guard let display = online.first(where: { $0.persistentKey == snapshot.persistentKey })
            else { continue }
            applied.append(display.name)
            guard let modeID = snapshot.modeID, modeID != display.currentMode?.id,
                  let mode = ModeEngine.allModes(for: display.id).first(where: { $0.id == modeID })
            else { continue }
            if ModeEngine.apply(mode, to: display.id) { changedMode = true }
        }

        // 2. Positions, against the sizes those modes just produced.
        let current = changedMode ? DisplayRegistry.shared.onlineDisplays() : online
        var origins: [CGDirectDisplayID: CGPoint] = [:]
        for snapshot in preset.displays {
            guard let display = current.first(where: { $0.persistentKey == snapshot.persistentKey }),
                  let x = snapshot.originX, let y = snapshot.originY else { continue }
            origins[display.id] = CGPoint(x: x, y: y)
        }
        if !origins.isEmpty { ArrangementEngine.applyOrigins(origins) }

        // 3. Everything that does not move geometry around.
        for snapshot in preset.displays {
            guard let display = current.first(where: { $0.persistentKey == snapshot.persistentKey })
            else { continue }

            if let rotation = snapshot.rotation, let angle = Rotation(rawValue: rotation),
               angle != display.rotation, RotationEngine.isSupported(for: display) {
                _ = RotationEngine.rotate(display, to: angle)
            }
            if let brightness = snapshot.brightness {
                _ = BrightnessEngine.shared.setBrightness(brightness, for: display)
            }
            if let contrast = snapshot.contrast {
                _ = BrightnessEngine.shared.setContrast(contrast, for: display)
            }
            if let warmth = snapshot.warmth {
                _ = BrightnessEngine.shared.setWarmth(warmth, for: display)
            }
            if let volume = snapshot.volume {
                _ = AudioEngine.shared.setVolume(volume, for: display)
            }
            if let path = snapshot.colorProfilePath {
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: path) {
                    _ = ColorEngine.apply(ColorProfile(id: path,
                                                       name: url.lastPathComponent,
                                                       url: url),
                                          to: display.id)
                }
            }
        }
        Log.info("applied preset '\(preset.name)' to \(applied.count) display(s)")
        return applied
    }
}
