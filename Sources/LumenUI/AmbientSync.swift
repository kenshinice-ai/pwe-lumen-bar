import Foundation
import LumenCore

/// Makes external displays follow the built-in panel's brightness.
///
/// A MacBook's built-in display has an ambient light sensor and macOS keeps it
/// adjusted; an external monitor has neither, and stays at whatever it was set
/// to when the room was a different brightness. This watches the built-in value
/// and moves the others with it, keeping the ratio each display had when the
/// user turned the feature on — so a deliberately dimmer second screen stays
/// proportionally dimmer.
@MainActor
final class AmbientSync {
    /// The built-in brightness moves in small steps; anything below this is
    /// noise not worth a DDC write.
    private static let threshold = 0.01
    private static let interval: TimeInterval = 5

    private var timer: Timer?
    private var lastBuiltInValue: Double?
    private let onAdjust: (DisplayInfo, Double) -> Void

    init(onAdjust: @escaping (DisplayInfo, Double) -> Void) {
        self.onAdjust = onAdjust
    }

    deinit { timer?.invalidate() }

    /// Runs only while at least one display is set to follow.
    func update(hasFollowers: Bool) {
        if hasFollowers, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            lastBuiltInValue = currentBuiltInBrightness()
            Log.info("ambient sync started")
        } else if !hasFollowers, timer != nil {
            timer?.invalidate()
            timer = nil
            Log.info("ambient sync stopped")
        }
    }

    private func currentBuiltInBrightness() -> Double? {
        guard let builtIn = DisplayRegistry.shared.onlineDisplays().first(where: \.isBuiltin)
        else { return nil }
        return BrightnessEngine.shared.brightness(of: builtIn)
    }

    private func tick() {
        guard let current = currentBuiltInBrightness() else { return }
        defer { lastBuiltInValue = current }
        guard let previous = lastBuiltInValue,
              abs(current - previous) >= Self.threshold else { return }

        for display in DisplayRegistry.shared.onlineDisplays() where !display.isBuiltin {
            guard let preferences = DisplaySettingsStore.shared.preferences(for: display.persistentKey),
                  preferences.followsBuiltIn == true else { continue }
            let ratio = preferences.followRatio ?? 1.0
            onAdjust(display, min(max(current * ratio, 0), 1))
        }
    }
}
