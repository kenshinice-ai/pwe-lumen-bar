import CoreGraphics
import Foundation
import IOKit

/// DDC/CI VCP feature codes Lumen drives.
public enum VCP: UInt8 {
    case brightness = 0x10
    case contrast = 0x12
    case volume = 0x62
    case mute = 0x8D
    case powerMode = 0xD6
    case inputSource = 0x60
}

public struct VCPReading {
    public let current: UInt16
    public let maximum: UInt16
    public var percent: Double { maximum > 0 ? Double(current) / Double(maximum) : 0 }
}

/// DDC/CI over the Apple Silicon `IOAVService` I2C pipe.
///
/// Every monitor's controller sits at I2C address 0x37 (0x6E as an 8-bit
/// address) and speaks the DDC/CI packet format: source byte, length byte,
/// opcode, payload, XOR checksum.
public final class DDCService {
    private typealias CreateWithService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<AnyObject>?
    private typealias WriteI2C = @convention(c) (AnyObject, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    private typealias ReadI2C = @convention(c) (AnyObject, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32

    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51
    private static let destination: UInt8 = 0x6E
    private static let source: UInt8 = 0x51

    /// I2C is a shared bus with no arbitration here — one command at a time.
    private static let queue = DispatchQueue(label: "com.leeliu.lumen.ddc")

    /// Monitors drop requests that arrive while they are still answering the
    /// previous one. A diagnostic pass fires several reads back to back, which
    /// was enough to make a Philips 27B1U3900 return nothing for brightness —
    /// so every transaction waits for a minimum gap since the last.
    private static let minimumGap: TimeInterval = 0.03
    private static var lastTransaction = Date.distantPast

    private static func settle() {
        let elapsed = Date().timeIntervalSince(lastTransaction)
        if elapsed < minimumGap {
            usleep(useconds_t((minimumGap - elapsed) * 1_000_000))
        }
        lastTransaction = Date()
    }

    private let avService: AnyObject

    public static var isSupported: Bool {
        Dyn.has("IOAVServiceCreateWithService") && Dyn.has("IOAVServiceWriteI2C")
    }

    public init?(service: io_service_t) {
        guard let create = Dyn.symbol("IOAVServiceCreateWithService", as: CreateWithService.self),
              let created = create(kCFAllocatorDefault, service)?.takeRetainedValue()
        else { return nil }
        self.avService = created
    }

    // MARK: - Packet construction

    private static func checksum(_ bytes: [UInt8], seed: UInt8) -> UInt8 {
        bytes.reduce(seed) { $0 ^ $1 }
    }

    @discardableResult
    public func write(_ vcp: VCP, value: UInt16) -> Bool {
        guard let writeI2C = Dyn.symbol("IOAVServiceWriteI2C", as: WriteI2C.self) else { return false }
        // 0x84 = 0x80 | 4 payload bytes (opcode, vcp, value-hi, value-lo)
        var packet: [UInt8] = [0x84, 0x03, vcp.rawValue, UInt8(value >> 8), UInt8(value & 0xFF)]
        let seed = Self.destination ^ Self.source
        packet.append(Self.checksum(packet, seed: seed))

        return Self.queue.sync {
            Self.settle()
            var attempt = 0
            while attempt < 4 {
                let result = packet.withUnsafeMutableBytes { buffer in
                    writeI2C(avService, Self.chipAddress, Self.dataAddress,
                             buffer.baseAddress!, UInt32(buffer.count))
                }
                if result == KERN_SUCCESS { return true }
                attempt += 1
                usleep(20_000)
            }
            Log.error("DDC write \(vcp) = \(value) failed after 3 attempts")
            return false
        }
    }

    public func read(_ vcp: VCP) -> VCPReading? {
        guard let writeI2C = Dyn.symbol("IOAVServiceWriteI2C", as: WriteI2C.self),
              let readI2C = Dyn.symbol("IOAVServiceReadI2C", as: ReadI2C.self) else { return nil }

        return Self.queue.sync {
            Self.settle()
            for _ in 0 ..< 4 {
                // 0x82 = 0x80 | 2 payload bytes (opcode, vcp)
                var request: [UInt8] = [0x82, 0x01, vcp.rawValue]
                request.append(Self.checksum(request, seed: Self.destination ^ Self.source))

                let wrote = request.withUnsafeMutableBytes { buffer in
                    writeI2C(avService, Self.chipAddress, Self.dataAddress,
                             buffer.baseAddress!, UInt32(buffer.count))
                }
                guard wrote == KERN_SUCCESS else { usleep(30_000); continue }
                usleep(40_000)   // monitors need a beat before the reply is ready

                var reply = [UInt8](repeating: 0, count: 12)
                let got = reply.withUnsafeMutableBytes { buffer in
                    readI2C(avService, Self.chipAddress, Self.dataAddress,
                            buffer.baseAddress!, UInt32(buffer.count))
                }
                if got == KERN_SUCCESS, let reading = Self.parse(reply, expecting: vcp) {
                    return reading
                }
                usleep(30_000)
            }
            return nil
        }
    }

    /// Read the monitor's EDID block.
    ///
    /// EDID lives at I2C address 0x50, not at the 0x37 DDC/CI uses — which is
    /// why it is invisible to everything that only speaks VCP. Apple Silicon
    /// publishes no EDID in the IORegistry at all, so this is the only way to
    /// get the real block from a third-party monitor.
    public func edid() -> Data? {
        guard let readI2C = Dyn.symbol("IOAVServiceReadI2C", as: ReadI2C.self) else { return nil }
        return Self.queue.sync {
            Self.settle()
            var block = [UInt8](repeating: 0, count: 128)
            let result = block.withUnsafeMutableBytes { buffer in
                readI2C(avService, 0x50, 0x00, buffer.baseAddress!, 128)
            }
            guard result == KERN_SUCCESS else { return nil }
            // Every EDID starts with this fixed header.
            guard Array(block.prefix(8)) == [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
            else { return nil }
            return Data(block)
        }
    }

    /// Ask the monitor what it actually supports.
    ///
    /// DDC/CI's capabilities request (VCP 0xF3) returns a parenthesised string
    /// listing the VCP codes the monitor implements and, for enumerated
    /// features like input source, the exact values it accepts. Reading it
    /// beats guessing: input source codes above 0x12 are vendor-defined, so a
    /// hard-coded list is wrong for somebody.
    ///
    /// The string arrives in offset-addressed chunks. The I2C read buffer often
    /// still holds the *previous* reply, so each chunk's echoed offset is
    /// checked against the one requested — without that the assembled string
    /// silently loses or duplicates a run of characters.
    public func capabilities() -> String? {
        guard let writeI2C = Dyn.symbol("IOAVServiceWriteI2C", as: WriteI2C.self),
              let readI2C = Dyn.symbol("IOAVServiceReadI2C", as: ReadI2C.self) else { return nil }

        return Self.queue.sync {
            Self.settle()
            var assembled = ""
            var offset: UInt16 = 0

            outer: for _ in 0 ..< 96 {
                for _ in 0 ..< 4 {
                    // 0x83 = 0x80 | 3 payload bytes (opcode, offset-hi, offset-lo)
                    var request: [UInt8] = [0x83, 0xF3, UInt8(offset >> 8), UInt8(offset & 0xFF)]
                    request.append(Self.checksum(request, seed: Self.destination ^ Self.source))

                    let wrote = request.withUnsafeMutableBytes { buffer in
                        writeI2C(avService, Self.chipAddress, Self.dataAddress,
                                 buffer.baseAddress!, UInt32(buffer.count))
                    }
                    guard wrote == KERN_SUCCESS else { usleep(40_000); continue }
                    usleep(60_000)

                    var reply = [UInt8](repeating: 0, count: 64)
                    let got = reply.withUnsafeMutableBytes { buffer in
                        readI2C(avService, Self.chipAddress, Self.dataAddress,
                                buffer.baseAddress!, UInt32(buffer.count))
                    }
                    guard got == KERN_SUCCESS,
                          let chunk = Self.parseCapabilityChunk(reply, expecting: offset)
                    else { usleep(40_000); continue }

                    // An empty payload is how the monitor says "that is all".
                    if chunk.isEmpty { break outer }
                    assembled += String(decoding: chunk, as: UTF8.self)
                    offset += UInt16(chunk.count)
                    usleep(20_000)
                    continue outer
                }
                break   // four attempts at one offset is enough
            }
            return assembled.isEmpty ? nil : assembled
        }
    }

    /// Frame: `[dest] [0x80|len] 0xE3 offsetHi offsetLo payload…`
    private static func parseCapabilityChunk(_ buffer: [UInt8],
                                             expecting offset: UInt16) -> ArraySlice<UInt8>? {
        for index in 1 ..< max(1, buffer.count - 4) {
            guard buffer[index] == 0xE3, buffer[index - 1] & 0x80 != 0 else { continue }
            let payloadLength = Int(buffer[index - 1] & 0x7F) - 3
            guard payloadLength >= 0 else { continue }
            let replyOffset = UInt16(buffer[index + 1]) << 8 | UInt16(buffer[index + 2])
            // A stale buffer answers with the offset of the previous request.
            guard replyOffset == offset else { continue }
            let start = index + 3
            let end = min(start + payloadLength, buffer.count)
            guard start <= end else { continue }
            return buffer[start ..< end]
        }
        return nil
    }

    /// Locate the VCP reply inside the raw I2C read.
    ///
    /// Monitors disagree about whether the buffer starts at the source address
    /// byte, so anchor on the reply opcode (0x02) plus a success result code
    /// and the VCP we asked about, rather than a fixed offset.
    private static func parse(_ buffer: [UInt8], expecting vcp: VCP) -> VCPReading? {
        for index in 0 ..< max(0, buffer.count - 7) {
            guard buffer[index] == 0x02,          // VCP feature reply
                  buffer[index + 1] == 0x00,      // result: no error
                  buffer[index + 2] == vcp.rawValue else { continue }
            let maximum = UInt16(buffer[index + 4]) << 8 | UInt16(buffer[index + 5])
            let current = UInt16(buffer[index + 6]) << 8 | UInt16(buffer[index + 7])
            return VCPReading(current: current, maximum: maximum)
        }
        return nil
    }
}

/// Maps displays to DDC channels and remembers the pairing the user confirms.
public final class DDCRegistry {
    public static let shared = DDCRegistry()

    private var services: [CGDirectDisplayID: DDCService] = [:]
    private var probed: Set<CGDirectDisplayID> = []
    /// Manual channel overrides, keyed by persistent display key. Positional
    /// pairing is a guess; this is the user's correction to it.
    private var channelOverrides: [String: Int] = [:]
    private let lock = NSLock()

    private init() {
        if let saved = Defaults.shared.dictionary(forKey: "ddcChannelOverrides") as? [String: Int] {
            channelOverrides = saved
        }
    }

    public func setChannel(_ channel: Int, forKey key: String) {
        lock.lock()
        channelOverrides[key] = channel
        Defaults.shared.set(channelOverrides, forKey: "ddcChannelOverrides")
        lock.unlock()
        invalidate()
    }

    public func channel(forKey key: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return channelOverrides[key]
    }

    public func invalidate() {
        lock.lock()
        services.removeAll()
        probed.removeAll()
        responsive.removeAll()
        capabilityCache.removeAll()
        lock.unlock()
    }

    public func service(for display: DisplayInfo) -> DDCService? {
        // AirPlay and virtual displays have no wire to speak I2C on. Skipping
        // them here saves three failed retries per control, per refresh.
        guard display.connection.canCarryDDC, !display.isBuiltin, DDCService.isSupported
        else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let existing = services[display.id] { return existing }
        guard !probed.contains(display.id) else { return nil }
        probed.insert(display.id)

        let ports = IOKitBridge.externalAVServices()
        defer { ports.forEach { IOObjectRelease($0) } }
        guard !ports.isEmpty else { return nil }

        let externals = DisplayRegistry.shared.onlineDisplays().filter { !$0.isBuiltin }
        let positional = externals.firstIndex { $0.id == display.id } ?? 0
        let index = channelOverrides[display.persistentKey] ?? positional
        guard index < ports.count, let service = DDCService(service: ports[index]) else {
            Log.error("no DDC channel \(index) for \(display.name) (\(ports.count) available)")
            return nil
        }
        services[display.id] = service
        Log.info("DDC channel \(index) bound to \(display.name)")
        return service
    }

    private var responsive: [String: Bool] = [:]
    private var capabilityCache: [String: DDCCapabilities?] = [:]

    /// The monitor's own account of what it supports, read once and kept.
    /// Reading it costs several I2C round trips, so it is never on a hot path.
    public func capabilities(for display: DisplayInfo) -> DDCCapabilities? {
        lock.lock()
        if let cached = capabilityCache[display.persistentKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let parsed = service(for: display)?.capabilities().flatMap { DDCCapabilities(raw: $0) }
        lock.lock()
        capabilityCache[display.persistentKey] = parsed
        lock.unlock()
        if let parsed {
            Log.info("capabilities for \(display.name): \(parsed.supported.count) VCP codes, MCCS \(parsed.mccsVersion ?? "?")")
        }
        return parsed
    }

    /// Whether the display actually answers DDC/CI.
    ///
    /// Creating an `IOAVService` succeeds for any external display, including
    /// Apple ones that speak no DDC at all — so reporting availability from the
    /// service object alone claims controls that do not exist. This asks for a
    /// real VCP value once and remembers the answer.
    public func isResponsive(_ display: DisplayInfo) -> Bool {
        lock.lock()
        if let cached = responsive[display.persistentKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let answered = service(for: display)?.read(.brightness) != nil
        lock.lock()
        responsive[display.persistentKey] = answered
        lock.unlock()
        Log.info("DDC responsive for \(display.name): \(answered)")
        return answered
    }

    public func availableChannelCount() -> Int {
        let ports = IOKitBridge.externalAVServices()
        defer { ports.forEach { IOObjectRelease($0) } }
        return ports.count
    }
}
