import AppKit
import CoreGraphics
import Foundation

/// Turning displays off, waking them, and rearranging the desktop.
public enum PowerEngine {

    /// Which displays PWE Lumen Bar put to sleep, and by which route — needed to wake
    /// them the same way they were turned off.
    public static var sleepStates: [String: SleepMethod] = [:]

    public enum DisconnectResult {
        case ok
        case refusedLastDisplay
        case unsupported
        case failed(CGError)

        public var message: String {
            switch self {
            case .ok:
                return L10n.t("已断开", "Disconnected")
            case .refusedLastDisplay:
                return L10n.t("这是唯一在用的屏幕，断开后就没有可用画面了",
                              "This is the only display in use — disconnecting it would leave no picture")
            case .unsupported:
                return L10n.t("这台机器不支持软断开", "This Mac does not support soft disconnect")
            case .failed(let error):
                return L10n.t("断开失败 (CGError \(error.rawValue))",
                              "Disconnect failed (CGError \(error.rawValue))")
            }
        }
    }

    // MARK: - Soft disconnect

    private typealias ConfigureDisplayEnabled =
        @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Bool) -> CGError

    public static var supportsSoftDisconnect: Bool {
        Dyn.has("CGSConfigureDisplayEnabled")
    }

    /// Remove a display from the desktop without touching the monitor's power
    /// state — windows migrate away, the arrangement closes the gap.
    public static func setEnabled(_ enabled: Bool, display: DisplayInfo) -> DisconnectResult {
        guard let configureEnabled = Dyn.symbol("CGSConfigureDisplayEnabled",
                                                as: ConfigureDisplayEnabled.self)
        else { return .unsupported }

        // Never leave the machine with no usable screen.
        if !enabled {
            let online = DisplayRegistry.shared.onlineDisplays()
            let others = online.filter { $0.id != display.id && !$0.isMirrored }
            if others.isEmpty { return .refusedLastDisplay }
        }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            return .failed(.failure)
        }
        let status = configureEnabled(config, display.id, enabled)
        guard status == .success else {
            CGCancelDisplayConfiguration(config)
            return .failed(status)
        }
        let completion = CGCompleteDisplayConfiguration(config, .permanently)
        Log.info("soft \(enabled ? "connect" : "disconnect") \(display.name) → \(completion.rawValue)")
        return completion == .success ? .ok : .failed(completion)
    }

    // MARK: - DDC power (external monitors)

    public enum PowerMode: UInt16 {
        case on = 0x01
        case standby = 0x04
        case off = 0x05
    }

    @discardableResult
    public static func setDDCPower(_ mode: PowerMode, display: DisplayInfo) -> Bool {
        guard let ddc = DDCRegistry.shared.service(for: display) else { return false }
        return ddc.write(.powerMode, value: mode.rawValue)
    }

    // MARK: - Per-display sleep

    public enum SleepMethod: String, Codable, Sendable {
        /// The monitor's own power state, over DDC/CI.
        case ddc
        /// Taken off the desktop, which also blanks the panel.
        case softDisconnect
    }

    public enum SleepOutcome {
        case slept(SleepMethod)
        case refusedLastDisplay
        case failed

        public var message: String {
            switch self {
            case .slept(.ddc):
                return L10n.t("已关闭显示器电源", "Monitor powered off")
            case .slept(.softDisconnect):
                return L10n.t("已关闭这块屏", "Display turned off")
            case .refusedLastDisplay:
                return L10n.t("这是唯一在用的屏幕，关掉就没有画面了",
                              "This is the only display in use — turning it off would leave no picture")
            case .failed:
                return L10n.t("关闭失败", "Could not turn the display off")
            }
        }
    }

    /// Turn one display off, reversibly.
    ///
    /// This always takes the display off the desktop rather than cutting the
    /// monitor's power over DDC. That preference was learned the hard way: on a
    /// Philips 27B1U3900, `VCP 0xD6 = 0x05` put the monitor into a state where
    /// it vanished from CoreGraphics *and* its `DCPAVServiceProxy` disappeared
    /// with it — so there was no I2C pipe left to send a power-on through, and
    /// the only way back was the monitor's physical button.
    ///
    /// Soft disconnect blanks the panel just as effectively and always comes
    /// back. DDC power control is still available as an explicit action, with a
    /// warning attached.
    public static func sleepDisplay(_ display: DisplayInfo) -> SleepOutcome {
        switch setEnabled(false, display: display) {
        case .ok: return .slept(.softDisconnect)
        case .refusedLastDisplay: return .refusedLastDisplay
        case .unsupported, .failed: return .failed
        }
    }

    @discardableResult
    public static func wakeDisplay(_ display: DisplayInfo, method: SleepMethod) -> Bool {
        switch method {
        case .ddc:
            return setDDCPower(.on, display: display)
        case .softDisconnect:
            if case .ok = setEnabled(true, display: display) { return true }
            return false
        }
    }

    // MARK: - Sleep all displays

    /// System-wide display sleep — the same thing the hot corner does.
    public static func sleepAllDisplays() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        try? task.run()
    }

    // MARK: - Mirroring

    @discardableResult
    public static func setMirror(_ display: DisplayInfo, to target: CGDirectDisplayID?) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        let status = CGConfigureDisplayMirrorOfDisplay(config, display.id, target ?? kCGNullDirectDisplay)
        guard status == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    // MARK: - Main display

    /// Make a display the main one by translating the whole arrangement so this
    /// display's origin lands on (0, 0) — that origin *is* what "main" means.
    @discardableResult
    public static func setAsMain(_ display: DisplayInfo) -> Bool {
        let displays = DisplayRegistry.shared.onlineDisplays()
        guard let target = displays.first(where: { $0.id == display.id }) else { return false }
        let deltaX = -target.bounds.origin.x
        let deltaY = -target.bounds.origin.y

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        for other in displays {
            let status = CGConfigureDisplayOrigin(
                config, other.id,
                Int32(other.bounds.origin.x + deltaX),
                Int32(other.bounds.origin.y + deltaY))
            if status != .success {
                CGCancelDisplayConfiguration(config)
                return false
            }
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
}
