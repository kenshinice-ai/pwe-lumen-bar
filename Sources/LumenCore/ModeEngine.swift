import CoreGraphics
import Foundation

/// Resolution and HiDPI handling.
public enum ModeEngine {

    // MARK: - Enumeration

    /// Every mode the display offers, private table first.
    public static func allModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        let privateModes = CGSModeTable.modes(for: displayID).map { record in
            DisplayMode(
                id: "cgs:\(record.number)",
                cgsNumber: record.number,
                cgMode: nil,
                width: record.width,
                height: record.height,
                pixelWidth: record.pixelWidth,
                pixelHeight: record.pixelHeight,
                refreshRate: record.refreshRate,
                ioFlags: record.flags,
                dpi: record.dpi,
                // Bit 0 is "valid"; bit 7 is "never show in the UI".
                usableForDesktop: record.flags & 0x1 != 0 && record.flags & 0x80 == 0
            )
        }
        if !privateModes.isEmpty { return sorted(privateModes) }

        Log.info("private mode table empty for \(displayID) — using public API")
        return sorted(publicModes(for: displayID))
    }

    private static func publicModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        let raw = (CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode]) ?? []
        var modes = raw.map { mode(from: $0) }
        // The current mode is not always in that list — make sure it is here.
        if let current = CGDisplayCopyDisplayMode(displayID),
           !modes.contains(where: { $0.id == "cg:\(current.ioDisplayModeID)" }) {
            modes.append(mode(from: current))
        }
        return modes
    }

    private static func mode(from cgMode: CGDisplayMode) -> DisplayMode {
        DisplayMode(
            id: "cg:\(cgMode.ioDisplayModeID)",
            cgsNumber: nil,
            cgMode: cgMode,
            width: cgMode.width,
            height: cgMode.height,
            pixelWidth: cgMode.pixelWidth,
            pixelHeight: cgMode.pixelHeight,
            refreshRate: cgMode.refreshRate,
            ioFlags: cgMode.ioFlags,
            dpi: nil,
            usableForDesktop: cgMode.isUsableForDesktopGUI()
        )
    }

    private static func sorted(_ modes: [DisplayMode]) -> [DisplayMode] {
        modes.sorted {
            ($0.width, $0.pixelWidth, $0.refreshRate) > ($1.width, $1.pixelWidth, $1.refreshRate)
        }
    }

    // MARK: - Current

    public static func currentMode(for displayID: CGDirectDisplayID) -> DisplayMode? {
        if let number = CGSModeTable.currentModeNumber(for: displayID) {
            if let match = allModes(for: displayID).first(where: { $0.cgsNumber == number }) {
                return match
            }
        }
        guard let cgMode = CGDisplayCopyDisplayMode(displayID) else { return nil }
        return mode(from: cgMode)
    }

    // MARK: - Curated lists

    /// One entry per logical size, HiDPI preferred, highest refresh first —
    /// the list a person actually picks from.
    public static func recommendedModes(for displayID: CGDirectDisplayID,
                                        includeLowRes: Bool = false) -> [DisplayMode] {
        let candidates = allModes(for: displayID).filter {
            $0.usableForDesktop && !$0.isStretched && !$0.isInterlaced
        }
        var best: [String: DisplayMode] = [:]
        for mode in candidates {
            let key = "\(mode.width)x\(mode.height)"
            guard let existing = best[key] else { best[key] = mode; continue }
            let isBetter = mode.isHiDPI == existing.isHiDPI
                ? mode.refreshRate > existing.refreshRate
                : mode.isHiDPI
            if isBetter { best[key] = mode }
        }
        var list = Array(best.values)
        if !includeLowRes {
            list = list.filter { $0.isHiDPI || !hasHiDPICounterpart($0, in: candidates) }
        }
        return list.sorted { ($0.width, $0.height) > ($1.width, $1.height) }
    }

    private static func hasHiDPICounterpart(_ mode: DisplayMode, in pool: [DisplayMode]) -> Bool {
        pool.contains { $0.isHiDPI && $0.width == mode.width && $0.height == mode.height }
    }

    /// The short list, the way System Settings does it: a handful of scaled
    /// sizes centred on the display's default, not every size the panel accepts.
    ///
    /// Centring matters. An earlier version anchored on the smallest and
    /// largest entries and strided between them, which on a 27" 4K monitor
    /// spent a slot on a 81-dpi 960×540 novelty and pushed 2560×1440 — the size
    /// most owners of that monitor actually want — down into the full list of
    /// 121. People scale around the default, so the window is built around it.
    public static func curatedModes(for displayID: CGDirectDisplayID,
                                    limit: Int = 5) -> [DisplayMode] {
        let all = recommendedModes(for: displayID, includeLowRes: true)
        let hiDPI = all.filter(\.isHiDPI)
        var pool = hiDPI.isEmpty ? all : hiDPI

        // Only sizes shaped like the panel. A 16:9 monitor will happily accept
        // 1600×1200, but offering it means offering letterboxing — System
        // Settings does not, and neither should this.
        if let native = nativeAspectRatio(from: allModes(for: displayID)) {
            let matching = pool.filter {
                $0.height > 0 && abs(Double($0.width) / Double($0.height) - native) / native < 0.02
            }
            if matching.count >= 3 { pool = matching }
        }
        guard pool.count > limit else { return pool.sorted { $0.width > $1.width } }

        let sorted = pool.sorted { $0.width < $1.width }
        // Anchor on the display's own default, falling back to what is in use.
        let currentID = currentMode(for: displayID)?.id
        let base = sorted.first(where: \.isDefault)
            ?? sorted.first { $0.id == currentID }
            ?? sorted[sorted.count / 2]

        // Steps *relative to the default*, snapped to whatever the display
        // actually offers. Picking neighbours instead produces a list of
        // near-identical sizes on a monitor with fine-grained modes; picking
        // multiples produces the familiar 1280 / 1600 / 1920 / 2560 / 3008
        // ladder that System Settings shows for a 4K panel.
        let steps: [Double] = [0.667, 0.833, 1.0, 1.333, 1.6]
        var chosen: [DisplayMode] = []
        for step in steps {
            let target = Double(base.width) * step
            let candidate = sorted
                .filter { mode in !chosen.contains { $0.id == mode.id } }
                .min { abs(Double($0.width) - target) < abs(Double($1.width) - target) }
            if let candidate { chosen.append(candidate) }
        }
        // Anything the snapping collapsed away is topped up from the wide end,
        // which is where the interesting sizes are.
        for mode in sorted.reversed() where chosen.count < limit {
            if !chosen.contains(where: { $0.id == mode.id }) { chosen.append(mode) }
        }
        return chosen.prefix(limit).sorted { $0.width > $1.width }
    }

    /// The panel's own shape, taken from the modes the driver flags as native.
    private static func nativeAspectRatio(from modes: [DisplayMode]) -> Double? {
        let native = modes.filter(\.isNative)
        let pool = native.isEmpty ? modes : native
        guard let best = pool.max(by: { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }),
              best.pixelHeight > 0 else { return nil }
        return Double(best.pixelWidth) / Double(best.pixelHeight)
    }

    public static func refreshRates(for displayID: CGDirectDisplayID,
                                    matching mode: DisplayMode) -> [DisplayMode] {
        let rates = allModes(for: displayID)
            .filter { $0.usableForDesktop
                && $0.width == mode.width && $0.height == mode.height
                && $0.isHiDPI == mode.isHiDPI }
            .sorted { $0.refreshRate > $1.refreshRate }

        // Drop the low-rate twins most panels advertise. A 30 Hz desktop is
        // unusable, and listing it beside 60 Hz invites picking it by mistake.
        guard let best = rates.first?.refreshRate, best >= 50 else { return rates }
        let usable = rates.filter { $0.refreshRate >= 50 || $0.id == mode.id }
        return usable.count > 1 ? usable : []
    }

    public static func hiDPIModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        allModes(for: displayID).filter { $0.isHiDPI && $0.usableForDesktop }
    }

    // MARK: - Apply

    @discardableResult
    public static func apply(_ mode: DisplayMode, to displayID: CGDirectDisplayID) -> Bool {
        if let number = mode.cgsNumber {
            return CGSModeTable.apply(modeNumber: number, to: displayID)
        }
        guard let cgMode = mode.cgMode else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        let status = CGConfigureDisplayWithDisplayMode(config, displayID, cgMode, nil)
        guard status == .success else {
            CGCancelDisplayConfiguration(config)
            Log.error("CGConfigureDisplayWithDisplayMode failed: \(status.rawValue)")
            return false
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
}
