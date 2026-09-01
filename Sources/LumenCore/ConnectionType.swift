import CoreGraphics
import Foundation

/// How a display is attached, because it decides which controls can exist.
///
/// A monitor on HDMI or DisplayPort has a DDC/CI channel. One arriving over
/// AirPlay or a DisplayLink-style virtual GPU has no wire to speak I2C on, so
/// asking is not just futile — each failed DDC read costs three retries and
/// most of a second per refresh.
public enum ConnectionType: Hashable, Sendable {
    case builtIn
    case airPlay
    /// DisplayLink adapters, dummy plugs, screen-sharing targets.
    case virtualDevice
    /// A physically wired external display. `transport` is the raw
    /// `kDisplayTransportType` value; only the built-in's value (0) has been
    /// confirmed on hardware, so the rest is reported rather than interpreted.
    case wired(transport: Int?)
    case unknown

    public var canCarryDDC: Bool {
        switch self {
        case .wired, .unknown: return true
        case .builtIn, .airPlay, .virtualDevice: return false
        }
    }

    public var label: String {
        switch self {
        case .builtIn: return L10n.t("内建", "Built-in")
        case .airPlay: return "AirPlay"
        case .virtualDevice: return L10n.t("虚拟", "Virtual")
        case .wired: return L10n.t("外接", "External")
        case .unknown: return L10n.t("未知", "Unknown")
        }
    }

    public var diagnosticLabel: String {
        switch self {
        case .wired(let transport):
            guard let transport else { return label }
            return "\(label) (transport \(transport))"
        default:
            return label
        }
    }

    /// Why a hardware control is missing, in terms the user can act on.
    public var ddcExplanation: String {
        switch self {
        case .builtIn:
            return L10n.t("内建屏没有 DDC 通道，亮度走系统接口。",
                          "The built-in panel has no DDC channel; brightness uses the system path.")
        case .airPlay:
            return L10n.t("AirPlay 屏幕没有物理线路，无法使用 DDC；只能软件调光。",
                          "An AirPlay display has no physical link for DDC — software dimming only.")
        case .virtualDevice:
            return L10n.t("虚拟显示器（DisplayLink、虚拟插头等）不提供 DDC；只能软件调光。",
                          "Virtual displays (DisplayLink adapters, dummy plugs) expose no DDC — software dimming only.")
        case .wired, .unknown:
            return L10n.t("显示器没有响应 DDC。有些扩展坞会拦截 DDC，可试着直连，或在显示器菜单里打开 DDC/CI。",
                          "The monitor did not answer DDC. Some docks block it — try a direct connection, or enable DDC/CI in the monitor's own menu.")
        }
    }
}

/// Reads CoreDisplay's per-display information dictionary.
///
/// One deliberate omission: the dictionary also carries
/// `kCGDisplaySupportsRotation`, which reports `true` for this Mac's built-in
/// panel even though the framebuffer answers `kIOReturnUnsupported` and macOS
/// itself offers no rotation control for it. It is an optimistic capability
/// claim, so rotation support is still decided by probing the driver.
public enum CoreDisplayInfo {
    private typealias CreateInfoDictionary = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?

    public static func dictionary(for displayID: CGDirectDisplayID) -> [String: Any]? {
        Dyn.load("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay")
        guard let create = Dyn.symbol("CoreDisplay_DisplayCreateInfoDictionary",
                                      as: CreateInfoDictionary.self),
              let dictionary = create(displayID)?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return dictionary
    }

    /// The display's own product name, as the panel reports it.
    ///
    /// `NSScreen` drops a display from its list the moment it is mirrored, at
    /// which point its `localizedName` is gone and the menu would fall back to
    /// "Display 2". CoreDisplay still knows what it is called.
    public static func productName(for displayID: CGDirectDisplayID) -> String? {
        guard let info = dictionary(for: displayID) else { return nil }
        guard let names = info["DisplayProductName"] as? [String: String] else {
            return info["DisplayProductName"] as? String
        }
        // The dictionary is keyed by locale; prefer the user's, then any English.
        let preferred = Locale.preferredLanguages.first?.replacingOccurrences(of: "-", with: "_") ?? "en_US"
        for key in [preferred, String(preferred.prefix(2)), "en_US", "en_GB"] {
            if let match = names.first(where: { $0.key.hasPrefix(key) })?.value { return match }
        }
        return names.values.first
    }

    public static func connectionType(for displayID: CGDirectDisplayID) -> ConnectionType {
        if CGDisplayIsBuiltin(displayID) == 1 { return .builtIn }
        guard let info = dictionary(for: displayID) else { return .unknown }

        if (info["kCGDisplayIsAirPlay"] as? NSNumber)?.boolValue == true { return .airPlay }
        if (info["kCGDisplayIsVirtualDevice"] as? NSNumber)?.boolValue == true { return .virtualDevice }

        let transport = (info["kDisplayTransportType"] as? NSNumber)?.intValue
        return .wired(transport: transport)
    }
}
