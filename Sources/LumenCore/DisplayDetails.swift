import CoreGraphics
import Foundation
import IOKit

/// Everything Lumen can find out about one display, in one place.
///
/// Raw EDID is included when the display exposes it. Apple Silicon built-in
/// panels do not — there is no EDID block anywhere in their IORegistry tree,
/// because the panel is described by the SoC rather than by a monitor's ROM —
/// so the descriptive fields come from CoreDisplay instead.
public struct DisplayDetails {
    public let name: String
    public let displayID: CGDirectDisplayID
    public let persistentKey: String
    public let connection: ConnectionType
    public let vendorID: UInt32
    public let productID: UInt32
    public let serialNumber: UInt32
    public let manufactureWeek: Int?
    public let manufactureYear: Int?
    public let physicalSizeMM: CGSize?
    public let isDigital: Bool?
    public let whitePoint: CGPoint?
    public let currentMode: DisplayMode?
    /// The panel's own pixel grid, which is not the current framebuffer: a
    /// scaled HiDPI mode can render larger than the panel and downsample.
    public let nativePixelSize: CGSize?
    public let modeCount: Int
    public let hiDPIModeCount: Int
    public let brightnessChannel: BrightnessChannel
    public let volumeChannel: VolumeChannel
    public let hasDDC: Bool
    public let rotationSupported: Bool
    public let colorProfile: String?
    public let signal: SignalInfo
    public let rawEDID: Data?

    public var diagonalInches: Double? {
        guard let size = physicalSizeMM, size.width > 0, size.height > 0 else { return nil }
        return sqrt(size.width * size.width + size.height * size.height) / 25.4
    }

    /// Pixels per inch of the physical panel — computed from its native
    /// resolution, never from the current mode's framebuffer.
    public var pixelsPerInch: Double? {
        guard let diagonal = diagonalInches, let native = nativePixelSize else { return nil }
        let pixelDiagonal = sqrt(native.width * native.width + native.height * native.height)
        return pixelDiagonal / diagonal
    }

    public func plainText() -> String {
        var lines: [String] = []
        // Pad to a column count, not a character count: CJK glyphs occupy two
        // terminal columns, so padding "连接" and "持久标识" by character length
        // leaves the value column visibly ragged.
        let labelColumns = 20
        func displayWidth(_ text: String) -> Int {
            text.unicodeScalars.reduce(0) { width, scalar in
                switch scalar.value {
                case 0x1100 ... 0x115F, 0x2E80 ... 0xA4CF, 0xAC00 ... 0xD7A3,
                     0xF900 ... 0xFAFF, 0xFE30 ... 0xFE6F, 0xFF00 ... 0xFF60,
                     0xFFE0 ... 0xFFE6, 0x20000 ... 0x3FFFD:
                    return width + 2
                default:
                    return width + 1
                }
            }
        }
        func row(_ label: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            let padding = String(repeating: " ", count: max(1, labelColumns - displayWidth(label)))
            lines.append(label + padding + value)
        }
        lines.append(name)
        lines.append(String(repeating: "─", count: max(8, name.count)))
        row(L10n.t("连接", "Connection"), connection.diagnosticLabel)
        row(L10n.t("标识", "Identity"),
            "vendor 0x\(String(vendorID, radix: 16)) · product 0x\(String(productID, radix: 16)) · serial \(serialNumber)")
        row(L10n.t("持久标识", "Persistent key"), persistentKey)
        if let week = manufactureWeek, let year = manufactureYear, year > 0 {
            row(L10n.t("生产", "Manufactured"), L10n.t("\(year) 年第 \(week) 周", "week \(week) of \(year)"))
        }
        if let size = physicalSizeMM, size.width > 0 {
            row(L10n.t("面板尺寸", "Panel size"),
                String(format: "%.0f × %.0f mm", size.width, size.height)
                + (diagonalInches.map { String(format: "  (%.1f\")", $0) } ?? ""))
        }
        if let native = nativePixelSize {
            row(L10n.t("原生分辨率", "Native resolution"),
                String(format: "%.0f × %.0f", native.width, native.height))
        }
        if let ppi = pixelsPerInch { row("PPI", String(format: "%.0f", ppi)) }
        if let digital = isDigital {
            row(L10n.t("信号", "Signal"), digital ? L10n.t("数字", "Digital") : L10n.t("模拟", "Analogue"))
        }
        if let white = whitePoint {
            row(L10n.t("白点", "White point"), String(format: "x %.4f  y %.4f", white.x, white.y))
        }
        row(L10n.t("当前模式", "Current mode"), currentMode?.describe())
        row(L10n.t("模式数", "Modes"),
            L10n.t("\(modeCount) 个，HiDPI \(hiDPIModeCount) 个",
                   "\(modeCount) total, \(hiDPIModeCount) HiDPI"))
        row(L10n.t("亮度通道", "Brightness channel"), brightnessChannel.label)
        row(L10n.t("音量通道", "Volume channel"), volumeChannel.label)
        row("DDC", hasDDC ? L10n.t("可用", "available") : L10n.t("不可用", "unavailable"))
        row(L10n.t("旋转", "Rotation"),
            rotationSupported ? L10n.t("支持", "supported") : L10n.t("不支持", "unsupported"))
        row(L10n.t("颜色配置", "Colour profile"), colorProfile)
        row(L10n.t("色彩空间", "Colour space"), signal.colorSpaceName)
        row(L10n.t("刷新率", "Refresh rate"),
            signal.refreshLabel.map { $0 + (signal.isVariableRefresh ? L10n.t("（可变）", " (variable)") : "") })
        if let depth = signal.maximumBitDepth {
            row(L10n.t("最高位深", "Max bit depth"), L10n.t("\(depth) bit", "\(depth)-bit"))
        }
        if !signal.encodings.isEmpty {
            row(L10n.t("信号编码", "Signal encodings"),
                signal.encodings.map(\.label).joined(separator: ", "))
        }
        // Two different questions, and answering them as one produced
        // "supported, up to 1.0×" — which reads as a contradiction. The link
        // carrying an HDR signal and macOS granting EDR headroom are separate
        // facts, and only the second one decides whether HDR is usable.
        row("HDR", signal.hdrDescription)
        if signal.isReferenceDisplay {
            row("XDR", L10n.t("参考模式余量 \(String(format: "%.1f", signal.referenceHeadroom))×",
                              "reference headroom \(String(format: "%.1f", signal.referenceHeadroom))×"))
        }
        row("DSC", signal.supportsDSC ? L10n.t("支持", "supported") : L10n.t("不支持", "not supported"))
        if let edid = rawEDID, let decoded = EDIDSummary(block: edid) {
            row("EDID", L10n.t("\(edid.count) 字节 · 版本 \(decoded.version)（可导出）",
                               "\(edid.count) bytes · version \(decoded.version) (exportable)"))
            row(L10n.t("EDID 厂商", "EDID vendor"),
                "\(decoded.manufacturer)  0x\(String(format: "%04x", decoded.productCode))")
            if let name = decoded.modelName { row(L10n.t("EDID 型号", "EDID model"), name) }
        } else if rawEDID != nil {
            row("EDID", L10n.t("已读取但无法解析", "read but could not be parsed"))
        } else {
            row("EDID", L10n.t("该显示器未提供", "not exposed by this display"))
        }
        return lines.joined(separator: "\n")
    }
}

public enum DetailsEngine {

    /// Raw EDID, when the display has one to give.
    ///
    /// The I2C route is tried first: Apple Silicon publishes no EDID block in
    /// the IORegistry, so for a third-party monitor reading address 0x50 over
    /// the video link is the only thing that works.
    public static func rawEDID(for display: DisplayInfo) -> Data? {
        guard !display.isBuiltin else { return nil }
        if let block = DDCRegistry.shared.service(for: display)?.edid() { return block }
        for className in ["DCPAVServiceProxy", "AppleCLCD2", "IODisplayConnect"] {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                               IOServiceMatching(className),
                                               &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                for key in ["EDID", "IODisplayEDID", "EDID UUID", "DisplayEDID"] {
                    if let value = IORegistryEntryCreateCFProperty(service, key as CFString,
                                                                   kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? Data, value.count >= 128 {
                        return value
                    }
                }
            }
        }
        return nil
    }

    /// The panel's real pixel grid, taken from the modes the driver flags as
    /// native. Falling back to the largest framebuffer would be wrong: a 2x
    /// scaled mode can render above the panel's resolution and downsample.
    static func nativePixelSize(from modes: [DisplayMode]) -> CGSize? {
        let native = modes.filter(\.isNative)
        let pool = native.isEmpty ? modes : native
        guard let best = pool.max(by: { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight })
        else { return nil }
        return CGSize(width: best.pixelWidth, height: best.pixelHeight)
    }

    public static func details(for display: DisplayInfo) -> DisplayDetails {
        let info = CoreDisplayInfo.dictionary(for: display.id) ?? [:]
        func number(_ key: String) -> NSNumber? { info[key] as? NSNumber }

        let width = number("DisplayHorizontalImageSize")?.doubleValue ?? 0
        let height = number("DisplayVerticalImageSize")?.doubleValue ?? 0
        let modes = ModeEngine.allModes(for: display.id)

        return DisplayDetails(
            name: display.name,
            displayID: display.id,
            persistentKey: display.persistentKey,
            connection: display.connection,
            vendorID: display.vendor,
            productID: display.model,
            serialNumber: display.serial,
            manufactureWeek: number("DisplayWeekManufacture")?.intValue,
            manufactureYear: number("DisplayYearManufacture")?.intValue,
            physicalSizeMM: width > 0 ? CGSize(width: width, height: height) : nil,
            isDigital: number("IODisplayIsDigital")?.boolValue,
            whitePoint: number("DisplayWhitePointX").map {
                CGPoint(x: $0.doubleValue,
                        y: number("DisplayWhitePointY")?.doubleValue ?? 0)
            },
            currentMode: display.currentMode,
            nativePixelSize: Self.nativePixelSize(from: modes),
            modeCount: modes.count,
            hiDPIModeCount: modes.filter { $0.isHiDPI && $0.usableForDesktop }.count,
            brightnessChannel: BrightnessEngine.shared.channel(for: display),
            volumeChannel: AudioEngine.shared.channel(for: display),
            // Answering DDC, not merely having a service object.
            hasDDC: DDCRegistry.shared.isResponsive(display),
            rotationSupported: RotationEngine.isSupported(for: display),
            colorProfile: ColorEngine.currentProfileName(for: display.id),
            signal: SignalEngine.info(for: display),
            rawEDID: rawEDID(for: display)
        )
    }
}
