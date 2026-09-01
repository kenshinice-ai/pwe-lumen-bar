import CoreGraphics
import Foundation

/// The display mode table CoreGraphics keeps to itself.
///
/// `CGDisplayCopyAllDisplayModes` omits most HiDPI modes — on an Apple Silicon
/// laptop it does not even return the mode the display is *currently* using.
/// The window server's own table has all of them, reachable through
/// `CGSGetDisplayModeDescriptionOfLength`.
///
/// The description is a fixed-size C struct whose field offsets were confirmed
/// against macOS 27. Field 46 holds the struct's own length, which gives a
/// cheap integrity check: if it stops reading back as 212, the layout has moved
/// and every caller falls back to the public API rather than trusting garbage.
public enum CGSModeTable {

    private typealias GetNumberOfModes = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Int32
    private typealias GetModeDescription = @convention(c) (CGDirectDisplayID, Int32, UnsafeMutableRawPointer, Int32) -> Int32
    private typealias GetCurrentMode = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Int32
    private typealias ConfigureMode = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Int32) -> CGError

    private static let structLength: Int32 = 212

    private enum Offset {
        static let modeNumber = 0
        static let flags = 4
        static let width = 8
        static let height = 12
        static let depth = 16
        static let refreshRate = 36
        static let dpi = 40
        static let selfLength = 184   // must read back as `structLength`
        static let pixelWidth = 200
        static let pixelHeight = 204
        static let scale = 208
    }

    public struct Record {
        public let number: Int32
        public let flags: UInt32
        public let width: Int
        public let height: Int
        public let pixelWidth: Int
        public let pixelHeight: Int
        public let refreshRate: Double
        public let dpi: Int
        public let scale: Float
    }

    public static var isAvailable: Bool {
        Dyn.has("CGSGetNumberOfDisplayModes") && Dyn.has("CGSGetDisplayModeDescriptionOfLength")
    }

    public static func modes(for displayID: CGDirectDisplayID) -> [Record] {
        guard let getCount = Dyn.symbol("CGSGetNumberOfDisplayModes", as: GetNumberOfModes.self),
              let getDescription = Dyn.symbol("CGSGetDisplayModeDescriptionOfLength", as: GetModeDescription.self)
        else { return [] }

        var count: Int32 = 0
        guard getCount(displayID, &count) == 0, count > 0 else { return [] }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(structLength), alignment: 8)
        defer { buffer.deallocate() }

        var records: [Record] = []
        for index in 0 ..< count {
            memset(buffer, 0, Int(structLength))
            guard getDescription(displayID, index, buffer, structLength) == 0 else { continue }
            let selfLength = buffer.load(fromByteOffset: Offset.selfLength, as: UInt32.self)
            guard selfLength == UInt32(structLength) else {
                Log.error("CGS mode struct layout changed: self-length reads back as "
                          + "\(selfLength), expected \(structLength) — abandoning the private "
                          + "mode table and falling back to the public list")
                return []
            }
            records.append(Record(
                number: buffer.load(fromByteOffset: Offset.modeNumber, as: Int32.self),
                flags: buffer.load(fromByteOffset: Offset.flags, as: UInt32.self),
                width: Int(buffer.load(fromByteOffset: Offset.width, as: UInt32.self)),
                height: Int(buffer.load(fromByteOffset: Offset.height, as: UInt32.self)),
                pixelWidth: Int(buffer.load(fromByteOffset: Offset.pixelWidth, as: UInt32.self)),
                pixelHeight: Int(buffer.load(fromByteOffset: Offset.pixelHeight, as: UInt32.self)),
                refreshRate: Double(buffer.load(fromByteOffset: Offset.refreshRate, as: UInt32.self)),
                dpi: Int(buffer.load(fromByteOffset: Offset.dpi, as: UInt32.self)),
                scale: buffer.load(fromByteOffset: Offset.scale, as: Float.self)
            ))
        }
        return records
    }

    /// Whether the private table can be trusted on the running system.
    ///
    /// The struct carries its own length at offset 184, which makes the layout
    /// self-verifying: no version test needed, and no guessing on a macOS
    /// release this code has never run on.
    public enum LayoutStatus {
        case ok(modeCount: Int)
        case unexpectedLength(UInt32)
        case unavailable
    }

    public static func layoutStatus(for displayID: CGDirectDisplayID) -> LayoutStatus {
        guard let getCount = Dyn.symbol("CGSGetNumberOfDisplayModes", as: GetNumberOfModes.self),
              let getDescription = Dyn.symbol("CGSGetDisplayModeDescriptionOfLength", as: GetModeDescription.self)
        else { return .unavailable }

        var count: Int32 = 0
        guard getCount(displayID, &count) == 0, count > 0 else { return .unavailable }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(structLength), alignment: 8)
        defer { buffer.deallocate() }
        memset(buffer, 0, Int(structLength))
        guard getDescription(displayID, 0, buffer, structLength) == 0 else { return .unavailable }

        let selfLength = buffer.load(fromByteOffset: Offset.selfLength, as: UInt32.self)
        return selfLength == UInt32(structLength)
            ? .ok(modeCount: Int(count))
            : .unexpectedLength(selfLength)
    }

    public static func currentModeNumber(for displayID: CGDirectDisplayID) -> Int32? {
        guard let getCurrent = Dyn.symbol("CGSGetCurrentDisplayMode", as: GetCurrentMode.self) else { return nil }
        var number: Int32 = -1
        guard getCurrent(displayID, &number) == 0, number >= 0 else { return nil }
        return number
    }

    @discardableResult
    public static func apply(modeNumber: Int32, to displayID: CGDirectDisplayID) -> Bool {
        guard let configureMode = Dyn.symbol("CGSConfigureDisplayMode", as: ConfigureMode.self) else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        let status = configureMode(config, displayID, modeNumber)
        guard status == .success else {
            CGCancelDisplayConfiguration(config)
            Log.error("CGSConfigureDisplayMode(\(modeNumber)) failed: \(status.rawValue)")
            return false
        }
        let completion = CGCompleteDisplayConfiguration(config, .permanently)
        Log.info("CGS mode \(modeNumber) applied to \(displayID) → \(completion.rawValue)")
        return completion == .success
    }
}
