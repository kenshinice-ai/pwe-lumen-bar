import CoreGraphics
import Foundation

/// Forcing HiDPI on a display that reports none.
///
/// macOS decides which scaled modes exist from the display's EDID. A monitor
/// that advertises no HiDPI timings gets none, however capable the panel is.
/// The documented-by-the-community escape is a display override plist naming
/// extra `scale-resolutions`, which the window server reads at boot.
///
/// Two honest caveats, both surfaced to the user before anything is written:
/// it needs administrator rights to install into `/Library/Displays`, and it
/// does nothing until the Mac restarts.
public enum HiDPIOverride {

    public struct Plan {
        public let displayName: String
        public let vendorID: UInt32
        public let productID: UInt32
        /// Logical sizes that will become available, each rendered at 2×.
        public let logicalSizes: [CGSize]
        public let plist: Data
        public let installPath: String
        public var directory: String { (installPath as NSString).deletingLastPathComponent }
    }

    /// Each entry is the *pixel* size to render, big-endian, followed by the
    /// two flag words the format expects.
    private static func entry(pixelWidth: Int, pixelHeight: Int) -> Data {
        var bytes = Data()
        for value in [UInt32(pixelWidth), UInt32(pixelHeight), 1, 0x0020_0000] {
            bytes.append(contentsOf: [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF),
                                      UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
        }
        return bytes
    }

    /// Sensible HiDPI steps for a panel of this size: half the native
    /// resolution is the natural "looks like" default, with a couple of
    /// neighbours either side.
    public static func suggestedSizes(nativePixels: CGSize) -> [CGSize] {
        let ratios: [Double] = [0.75, 0.6667, 0.5, 0.4167, 0.3333]
        return ratios.map { ratio in
            // Even numbers only — an odd framebuffer dimension is asking for trouble.
            CGSize(width: (nativePixels.width * ratio / 2).rounded() * 2,
                   height: (nativePixels.height * ratio / 2).rounded() * 2)
        }
    }

    public static func plan(for display: DisplayInfo,
                            sizes: [CGSize]? = nil) -> Plan? {
        let details = DetailsEngine.details(for: display)
        guard let native = details.nativePixelSize else { return nil }
        let logical = sizes ?? suggestedSizes(nativePixels: native)

        let entries = logical.map {
            entry(pixelWidth: Int($0.width) * 2, pixelHeight: Int($0.height) * 2)
        }
        let contents: [String: Any] = [
            "DisplayProductName": "\(display.name) (HiDPI)",
            "DisplayVendorID": Int(display.vendor),
            "DisplayProductID": Int(display.model),
            "scale-resolutions": entries,
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: contents,
                                                             format: .xml, options: 0)
        else { return nil }

        // The window server looks these up by hexadecimal identity.
        let path = "/Library/Displays/Contents/Resources/Overrides/"
            + String(format: "DisplayVendorID-%x/DisplayProductID-%x", display.vendor, display.model)

        return Plan(displayName: display.name,
                    vendorID: display.vendor,
                    productID: display.model,
                    logicalSizes: logical,
                    plist: data,
                    installPath: path)
    }

    /// Whether an override is already installed for this display.
    public static func isInstalled(for display: DisplayInfo) -> Bool {
        guard let plan = plan(for: display) else { return false }
        return FileManager.default.fileExists(atPath: plan.installPath)
    }

    public enum InstallResult {
        case installed
        case cancelled
        case failed(String)
    }

    /// Writes the plist through one authenticated shell call. The user sees the
    /// standard macOS admin prompt; PWE Lumen Bar never handles the password.
    public static func install(_ plan: Plan) -> InstallResult {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("pwelumenbar-override-\(UUID().uuidString).plist")
        do {
            try plan.plist.write(to: staging)
        } catch {
            return .failed(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: staging) }

        let command = "/bin/mkdir -p '\(plan.directory)' && /bin/cp '\(staging.path)' '\(plan.installPath)' && /usr/sbin/chown root:wheel '\(plan.installPath)'"
        return runAuthorized(command)
    }

    public static func remove(_ plan: Plan) -> InstallResult {
        runAuthorized("/bin/rm -f '\(plan.installPath)'")
    }

    private static func runAuthorized(_ shellCommand: String) -> InstallResult {
        let escaped = shellCommand.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failed(error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                                 as: UTF8.self)
            // -128 is the user dismissing the password prompt.
            if message.contains("-128") { return .cancelled }
            return .failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        Log.info("display override written")
        return .installed
    }
}
