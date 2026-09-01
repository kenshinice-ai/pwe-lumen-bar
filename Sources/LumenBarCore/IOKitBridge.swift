import CoreGraphics
import Foundation
import IOKit

/// Bridges a CoreGraphics display ID to the IOKit services that actually own it.
///
/// Two different services matter:
///   * the framebuffer service (`AppleCLCD2` on Apple Silicon, `IOFramebuffer`
///     on Intel) — this is what accepts the rotation probe;
///   * the AV service (`DCPAVServiceProxy`) — this is the I2C pipe to an
///     external monitor's DDC/CI controller.
public enum IOKitBridge {

    // MARK: - Framebuffer service

    private static let framebufferClasses = [
        "AppleCLCD2",              // Apple Silicon
        "IOMobileFramebufferShim", // Apple Silicon, older naming
        "IOFramebuffer",           // Intel
    ]

    /// Find the framebuffer service backing `displayID`.
    ///
    /// Three routes, best first: CoreGraphics can name the service outright,
    /// the deprecated port lookup still answers on some systems, and failing
    /// both we match by EDID identity (service enumeration order is not stable
    /// across reconnects, so identity is the only safe key).
    /// Caller owns the returned port and must `IOObjectRelease` it.
    public static func framebufferService(for displayID: CGDirectDisplayID) -> io_service_t? {
        if let serviceForDisplay = Dyn.symbol(
            "CGSServiceForDisplayNumber",
            as: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<io_service_t>) -> Int32).self) {
            var service: io_service_t = 0
            if serviceForDisplay(displayID, &service) == 0, service != 0 {
                IOObjectRetain(service)
                return service
            }
        }
        if let portForDisplay = Dyn.symbol(
            "CGDisplayIOServicePort",
            as: (@convention(c) (CGDirectDisplayID) -> io_service_t).self) {
            let service = portForDisplay(displayID)
            if service != 0 {
                IOObjectRetain(service)
                return service
            }
        }
        // CoreDisplay names the exact registry path, which beats guessing.
        if let path = CoreDisplayInfo.dictionary(for: displayID)?["IODisplayLocation"] as? String {
            let service = IORegistryEntryFromPath(kIOMainPortDefault, path)
            if service != 0 { return service }
        }
        return matchFramebufferByIdentity(for: displayID)
    }

    private static func matchFramebufferByIdentity(for displayID: CGDirectDisplayID) -> io_service_t? {
        let wantVendor = CGDisplayVendorNumber(displayID)
        let wantModel = CGDisplayModelNumber(displayID)
        var fallback: io_service_t?
        var candidateCount = 0

        for className in framebufferClasses {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                               IOServiceMatching(className),
                                               &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }

            while case let service = IOIteratorNext(iterator), service != 0 {
                guard let attributes = productAttributes(of: service) else {
                    IOObjectRelease(service)
                    continue
                }
                let vendor = (attributes["LegacyManufacturerID"] as? NSNumber)?.uint32Value
                // ProductID is a wide packed field; only the low 16 bits line up
                // with what CoreGraphics reports as the model number.
                let product = (attributes["ProductID"] as? NSNumber)
                    .map { UInt32($0.uint64Value & 0xFFFF) }

                if vendor == wantVendor, product == wantModel {
                    if let previous = fallback { IOObjectRelease(previous) }
                    return service
                }
                // Only usable as a fallback when it is the sole candidate; the
                // built-in panel's packed ProductID does not match what
                // CoreGraphics reports, so identity matching can miss.
                if fallback == nil { fallback = service } else { IOObjectRelease(service) }
                candidateCount += 1
            }
        }
        guard candidateCount <= 1 else {
            // Several framebuffers and no identity match: returning a guess
            // would aim the operation at somebody else's screen.
            if let fallback { IOObjectRelease(fallback) }
            Log.error("no framebuffer identity match for display \(displayID) among \(candidateCount) candidates")
            return nil
        }
        return fallback
    }

    public static func productAttributes(of service: io_service_t) -> [String: Any]? {
        guard let raw = IORegistryEntryCreateCFProperty(service,
                                                        "DisplayAttributes" as CFString,
                                                        kCFAllocatorDefault, 0) else { return nil }
        let attributes = raw.takeRetainedValue() as? [String: Any]
        return attributes?["ProductAttributes"] as? [String: Any]
    }

    // MARK: - AV service (DDC transport)

    /// External `DCPAVServiceProxy` ports, in IORegistry order.
    ///
    /// Apple exposes no property tying one of these to a `CGDirectDisplayID`,
    /// so callers pair them positionally against the external displays and let
    /// the user swap the pairing if a monitor ends up on the wrong channel.
    public static func externalAVServices() -> [io_service_t] {
        var result: [io_service_t] = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("DCPAVServiceProxy"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let location = IORegistryEntryCreateCFProperty(service, "Location" as CFString,
                                                           kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            if location == "External" {
                result.append(service)   // kept alive for the caller
            } else {
                IOObjectRelease(service)
            }
        }
        return result
    }

    // MARK: - Rotation probe

    /// `IOServiceRequestProbe` option word that asks a framebuffer to re-orient.
    /// Layout: `kIOFBSetTransform` in the low bits, the rotation selector in
    /// bits 16-19.
    private static let kIOFBSetTransform: UInt32 = 0x0000_0400

    private static func transformOption(for rotation: Rotation) -> UInt32 {
        let selector: UInt32
        switch rotation {
        case .zero: selector = 0
        case .ninety: selector = 1
        case .oneEighty: selector = 2
        case .twoSeventy: selector = 3
        }
        return kIOFBSetTransform | (selector << 16)
    }

    /// Send the transform request and hand back the raw kernel result, so
    /// callers can tell "the driver refuses to rotate" (`kIOReturnUnsupported`)
    /// apart from "there is no service to ask".
    public static func probeRotation(_ rotation: Rotation,
                                     displayID: CGDirectDisplayID) -> kern_return_t? {
        guard let probe = Dyn.symbol("IOServiceRequestProbe",
                                     as: (@convention(c) (io_service_t, UInt32) -> kern_return_t).self)
        else {
            Log.error("IOServiceRequestProbe unavailable on this system")
            return nil
        }
        guard let service = framebufferService(for: displayID) else {
            Log.error("no framebuffer service for display \(displayID)")
            return nil
        }
        defer { IOObjectRelease(service) }

        let result = probe(service, transformOption(for: rotation))
        Log.info(String(format: "rotation probe display=%u angle=%d kr=0x%08X",
                        displayID, rotation.rawValue, UInt32(bitPattern: result)))
        return result
    }

    public static func requestRotation(_ rotation: Rotation,
                                       displayID: CGDirectDisplayID) -> Bool {
        probeRotation(rotation, displayID: displayID) == KERN_SUCCESS
    }
}
