import CoreGraphics
import Foundation

/// Display rotation.
///
/// Rotation goes through SkyLight's `SLSSetDisplayRotation`. The IOKit
/// framebuffer transform that Intel Macs used answers `kIOReturnUnsupported`
/// on every display here, including ones that rotate perfectly well — Lumen
/// targets Apple Silicon, so only the SkyLight path is kept.
///
/// Worth knowing: the built-in panel *does* rotate, even though System Settings
/// offers no control for it. An earlier version of this file reported it as
/// unsupported; that was the wrong API talking, not the hardware.
public enum RotationEngine {

    private typealias SetDisplayRotation = @convention(c) (CGDirectDisplayID, Int32) -> Int32

    private static var supportCache: [String: Bool] = [:]
    private static let cacheLock = NSLock()

    private static func skyLightSetter() -> SetDisplayRotation? {
        Dyn.load("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight")
        return Dyn.symbol("SLSSetDisplayRotation", as: SetDisplayRotation.self)
    }

    public static func current(of displayID: CGDirectDisplayID) -> Rotation {
        Rotation.from(degrees: CGDisplayRotation(displayID))
    }

    /// Whether this display answers rotation requests.
    ///
    /// Probed by asking for the angle already in effect — a request the driver
    /// either accepts or rejects, with nothing visible either way.
    public static func isSupported(for display: DisplayInfo) -> Bool {
        cacheLock.lock()
        if let cached = supportCache[display.persistentKey] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let supported = skyLightSetter().map {
            $0(display.id, Int32(display.rotation.rawValue)) == 0
        } ?? false

        cacheLock.lock()
        supportCache[display.persistentKey] = supported
        cacheLock.unlock()
        Log.info("rotation support for \(display.name): \(supported)")
        return supported
    }

    public static func invalidateSupportCache() {
        cacheLock.lock(); supportCache.removeAll(); cacheLock.unlock()
    }

    /// Rotate and wait for the change to land.
    ///
    /// The call returns as soon as the request is accepted, which is not the
    /// same as the panel having turned, so the result is confirmed against
    /// `CGDisplayRotation` before it is reported as done.
    @discardableResult
    public static func rotate(_ display: DisplayInfo, to rotation: Rotation) -> Bool {
        let before = current(of: display.id)
        guard before != rotation else { return true }

        guard let setRotation = skyLightSetter() else { return false }
        let result = setRotation(display.id, Int32(rotation.rawValue))
        Log.info("SLSSetDisplayRotation(\(display.id), \(rotation.rawValue)) → \(result)")
        guard result == 0 else { return false }

        // The framebuffer reconfigures asynchronously; poll briefly.
        for _ in 0 ..< 30 {
            usleep(100_000)
            if current(of: display.id) == rotation { return true }
        }
        Log.error("rotation to \(rotation.rawValue)° did not take effect on \(display.name)")
        return false
    }
}
