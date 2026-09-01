import CoreGraphics
import Foundation

/// Brightness across three channels, picked per display.
///
/// * `DisplayServices` — the same private path the F1/F2 keys use. Works for
///   the built-in panel and Apple external displays.
/// * `DDC` — VCP 0x10 over I2C. The only hardware path for third-party monitors.
/// * `gamma` — a software transfer curve. Not real brightness (the backlight
///   stays put) but it is the honest fallback for panels that answer neither
///   of the above, and it can push any display below its hardware minimum.
public final class BrightnessEngine {
    public static let shared = BrightnessEngine()

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeBrightness = @convention(c) (CGDirectDisplayID) -> Bool

    private var channelCache: [CGDirectDisplayID: BrightnessChannel] = [:]
    /// Identities that have answered DDC brightness at least once.
    private var knownDDCDisplays: Set<String> = []
    private var softwareLevels: [CGDirectDisplayID: Double] = [:]
    private let lock = NSLock()

    private init() {
        Dyn.load("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices")
    }

    // MARK: - Channel selection

    public func channel(for display: DisplayInfo) -> BrightnessChannel {
        lock.lock()
        if let cached = channelCache[display.id] { lock.unlock(); return cached }
        lock.unlock()

        let resolved: BrightnessChannel
        if canUseDisplayServices(display.id) {
            resolved = .displayServices
        } else if supportsDDCBrightness(display) {
            resolved = .ddc
        } else if !display.isBuiltin {
            // No hardware answer — software dimming still gives real control.
            resolved = .gamma
        } else {
            resolved = .none
        }

        lock.lock()
        channelCache[display.id] = resolved
        // Remember a hardware channel against the display's identity. DDC reads
        // are occasionally flaky, and one dropped reply used to demote a
        // monitor to software dimming for the rest of the session — the slider
        // kept moving while the backlight stopped listening.
        if resolved == .ddc { knownDDCDisplays.insert(display.persistentKey) }
        lock.unlock()
        Log.info("brightness channel for \(display.name): \(resolved.rawValue)")
        return resolved
    }

    public func invalidate() {
        // The per-ID cache goes; the identity-based knowledge that a monitor
        // speaks DDC survives, because that does not change when a cable moves.
        lock.lock(); channelCache.removeAll(); lock.unlock()
    }

    /// Trust the monitor's own capabilities list first, then a live read, then
    /// anything it has answered before. Only a display that has never once
    /// spoken DDC gets demoted to software dimming.
    private func supportsDDCBrightness(_ display: DisplayInfo) -> Bool {
        lock.lock()
        let knownGood = knownDDCDisplays.contains(display.persistentKey)
        lock.unlock()
        if knownGood { return true }

        if let capabilities = DDCRegistry.shared.capabilities(for: display) {
            return capabilities.supports(.brightness)
        }
        return DDCRegistry.shared.service(for: display)?.read(.brightness) != nil
    }

    private func canUseDisplayServices(_ id: CGDirectDisplayID) -> Bool {
        guard let canChange = Dyn.symbol("DisplayServicesCanChangeBrightness", as: CanChangeBrightness.self)
        else { return false }
        return canChange(id)
    }

    // MARK: - Read / write

    public func brightness(of display: DisplayInfo) -> Double? {
        switch channel(for: display) {
        case .displayServices:
            guard let get = Dyn.symbol("DisplayServicesGetBrightness", as: GetBrightness.self)
            else { return nil }
            var value: Float = 0
            guard get(display.id, &value) == 0 else { return nil }
            return Double(value)
        case .ddc:
            return DDCRegistry.shared.service(for: display)?.read(.brightness)?.percent
        case .gamma:
            return softwareDim(of: display)
        case .none:
            return nil
        }
    }

    @discardableResult
    public func setBrightness(_ value: Double, for display: DisplayInfo) -> Bool {
        let clamped = min(max(value, 0), 1)
        switch channel(for: display) {
        case .displayServices:
            guard let set = Dyn.symbol("DisplayServicesSetBrightness", as: SetBrightness.self)
            else { return false }
            return set(display.id, Float(clamped)) == 0
        case .ddc:
            guard let ddc = DDCRegistry.shared.service(for: display) else { return false }
            let maximum = ddc.read(.brightness)?.maximum ?? 100
            return ddc.write(.brightness, value: UInt16((clamped * Double(maximum)).rounded()))
        case .gamma:
            return setSoftwareDim(clamped, for: display)
        case .none:
            return false
        }
    }

    // MARK: - Gamma: software dimming and colour temperature

    /// Dimming and warmth share one gamma table, so they are stored together
    /// and always written as a single composed curve. Setting them through
    /// separate calls would make each one silently undo the other.
    private struct GammaState {
        var dim: Double = 1.0
        var warmth: Double = 0.0
    }

    private var gammaStates: [CGDirectDisplayID: GammaState] = [:]

    private func write(_ state: GammaState, to displayID: CGDirectDisplayID) -> Bool {
        // Software dimming alone is floored at 0.08, because a gamma curve
        // really can reach black and a screen at zero cannot be recovered from
        // a menu living on it. The hardware channels are *not* clamped: zero on
        // DisplayServices or DDC is the panel's minimum backlight, which stays
        // readable, and refusing it would take away a setting macOS itself
        // allows.
        let dim = Float(min(max(state.dim, 0.08), 1.0))
        let warmth = Float(min(max(state.warmth, 0.0), 1.0))
        // Warmer means pulling blue down hardest, green a little, red not at all.
        let red = dim
        let green = dim * (1 - 0.14 * warmth)
        let blue = dim * (1 - 0.40 * warmth)
        return CGSetDisplayTransferByFormula(displayID,
                                             0, red, 1,
                                             0, green, 1,
                                             0, blue, 1) == .success
    }

    private func mutateGamma(_ display: DisplayInfo,
                             _ mutate: (inout GammaState) -> Void) -> Bool {
        lock.lock()
        var state = gammaStates[display.id] ?? GammaState()
        mutate(&state)
        gammaStates[display.id] = state
        lock.unlock()
        return write(state, to: display.id)
    }

    /// `level` 1.0 is untouched, 0.08 is very dark.
    @discardableResult
    public func setSoftwareDim(_ level: Double, for display: DisplayInfo) -> Bool {
        mutateGamma(display) { $0.dim = level }
    }

    public func softwareDim(of display: DisplayInfo) -> Double {
        lock.lock(); defer { lock.unlock() }
        return gammaStates[display.id]?.dim ?? 1.0
    }

    /// `warmth` 0 leaves colour alone; 1 is the warmest this applies.
    @discardableResult
    public func setWarmth(_ warmth: Double, for display: DisplayInfo) -> Bool {
        mutateGamma(display) { $0.warmth = warmth }
    }

    public func warmth(of display: DisplayInfo) -> Double {
        lock.lock(); defer { lock.unlock() }
        return gammaStates[display.id]?.warmth ?? 0.0
    }

    /// Re-apply after a reconfiguration — macOS resets gamma tables whenever a
    /// display mode changes.
    public func reapplySoftwareDimming() {
        lock.lock()
        let states = gammaStates
        lock.unlock()
        for display in DisplayRegistry.shared.onlineDisplays() {
            guard let state = states[display.id],
                  state.dim < 0.999 || state.warmth > 0.001 else { continue }
            _ = write(state, to: display.id)
        }
    }

    /// Always call before quitting: gamma changes outlive the process.
    public func restoreAllGamma() {
        CGDisplayRestoreColorSyncSettings()
        lock.lock(); gammaStates.removeAll(); lock.unlock()
    }

    // MARK: - Contrast (DDC only)

    public func contrast(of display: DisplayInfo) -> Double? {
        DDCRegistry.shared.service(for: display)?.read(.contrast)?.percent
    }

    @discardableResult
    public func setContrast(_ value: Double, for display: DisplayInfo) -> Bool {
        guard let ddc = DDCRegistry.shared.service(for: display) else { return false }
        let maximum = ddc.read(.contrast)?.maximum ?? 100
        return ddc.write(.contrast, value: UInt16((min(max(value, 0), 1) * Double(maximum)).rounded()))
    }
}
