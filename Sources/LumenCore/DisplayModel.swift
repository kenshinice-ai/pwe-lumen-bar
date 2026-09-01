import CoreGraphics
import Foundation

/// A resolution/refresh-rate combination offered by a display.
///
/// Modes come from two sources — the window server's private table (complete,
/// and the only place most HiDPI modes appear) and the public CoreGraphics list
/// (incomplete, but guaranteed to keep working). `id` is unique across both.
public struct DisplayMode: Identifiable, Hashable {
    public let id: String
    /// Set when the mode came from the private table; how it gets applied.
    public let cgsNumber: Int32?
    /// Set when the mode came from the public API; the fallback apply path.
    public let cgMode: CGDisplayMode?

    /// Logical size — the "looks like" resolution the desktop is laid out in.
    public let width: Int
    public let height: Int
    /// Physical size — the framebuffer actually rendered.
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double
    public let ioFlags: UInt32
    public let dpi: Int?
    public let usableForDesktop: Bool

    public init(id: String, cgsNumber: Int32?, cgMode: CGDisplayMode?,
                width: Int, height: Int, pixelWidth: Int, pixelHeight: Int,
                refreshRate: Double, ioFlags: UInt32, dpi: Int?, usableForDesktop: Bool) {
        self.id = id; self.cgsNumber = cgsNumber; self.cgMode = cgMode
        self.width = width; self.height = height
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate; self.ioFlags = ioFlags
        self.dpi = dpi; self.usableForDesktop = usableForDesktop
    }

    /// A mode is HiDPI when the framebuffer is rendered denser than the layout.
    /// This is exactly the property macOS calls "Retina" and the reason text
    /// stays sharp at a scaled resolution.
    public var isHiDPI: Bool { pixelWidth > width }
    public var scaleFactor: Int { width > 0 ? max(1, pixelWidth / width) : 1 }
    public var isNative: Bool { ioFlags & 0x0200_0000 != 0 }
    /// The size the display reports as its own default.
    public var isDefault: Bool { ioFlags & 0x0000_0004 != 0 }
    public var isSafe: Bool { ioFlags & 0x0000_0002 != 0 }
    public var isStretched: Bool { ioFlags & 0x0000_0800 != 0 }
    public var isInterlaced: Bool { ioFlags & 0x0000_0040 != 0 }

    public var pointsLabel: String { "\(width) × \(height)" }
    public var pixelsLabel: String { "\(pixelWidth) × \(pixelHeight)" }
    public var refreshLabel: String {
        refreshRate > 0 ? String(format: "%.0f Hz", refreshRate) : "—"
    }

    public func describe() -> String {
        var parts = [pointsLabel]
        parts.append(isHiDPI ? "HiDPI \(scaleFactor)x → \(pixelsLabel)" : "1x")
        if refreshRate > 0 { parts.append(refreshLabel) }
        if let dpi { parts.append("\(dpi) dpi") }
        if isNative { parts.append(L10n.t("原生", "Native")) }
        if isStretched { parts.append(L10n.t("拉伸", "Stretched")) }
        return parts.joined(separator: "  ")
    }

    public static func == (lhs: DisplayMode, rhs: DisplayMode) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public enum Rotation: Int, CaseIterable, Identifiable, Sendable {
    case zero = 0, ninety = 90, oneEighty = 180, twoSeventy = 270
    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .zero: return L10n.t("标准", "Standard")
        case .ninety: return "90°"
        case .oneEighty: return "180°"
        case .twoSeventy: return "270°"
        }
    }
    public var symbol: String {
        switch self {
        case .zero: return "rectangle"
        case .ninety: return "rectangle.portrait.rotate"
        case .oneEighty: return "rectangle.rotate"
        case .twoSeventy: return "rectangle.portrait.rotate"
        }
    }
    public static func from(degrees: Double) -> Rotation {
        Rotation(rawValue: Int(degrees.rounded()) % 360) ?? .zero
    }
}

/// Where a display's brightness value actually comes from, so the UI can be
/// honest about what it is driving instead of showing a slider that does nothing.
///
/// Raw values are stable identifiers for logs and diagnostics; `label` and
/// `explanation` are the user-facing copy.
public enum BrightnessChannel: String, Sendable {
    case displayServices
    case ddc
    case gamma
    case none

    public var label: String {
        switch self {
        case .displayServices: return L10n.t("系统", "System")
        case .ddc: return "DDC"
        case .gamma: return L10n.t("软件", "Software")
        case .none: return L10n.t("不可用", "Unavailable")
        }
    }

    public var explanation: String {
        switch self {
        case .displayServices:
            return L10n.t("走系统亮度接口，和键盘亮度键同一条路径。",
                          "Uses the system brightness path — the same one the keyboard keys drive.")
        case .ddc:
            return L10n.t("通过 DDC/CI 直接调节显示器背光。",
                          "Drives the monitor's own backlight over DDC/CI.")
        case .gamma:
            return L10n.t("显示器不接受硬件调节，改用软件色彩曲线变暗；背光本身没有变化。",
                          "The monitor accepts no hardware control, so this dims the colour curve in software — the backlight itself does not change.")
        case .none:
            return L10n.t("这块屏没有可用的亮度通道。",
                          "No brightness channel is available for this display.")
        }
    }
}

public enum VolumeChannel: String, Sendable {
    case coreAudio
    case ddc
    case none

    public var label: String {
        switch self {
        case .coreAudio: return L10n.t("音频设备", "Audio device")
        case .ddc: return "DDC"
        case .none: return L10n.t("不可用", "Unavailable")
        }
    }

    public var explanation: String {
        switch self {
        case .coreAudio:
            return L10n.t("控制这块屏对应的系统音频输出设备。",
                          "Controls the system audio output device this display carries.")
        case .ddc:
            return L10n.t("通过 DDC/CI 调节显示器内置扬声器。",
                          "Drives the monitor's built-in speakers over DDC/CI.")
        case .none:
            return L10n.t("这块屏没有可控的音频输出。",
                          "This display carries no controllable audio output.")
        }
    }
}

public struct DisplayInfo: Identifiable, Hashable {
    public let id: CGDirectDisplayID
    public let name: String
    public let isBuiltin: Bool
    public let isMain: Bool
    public let vendor: UInt32
    public let model: UInt32
    public let serial: UInt32
    public let unitNumber: UInt32
    public let bounds: CGRect
    public let rotation: Rotation
    public let backingScale: CGFloat
    public let currentMode: DisplayMode?
    public let mirrorSource: CGDirectDisplayID
    public let connection: ConnectionType

    public init(id: CGDirectDisplayID, name: String, isBuiltin: Bool, isMain: Bool,
                vendor: UInt32, model: UInt32, serial: UInt32, unitNumber: UInt32,
                bounds: CGRect, rotation: Rotation, backingScale: CGFloat,
                currentMode: DisplayMode?, mirrorSource: CGDirectDisplayID,
                connection: ConnectionType = .unknown) {
        self.id = id; self.name = name; self.isBuiltin = isBuiltin; self.isMain = isMain
        self.vendor = vendor; self.model = model; self.serial = serial
        self.unitNumber = unitNumber; self.bounds = bounds; self.rotation = rotation
        self.backingScale = backingScale; self.currentMode = currentMode
        self.mirrorSource = mirrorSource
        self.connection = connection
    }

    public var isMirrored: Bool { mirrorSource != 0 }

    /// Survives reconnects and reboots — display IDs do not.
    public var persistentKey: String {
        isBuiltin ? "builtin" : "\(vendor)-\(model)-\(serial)"
    }

    public var resolutionSummary: String {
        guard let mode = currentMode else {
            return "\(Int(bounds.width)) × \(Int(bounds.height))"
        }
        return mode.isHiDPI
            ? "\(mode.pointsLabel) HiDPI · \(mode.refreshLabel)"
            : "\(mode.pointsLabel) · \(mode.refreshLabel)"
    }
}
