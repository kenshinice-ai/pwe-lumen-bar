import CoreGraphics
import Foundation

/// What Lumen is running on, and whether the paths it depends on are there.
///
/// Nothing in Lumen's own code needs an API newer than macOS 14 — the package
/// is compiled against that floor precisely so a newer one cannot creep in
/// unnoticed. Everything version-sensitive is *private*: the window server's
/// mode table, SkyLight's rotation call, DisplayServices' brightness, the
/// IOAVService I2C channel. Those are the things that can move between
/// releases, and they are all resolved at run time, so a rename degrades one
/// capability instead of failing to launch.
///
/// This type turns that into something checkable in one command
/// (`lumenctl compat`) rather than something to find out by accident on a
/// machine the developer does not own.
public enum Platform {

    /// The oldest macOS Lumen claims to support. Development and verification
    /// happen on 27; 26 shares the same private surface and the same Apple
    /// Silicon display stack, so it is supported, and `lumenctl compat`
    /// confirms it on the spot.
    public static let minimumMajor = 26

    public static var osVersion: OperatingSystemVersion {
        ProcessInfo.processInfo.operatingSystemVersion
    }

    public static var osVersionString: String {
        let v = osVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    public static var buildVersion: String {
        sysctlString("kern.osversion") ?? "?"
    }

    /// Apple Silicon only — DDC over `IOAVService` and the Apple Silicon
    /// display stack simply do not exist on Intel Macs.
    public static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 else { return false }
        return value == 1
    }

    public static var chipName: String {
        sysctlString("machdep.cpu.brand_string") ?? "?"
    }

    public static var isSupportedOS: Bool {
        osVersion.majorVersion >= minimumMajor
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: - Self-check

    public struct Check {
        public let name: String
        public let ok: Bool
        public let detail: String
    }

    /// Every private entry point Lumen depends on, and what breaks without it.
    /// Ordered by how much the app loses when one is missing.
    private static let symbols: [(symbol: String, feature: String)] = [
        ("CGSGetNumberOfDisplayModes", "HiDPI mode list"),
        ("CGSGetDisplayModeDescriptionOfLength", "HiDPI mode list"),
        ("CGSGetCurrentDisplayMode", "current mode"),
        ("CGSConfigureDisplayMode", "resolution switching"),
        ("CGSConfigureDisplayEnabled", "per-display sleep"),
        ("SLSSetDisplayRotation", "rotation"),
        ("DisplayServicesGetBrightness", "built-in / Apple display brightness"),
        ("DisplayServicesSetBrightness", "built-in / Apple display brightness"),
        ("DisplayServicesCanChangeBrightness", "brightness capability probe"),
        ("CoreDisplay_DisplayCreateInfoDictionary", "display identity"),
        ("IOAVServiceCreateWithService", "DDC/CI"),
        ("IOAVServiceWriteI2C", "DDC/CI"),
        ("IOAVServiceReadI2C", "DDC/CI"),
    ]

    public static func compatibilityReport() -> [Check] {
        // The symbols only become visible once their framework is mapped in.
        Dyn.load("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices")
        Dyn.load("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight")
        Dyn.load("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay")

        var checks: [Check] = [
            Check(name: "macOS",
                  ok: isSupportedOS,
                  detail: isSupportedOS
                      ? "\(osVersionString) (\(buildVersion))"
                      : "\(osVersionString) — below the supported floor of \(minimumMajor).0"),
            Check(name: "Apple Silicon",
                  ok: isAppleSilicon,
                  detail: isAppleSilicon ? chipName : "\(chipName) — Intel is not supported"),
        ]

        for entry in symbols {
            let present = Dyn.has(entry.symbol)
            checks.append(Check(name: entry.symbol,
                                ok: present,
                                detail: present ? entry.feature : "missing — \(entry.feature) unavailable"))
        }

        checks.append(modeTableCheck())
        return checks
    }

    /// The one check that cannot be answered by asking whether a symbol exists:
    /// the mode description is a C struct read at fixed offsets, so it has to be
    /// read back and validated. `CGSModeTable` refuses the table outright if the
    /// layout has moved, which is the safe failure — this reports it plainly.
    private static func modeTableCheck() -> Check {
        let main = CGMainDisplayID()
        switch CGSModeTable.layoutStatus(for: main) {
        case .ok(let count):
            return Check(name: "CGS mode table", ok: true,
                         detail: "212-byte layout confirmed; the window server lists \(count) "
                               + "modes for the main display")
        case .unexpectedLength(let found):
            return Check(name: "CGS mode table", ok: false,
                         detail: "struct length reads back as \(found), expected 212 — "
                               + "falling back to the public mode list (no forced HiDPI)")
        case .unavailable:
            return Check(name: "CGS mode table", ok: false,
                         detail: "the window server refused the private mode table")
        }
    }
}
