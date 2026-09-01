import CoreGraphics
import Foundation

/// Where one display sits relative to another.
public enum ArrangementEdge: String, CaseIterable, Sendable, Identifiable {
    case left, right, above, below

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .left: return L10n.t("左边", "Left")
        case .right: return L10n.t("右边", "Right")
        case .above: return L10n.t("上面", "Above")
        case .below: return L10n.t("下面", "Below")
        }
    }

    public var symbol: String {
        switch self {
        case .left: return "rectangle.lefthalf.inset.filled"
        case .right: return "rectangle.righthalf.inset.filled"
        case .above: return "rectangle.tophalf.inset.filled"
        case .below: return "rectangle.bottomhalf.inset.filled"
        }
    }
}

/// Moving displays around the desktop.
///
/// Global display coordinates put the main display's top-left at (0, 0) with y
/// growing downward, so "above" means a smaller y — the opposite of the screen
/// coordinates AppKit uses, and an easy thing to get backwards.
public enum ArrangementEngine {

    /// Place `display` against one edge of `anchor`, centred on that edge.
    @discardableResult
    public static func place(_ display: DisplayInfo,
                             _ edge: ArrangementEdge,
                             relativeTo anchor: DisplayInfo) -> Bool {
        guard display.id != anchor.id else { return false }
        let target = display.bounds.size
        let base = anchor.bounds

        let origin: CGPoint
        switch edge {
        case .left:
            origin = CGPoint(x: base.minX - target.width,
                             y: base.midY - target.height / 2)
        case .right:
            origin = CGPoint(x: base.maxX,
                             y: base.midY - target.height / 2)
        case .above:
            origin = CGPoint(x: base.midX - target.width / 2,
                             y: base.minY - target.height)
        case .below:
            origin = CGPoint(x: base.midX - target.width / 2,
                             y: base.maxY)
        }
        return applyOrigins([display.id: origin])
    }

    /// Lay every display out in one row, left to right, tops aligned.
    @discardableResult
    public static func tileHorizontally(_ displays: [DisplayInfo]) -> Bool {
        // The main display must stay at the origin, so start the row there and
        // let the others follow it.
        let ordered = displays.sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            return lhs.bounds.minX < rhs.bounds.minX
        }
        var origins: [CGDirectDisplayID: CGPoint] = [:]
        var x: CGFloat = 0
        for display in ordered {
            origins[display.id] = CGPoint(x: x, y: 0)
            x += display.bounds.width
        }
        return applyOrigins(origins)
    }

    /// Commit a set of origins as one transaction, so the desktop never passes
    /// through a half-rearranged state.
    @discardableResult
    public static func applyOrigins(_ origins: [CGDirectDisplayID: CGPoint]) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        for (id, origin) in origins {
            let status = CGConfigureDisplayOrigin(config, id, Int32(origin.x), Int32(origin.y))
            guard status == .success else {
                CGCancelDisplayConfiguration(config)
                Log.error("CGConfigureDisplayOrigin failed for \(id): \(status.rawValue)")
                return false
            }
        }
        let completion = CGCompleteDisplayConfiguration(config, .permanently)
        Log.info("arrangement applied to \(origins.count) display(s) → \(completion.rawValue)")
        return completion == .success
    }
}
