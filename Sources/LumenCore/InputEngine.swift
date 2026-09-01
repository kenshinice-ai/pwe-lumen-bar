import CoreGraphics
import Foundation

/// Switching a monitor's input source over DDC (VCP 0x60).
///
/// This is the control that lets one monitor serve a Mac and something else
/// without reaching behind the desk for the OSD joystick.
public enum InputSource: UInt16, CaseIterable, Sendable, Identifiable {
    case vga1 = 0x01
    case dvi1 = 0x03
    case dvi2 = 0x04
    case displayPort1 = 0x0F
    case displayPort2 = 0x10
    case hdmi1 = 0x11
    case hdmi2 = 0x12
    case usbC = 0x1B

    public var id: UInt16 { rawValue }

    public var label: String {
        switch self {
        case .vga1: return "VGA"
        case .dvi1: return "DVI 1"
        case .dvi2: return "DVI 2"
        case .displayPort1: return "DisplayPort 1"
        case .displayPort2: return "DisplayPort 2"
        case .hdmi1: return "HDMI 1"
        case .hdmi2: return "HDMI 2"
        case .usbC: return "USB-C"
        }
    }
}

public enum InputEngine {

    /// A readable name for any input code, including the vendor-defined ones
    /// above 0x12 that no standard list covers.
    public static func label(forRawValue raw: UInt16) -> String {
        InputSource(rawValue: raw)?.label ?? String(format: "%@ 0x%02X", L10n.t("输入", "Input"), raw)
    }

    @discardableResult
    public static func select(rawValue: UInt16, for display: DisplayInfo) -> Bool {
        guard let ddc = DDCRegistry.shared.service(for: display) else { return false }
        Log.info("switching \(display.name) to input 0x\(String(rawValue, radix: 16))")
        return ddc.write(.inputSource, value: rawValue)
    }


    /// The input the monitor reports it is showing, if it answers at all.
    ///
    /// Vendors disagree about these codes below the common set, so an
    /// unrecognised value is returned raw rather than guessed at.
    public static func currentRawValue(for display: DisplayInfo) -> UInt16? {
        DDCRegistry.shared.service(for: display)?.read(.inputSource)?.current
    }

    public static func current(for display: DisplayInfo) -> InputSource? {
        guard let raw = currentRawValue(for: display) else { return nil }
        return InputSource(rawValue: raw)
    }

    @discardableResult
    public static func select(_ source: InputSource, for display: DisplayInfo) -> Bool {
        guard let ddc = DDCRegistry.shared.service(for: display) else { return false }
        Log.info("switching \(display.name) to input \(source.label)")
        return ddc.write(.inputSource, value: source.rawValue)
    }
}
