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
    /// Was "天域文创出品" / "A PARADISE PRODUCTION". Both halves are retired: the house is
    /// PWE · 天域, and 「文创」 drifted in Chinese towards merchandise and craft goods — too
    /// light for a company shipping SaaS and Mac tools (planning doc 17 §2.3).
    ///
    /// The standard's form is the pair `PWE · 天域出品`, and unlike the old one it is worth
    /// printing whole in both languages: "PWE" is the brand rather than English, and 天域出品 is
    /// four characters. Nobody is made to read half a line of a language they did not choose.
    ///
    /// It is drawn by `BrandSignature`, which sets the two scripts separately — see there.
    static let signature = "PWE · 天域出品"
    static let signatureLatin = "PWE"
    static let signatureHan = "天域出品"

    static let copyright = "© 2026 PWE Group Pty Ltd"

    /// Whatever the bundle actually says, never a second copy of the number.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

/// The product mark: the Paradise wing, with the sparkles that belong to this
/// product.
///
/// The wing geometry comes from `BrandMark`, which is imported from the
/// generator — so the wing here, the wing in the app icon and the wing on the
/// website are the same five feathers and cannot drift apart (brand standard
/// §2). The sparkles are placed off the leading feather's tip in the same
/// proportions the icon uses, so the mark in the interface and the mark on the
/// tile are one shape rather than two that resemble each other.
struct WingMark: View {
    /// The wing's own height. The view is larger, because the sparkles sit
    /// outside the wing's golden box.
    var height: CGFloat = 14
    /// nil follows `Brand.accent`; pass a colour for a fixed ground.
    var color: Color? = nil

    var body: some View {
        MarkShape(wingHeight: height)
            .fill(color ?? Brand.accent)
            .frame(width: height * BrandMark.aspect * MarkShape.widthSlack,
                   height: height * MarkShape.heightSlack)
            .accessibilityHidden(true)
    }
}

private struct MarkShape: Shape {
    let wingHeight: CGFloat

    /// Room for the sparkles, as a multiple of the wing's own box.
    static let widthSlack: CGFloat = 1.24
    static let heightSlack: CGFloat = 1.34

    func path(in rect: CGRect) -> Path {
        let markH = rect.height / Self.heightSlack
        let markW = markH * BrandMark.aspect
        // The wing sits bottom-left; its tip reaches the top-right, which is
        // where the sparkles go.
        let wing = CGRect(x: rect.minX, y: rect.maxY - markH, width: markW, height: markH)

        // `BrandMark` maps the generator's SVG coordinates into AppKit's, where
        // y grows upward — correct for the icon, which is drawn into a
        // CoreGraphics context. SwiftUI's `Path` grows y downward, so the same
        // geometry arrives mirrored: the wing sweeps down instead of up. Flip it
        // back here rather than in `BrandMark`, which has to keep matching the
        // shared file it was imported from.
        let flip = CGAffineTransform(scaleX: 1, y: -1)
            .concatenating(CGAffineTransform(translationX: 0, y: wing.minY + wing.maxY))
        var path = Path(BrandMark.path(in: wing).cgPath).applying(flip)

        let tip = CGPoint(x: wing.maxX, y: wing.minY)
        path.addPath(Self.sparkle(center: CGPoint(x: tip.x + markW * 0.058,
                                                  y: tip.y - markW * 0.047),
                                  radius: markW * 0.092))
        // The companion sparkle is detail, not structure — the same rule the
        // icon follows. Below this size it stops being a shape and becomes a
        // speck of amber next to the mark.
        if markH >= 20 {
            path.addPath(Self.sparkle(center: CGPoint(x: tip.x + markW * 0.190,
                                                      y: tip.y - markW * 0.163),
                                      radius: markW * 0.043))
        }
        return path
    }

    /// A four-pointed sparkle with concave sides — the same shape the resolution
    /// menu uses to mark a HiDPI mode, so the mark and the interface say "sharp"
    /// with one shape.
    static func sparkle(center c: CGPoint, radius r: CGFloat) -> Path {
        var path = Path()
        let waist = r * 0.16  // control points near the centre pull the sides in
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y),
                          control: CGPoint(x: c.x + waist, y: c.y - waist))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r),
                          control: CGPoint(x: c.x + waist, y: c.y + waist))
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y),
                          control: CGPoint(x: c.x - waist, y: c.y + waist))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r),
                          control: CGPoint(x: c.x - waist, y: c.y - waist))
        path.closeSubpath()
        return path
    }
}

/// The signature line as it appears at the foot of a window.
struct BrandSignature: View {
    var body: some View {
        HStack(spacing: 6) {
            WingMark(height: 11)
            // Two runs, because this one line is two scripts that want opposite things. Latin
            // small caps need the tracking; Han has no small caps, and spacing 天域出品 apart
            // reads as four separate words rather than as an opened line.
            HStack(spacing: 3) {
                Text(verbatim: Brand.signatureLatin).tracking(1.4)
                Text(verbatim: "·")
                Text(verbatim: Brand.signatureHan)
            }
            .font(.caption2.weight(.medium))
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
