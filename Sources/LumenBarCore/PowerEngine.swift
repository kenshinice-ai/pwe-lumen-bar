import AppKit
import CoreGraphics
import Foundation

/// Turning displays off, waking them, and rearranging the desktop.
public enum PowerEngine {

    /// Which displays PWE Lumen Bar put to sleep, and by which route — needed to wake
    /// them the same way they were turned off.
    public static var sleepStates: [String: SleepMethod] = [:]

    /// Displays whose backlight PWE Lumen Bar cut over DDC in this session.
    ///
    /// Such a monitor stays *online* — CoreGraphics still lists it — while
    /// showing nothing, so "another display is online" is not the same as
    /// "another display is lit". The guard below needs the difference.
    public static var darkenedByDDC: Set<String> = []

    public enum DisconnectResult {
        public var isOK: Bool { if case .ok = self { return true } else { return false } }

        case ok
        case refusedLastDisplay
        /// Another display is online, but its backlight was cut over DDC.
        case refusedNoLitDisplay(darkName: String)
        case unsupported
        case failed(CGError)

        public var message: String {
            switch self {
            case .ok:
                return L10n.t("已断开", "Disconnected")
            case .refusedLastDisplay:
                return L10n.t("这是唯一在用的屏幕，断开后就没有可用画面了",
                              "This is the only display in use — disconnecting it would leave no picture")
            case .refusedNoLitDisplay(let darkName):
                return L10n.t("\(darkName) 的背光是用 DDC 关掉的，熄掉这块屏就没有亮着的屏了。先动一下鼠标或按一个键唤醒它，再试一次。",
                              "\(darkName)'s backlight was cut over DDC, so turning this display off would leave nothing lit. Wake it with the mouse or a key, then try again.")
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
    ///
    /// Committed `.permanently`, and not by oversight: the private call ignores
    /// the configuration scope (`.forAppOnly` was tried — the display stayed off
    /// after the process exited), so no scope would make the window server undo
    /// it for us. Bringing a display back is `OffDisplayStore`'s job.
    public static func setEnabled(_ enabled: Bool, display: DisplayInfo) -> DisconnectResult {
        // Never leave the machine without a screen someone can see.
        if !enabled {
            let online = DisplayRegistry.shared.onlineDisplays()
            let candidates = online.filter { $0.id != display.id }.map {
                RemainingDisplay(isMirror: $0.isMirrored, isDark: darkenedByDDC.contains($0.persistentKey),
                                 name: $0.name)
            }
            switch assessRemaining(candidates) {
            case .lit: break
            case .none: return .refusedLastDisplay
            case .onlyDark(let name):
                // Say it once. The monitor wakes on input, and by the time
                // someone reads this and tries again it almost certainly has —
                // a guard that kept refusing on a stale record would be worse
                // than the risk it covers.
                darkenedByDDC.removeAll()
                return .refusedNoLitDisplay(darkName: name)
            }
        }
        let result = setEnabled(enabled, id: display.id)
        Log.info("soft \(enabled ? "connect" : "disconnect") \(display.name) → \(result)")
        return result
    }

    /// Re-enable (or disable) by ID alone. A display taken off the desktop is not
    /// in the online list any more, so there is no `DisplayInfo` to pass — only the
    /// ID recorded when it went off.
    public static func setEnabled(_ enabled: Bool, id: CGDirectDisplayID) -> DisconnectResult {
        guard let configureEnabled = Dyn.symbol("CGSConfigureDisplayEnabled",
                                                as: ConfigureDisplayEnabled.self)
        else { return .unsupported }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            return .failed(.failure)
        }
        let status = configureEnabled(config, id, enabled)
        guard status == .success else {
            CGCancelDisplayConfiguration(config)
            return .failed(status)
        }
        let completion = CGCompleteDisplayConfiguration(config, .permanently)
        return completion == .success ? .ok : .failed(completion)
    }

    /// Bring a recorded display back, and report whether it actually came back.
    ///
    /// The window server's answer is not the evidence. Asked while the displays
    /// were asleep, enabling a display reported success and changed nothing —
    /// and a caller that believed it would forget the one record that could
    /// still bring that display back. So this watches for the display to appear
    /// online, by ID or by identity, for up to `timeout` seconds.
    public static func turnBackOn(_ record: OffRecord, timeout: TimeInterval = 3) -> Bool {
        _ = setEnabled(true, id: record.displayID)
        return waitUntilOnline(record, timeout: timeout)
    }

    public static func waitUntilOnline(_ record: OffRecord, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let online = DisplayRegistry.shared.onlineDisplays()
            if online.contains(where: { $0.id == record.displayID })
                || (!record.keyWasShared && online.contains(where: { $0.persistentKey == record.key })) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return false
    }

    /// Whether the main display is in display sleep — the one state in which a
    /// display cannot be brought back, and which is worth naming when it fails.
    public static var displaysAreAsleep: Bool {
        CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }

    /// The command line's last resort when nothing is on record: try to enable
    /// every display ID in range that is not active.
    ///
    /// One configuration per ID, completed only when the window server accepts
    /// that ID. Batching them into a single configuration was tried and brought
    /// nothing back: the first ID that does not exist is refused, and the whole
    /// configuration goes with it. IDs that do not exist are refused at the
    /// configure step and cancelled, so they cost no reconfiguration. The range
    /// is wide because display IDs keep climbing across reconnects.
    public static func enableEveryInactive(upTo limit: CGDirectDisplayID) -> Int {
        guard let configureEnabled = Dyn.symbol("CGSConfigureDisplayEnabled",
                                                as: ConfigureDisplayEnabled.self)
        else { return 0 }
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        CGGetActiveDisplayList(32, &ids, &count)
        let active = Set(ids.prefix(Int(count)))
        var accepted = 0
        for id in 1 ... limit where !active.contains(id) {
            var config: CGDisplayConfigRef?
            guard CGBeginDisplayConfiguration(&config) == .success, let config else { continue }
            guard configureEnabled(config, id, true) == .success else {
                CGCancelDisplayConfiguration(config)
                continue
            }
            if CGCompleteDisplayConfiguration(config, .permanently) == .success { accepted += 1 }
        }
        return accepted
    }

    /// What is left on screen if one display goes away.
    public struct RemainingDisplay: Sendable {
        public let isMirror: Bool
        public let isDark: Bool
        public let name: String
        public init(isMirror: Bool, isDark: Bool, name: String) {
            self.isMirror = isMirror
            self.isDark = isDark
            self.name = name
        }
    }

    public enum Remaining: Equatable, Sendable {
        case lit
        case none
        case onlyDark(name: String)
    }

    /// A mirror follows its source and cannot be relied on to stay; a display
    /// whose backlight was cut over DDC is present and dark. Neither counts.
    public static func assessRemaining(_ displays: [RemainingDisplay]) -> Remaining {
        let independent = displays.filter { !$0.isMirror }
        if independent.contains(where: { !$0.isDark }) { return .lit }
        if let dark = independent.first(where: \.isDark) { return .onlyDark(name: dark.name) }
        return .none
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
        let ok = ddc.write(.powerMode, value: mode.rawValue)
        if ok {
            if mode == .on { darkenedByDDC.remove(display.persistentKey) }
            else { darkenedByDDC.insert(display.persistentKey) }
        }
        return ok
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
        case refusedNoLitDisplay(darkName: String)
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
            case .refusedNoLitDisplay(let darkName):
                return DisconnectResult.refusedNoLitDisplay(darkName: darkName).message
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
        case .refusedNoLitDisplay(let name): return .refusedNoLitDisplay(darkName: name)
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
