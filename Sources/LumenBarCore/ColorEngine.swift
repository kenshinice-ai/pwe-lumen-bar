import ApplicationServices
import CoreGraphics
import Foundation

/// A ColorSync ICC profile that can be assigned to a display.
public struct ColorProfile: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let url: URL

    public init(id: String, name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url
    }
}

/// Per-display colour profile management, via ColorSync.
///
/// This is the same assignment System Settings makes under Displays → Colour
/// Profile, reachable without leaving the menu bar. All public API — no private
/// symbols involved.
public enum ColorEngine {

    /// ColorSync identifies displays by UUID, not by the display ID that gets
    /// reassigned on every reconnect.
    private static func deviceUUID(for displayID: CGDirectDisplayID) -> CFUUID? {
        CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
    }

    // MARK: - Listing

    private final class ProfileCollector {
        var profiles: [ColorProfile] = []
    }

    /// Every installed profile that a display can actually use.
    ///
    /// Filtered to the monitor class ('mntr'): assigning a printer or scanner
    /// profile to a screen is not a thing anyone wants offered to them.
    // ColorSync exposes its dictionary keys as `Unmanaged<CFString>`, so they
    // are unwrapped once here rather than at every use.
    private static let classKey = kColorSyncProfileClass.takeUnretainedValue()
    private static let urlKey = kColorSyncProfileURL.takeUnretainedValue()
    private static let descriptionKey = kColorSyncProfileDescription.takeUnretainedValue()
    private static let displayClassValue = kColorSyncSigDisplayClass.takeUnretainedValue() as String

    public static func installedDisplayProfiles() -> [ColorProfile] {
        let collector = ProfileCollector()
        var seed: UInt32 = 0

        ColorSyncIterateInstalledProfiles({ profileInfo, userInfo in
            guard let userInfo,
                  let info = profileInfo as? [CFString: Any] else { return true }
            let collector = Unmanaged<ProfileCollector>.fromOpaque(userInfo).takeUnretainedValue()

            // 'mntr' — assigning a printer profile to a screen helps no one.
            guard let profileClass = info[ColorEngine.classKey] as? String,
                  profileClass == ColorEngine.displayClassValue,
                  let url = info[ColorEngine.urlKey] as? URL else { return true }

            let name = (info[ColorEngine.descriptionKey] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            collector.profiles.append(ColorProfile(id: url.path, name: name, url: url))
            return true
        }, &seed, Unmanaged.passUnretained(collector).toOpaque(), nil)

        return collector.profiles.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The ICC file currently assigned to the display.
    ///
    /// A custom assignment wins over the factory one; both live in the
    /// ColorSync device record. Knowing the URL — not just a colour space name
    /// — is what makes an assignment reversible.
    public static func currentProfileURL(for displayID: CGDirectDisplayID) -> URL? {
        guard let uuid = deviceUUID(for: displayID),
              let info = ColorSyncDeviceCopyDeviceInfo(
                kColorSyncDisplayDeviceClass.takeUnretainedValue(), uuid)?
                .takeRetainedValue() as? [CFString: Any]
        else { return nil }

        // Bridge through String: casting Any straight to CFString is a downcast
        // Swift considers unconditional, which it will not compile.
        guard let defaultID = info[kColorSyncDeviceDefaultProfileID.takeUnretainedValue()] as? String
        else { return nil }
        let key = defaultID as CFString

        if let custom = info[kColorSyncCustomProfiles.takeUnretainedValue()] as? [CFString: Any],
           let url = custom[key] as? URL {
            return url
        }
        if let factory = info[kColorSyncFactoryProfiles.takeUnretainedValue()] as? [CFString: Any],
           let entry = factory[key] as? [CFString: Any],
           let url = entry[kColorSyncDeviceProfileURL.takeUnretainedValue()] as? URL {
            return url
        }
        return nil
    }

    /// A human-readable name for what is in effect, preferring the ICC file's
    /// own description over the colour space identifier.
    public static func currentProfileName(for displayID: CGDirectDisplayID) -> String? {
        if let url = currentProfileURL(for: displayID) {
            if let profile = ColorSyncProfileCreateWithURL(url as CFURL, nil)?.takeRetainedValue(),
               let description = ColorSyncProfileCopyDescriptionString(profile)?.takeRetainedValue() {
                return description as String
            }
            return url.deletingPathExtension().lastPathComponent
        }
        guard let name = CGDisplayCopyColorSpace(displayID).name else { return nil }
        return (name as String)
            .replacingOccurrences(of: "kCGColorSpace", with: "")
    }

    // MARK: - Assignment

    @discardableResult
    public static func apply(_ profile: ColorProfile, to displayID: CGDirectDisplayID) -> Bool {
        guard let uuid = deviceUUID(for: displayID) else { return false }
        let assignment: [CFString: Any] = [
            kColorSyncDeviceDefaultProfileID.takeUnretainedValue(): profile.url as CFURL,
        ]
        let ok = ColorSyncDeviceSetCustomProfiles(kColorSyncDisplayDeviceClass.takeUnretainedValue(),
                                                  uuid,
                                                  assignment as CFDictionary)
        Log.info("colour profile \(profile.name) → display \(displayID): \(ok)")
        return ok
    }

    /// Drop the custom assignment and fall back to the display's factory profile.
    @discardableResult
    public static func resetToFactory(displayID: CGDirectDisplayID) -> Bool {
        guard let uuid = deviceUUID(for: displayID) else { return false }
        let ok = ColorSyncDeviceSetCustomProfiles(kColorSyncDisplayDeviceClass.takeUnretainedValue(),
                                                  uuid,
                                                  nil)
        Log.info("colour profile reset to factory for display \(displayID): \(ok)")
        return ok
    }
}
