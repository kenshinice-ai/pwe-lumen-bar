import AppKit
import CoreGraphics
import Foundation
import IOKit

/// Colour, dynamic range and signal facts about a display.
///
/// Split deliberately into two kinds of fact. *Current state* comes from
/// `NSScreen`, which is documented and verifiable. *Capabilities* come from the
/// `ColorElements` table in the IORegistry, which lists every combination the
/// link supports.
///
/// What is deliberately not reported: the exact meaning of the `Colorimetry`
/// and `PixelEncoding` enums beyond the values that are unambiguous. IOKit
/// exposes them as bare integers with no public documentation; labelling
/// `Colorimetry=16` as a named colour space would be a guess presented as a
/// fact, and the raw value is more useful than a confident invention.
public struct SignalInfo {
    // Current state, from NSScreen.
    public let colorSpaceName: String?
    /// 1.0 means standard range; above that is how much headroom HDR content has.
    public let edrHeadroom: Double
    public let edrPotential: Double
    public let referenceHeadroom: Double
    public let refreshRange: ClosedRange<Double>?

    // Capabilities, from the link's colour element table.
    public let maximumBitDepth: Int?
    public let supportsHDRSignal: Bool
    public let supportsDSC: Bool
    public let encodings: [Encoding]
    /// Raw (encoding, colorimetry, depth, dynamic range) rows, for the curious.
    public let rawElements: [String]

    public enum Encoding: Int, CaseIterable {
        case rgb = 0
        case ycbcr444 = 1
        case ycbcr422 = 2
        case ycbcr420 = 3

        public var label: String {
            switch self {
            case .rgb: return "RGB"
            case .ycbcr444: return "YCbCr 4:4:4"
            case .ycbcr422: return "YCbCr 4:2:2"
            case .ycbcr420: return "YCbCr 4:2:0"
            }
        }
    }

    public var isHDRCapable: Bool { edrPotential > 1.001 || supportsHDRSignal }
    public var isHDRActive: Bool { edrHeadroom > 1.001 }
    /// A reference headroom is what Apple's XDR panels report.
    public var isReferenceDisplay: Bool { referenceHeadroom > 1.001 }
    public var isVariableRefresh: Bool {
        guard let range = refreshRange else { return false }
        return range.upperBound - range.lowerBound > 1
    }

    /// Plain language for the state most people actually want to know.
    public var hdrDescription: String {
        if isHDRActive {
            return L10n.t("已开启，余量 \(String(format: "%.1f", edrHeadroom))×",
                          "active, \(String(format: "%.1f", edrHeadroom))× headroom")
        }
        if edrPotential > 1.001 {
            return L10n.t("可用，当前未开启（最高 \(String(format: "%.1f", edrPotential))×）",
                          "available, not in use (up to \(String(format: "%.1f", edrPotential))×)")
        }
        if supportsHDRSignal {
            return L10n.t("显示器链路支持 HDR 信号，但 macOS 没有给出 EDR 余量，实际用不上",
                          "the link can carry an HDR signal, but macOS grants no EDR headroom, so it is not usable")
        }
        return L10n.t("不支持", "not supported")
    }

    public var refreshLabel: String? {
        guard let range = refreshRange else { return nil }
        return isVariableRefresh
            ? String(format: "%.0f–%.0f Hz", range.lowerBound, range.upperBound)
            : String(format: "%.0f Hz", range.upperBound)
    }
}

public enum SignalEngine {

    public static func info(for display: DisplayInfo) -> SignalInfo {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == display.id
        }

        var refreshRange: ClosedRange<Double>?
        if let screen, screen.maximumRefreshInterval > 0, screen.minimumRefreshInterval > 0 {
            // Intervals are seconds per frame; the shorter one is the faster rate.
            let low = 1 / screen.maximumRefreshInterval
            let high = 1 / screen.minimumRefreshInterval
            refreshRange = min(low, high) ... max(low, high)
        }

        let elements = colorElements(for: display)
        // Virtual elements describe what the link could negotiate rather than
        // what this panel offers, so they are left out of the capability claims.
        let real = elements.filter { ($0["IsVirtual"] as? NSNumber)?.boolValue != true }

        let depths = real.compactMap { ($0["Depth"] as? NSNumber)?.intValue }
        let encodings = Set(real.compactMap { ($0["PixelEncoding"] as? NSNumber)?.intValue })
            .compactMap(SignalInfo.Encoding.init(rawValue:))
            .sorted { $0.rawValue < $1.rawValue }

        let rawRows = real.prefix(12).map { element -> String in
            let encoding = (element["PixelEncoding"] as? NSNumber)?.intValue ?? -1
            let depth = (element["Depth"] as? NSNumber)?.intValue ?? -1
            let colorimetry = (element["Colorimetry"] as? NSNumber)?.intValue ?? -1
            let range = (element["DynamicRange"] as? NSNumber)?.intValue ?? -1
            let eotf = (element["EOTF"] as? NSNumber)?.intValue ?? -1
            return "encoding \(encoding) · \(depth)-bit · colorimetry \(colorimetry) · range \(range) · eotf \(eotf)"
        }

        return SignalInfo(
            colorSpaceName: screen?.colorSpace?.localizedName
                ?? (CGDisplayCopyColorSpace(display.id).name as String?),
            edrHeadroom: Double(screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1),
            edrPotential: Double(screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1),
            referenceHeadroom: Double(screen?.maximumReferenceExtendedDynamicRangeColorComponentValue ?? 0),
            refreshRange: refreshRange,
            maximumBitDepth: depths.max(),
            supportsHDRSignal: real.contains { ($0["DynamicRange"] as? NSNumber)?.intValue == 1 },
            supportsDSC: real.contains { ($0["SupportsDSC"] as? NSNumber)?.boolValue == true },
            encodings: encodings,
            rawElements: Array(rawRows))
    }

    /// The colour element table belongs to the display's framebuffer service.
    private static func colorElements(for display: DisplayInfo) -> [[String: Any]] {
        guard let service = IOKitBridge.framebufferService(for: display.id) else { return [] }
        defer { IOObjectRelease(service) }
        guard let raw = IORegistryEntryCreateCFProperty(service, "ColorElements" as CFString,
                                                        kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]] else { return [] }
        return raw
    }
}
