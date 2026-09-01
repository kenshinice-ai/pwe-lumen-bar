import AppKit
import LumenBarCore
import SwiftUI

/// Paradise Production's colours and marks, and the rule that keeps them legal.
///
/// Deliberately small. This app is a system utility, so its controls follow the
/// user's own accent colour — a slider that ignores the colour someone picked in
/// System Settings looks broken, not branded. The brand appears where the app
/// speaks as a product rather than as a control surface: the welcome window, the
/// panel header, the settings footer, the icon.
///
/// Brand standard §5 has one hard rule, and it is the reason `accent` is a
/// computed property rather than a constant: amber `#F5B335` is legal on navy and
/// illegal on paper, where it fails WCAG AA. Asking for `Brand.accent` returns
/// the variant that is correct for the appearance in force, so the rule holds at
/// every call site instead of depending on whoever writes the next one.
enum Brand {

    // MARK: Palette (brand standard §5 — not extensible)

    static let navy = Color(hex: 0x0E1729)
    static let amber = Color(hex: 0xF5B335)      // dark grounds only
    static let amberDeep = Color(hex: 0xA16207)  // the paper-ground equivalent
    static let paper = Color(hex: 0xF7F5F2)
    static let ink = Color(hex: 0x0C0A09)
    static let muted = Color(hex: 0x6B7280)
    static let line = Color(hex: 0xE3DFD8)

    /// The accent, resolved against the appearance it will be drawn on.
    static var accent: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(Brand.amber) : NSColor(Brand.amberDeep)
        })
    }

    // MARK: Attribution

    /// The signature line.
    ///
    /// The brand standard's own format is the bilingual pair
    /// "A PARADISE PRODUCTION · 天域文创出品". Inside a product that already runs
    /// entirely in one language, printing both halves means every reader reads
    /// half a line of a language they did not choose, so each interface carries
    /// its own half. The paired form stays in place on outward-facing material —
    /// the README, the disk image, the site — where the audience is both.
    static var signature: String {
        L10n.t("天域文创出品", "A PARADISE PRODUCTION")
    }

    static let copyright = "© 2026 PWE Group Pty Ltd"

    /// Whatever the bundle actually says, never a second copy of the number.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

/// The Paradise wing, as a SwiftUI shape.
///
/// The geometry comes from `BrandMark`, which is imported from the generator —
/// so the wing here, the wing in the app icon and the wing on the website are
/// the same five feathers, and cannot drift apart (brand standard §2).
struct WingMark: View {
    var height: CGFloat = 14
    /// nil follows `Brand.accent`; pass a colour for a fixed ground.
    var color: Color? = nil

    var body: some View {
        WingShape()
            .fill(color ?? Brand.accent)
            .frame(width: height * BrandMark.aspect, height: height)
            .accessibilityHidden(true)
    }
}

private struct WingShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(BrandMark.path(in: rect).cgPath)
    }
}

/// The signature line as it appears at the foot of a window.
struct BrandSignature: View {
    var body: some View {
        HStack(spacing: 6) {
            WingMark(height: 11)
            Text(Brand.signature)
                .font(.caption2.weight(.medium))
                .tracking(1.4)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Brand.signature)
    }
}

// MARK: - Plumbing

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

extension NSAppearance {
    /// True when the appearance in force is one of the dark ones — the only
    /// question `Brand.accent` needs answered, and the only one that keeps amber
    /// off a paper ground.
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
