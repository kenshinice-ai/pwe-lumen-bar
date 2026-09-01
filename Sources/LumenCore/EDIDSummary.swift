import Foundation

/// The handful of EDID fields worth showing a person.
///
/// Bytes 8–17 are fixed-position identity fields; the model name lives in one
/// of the four 18-byte descriptors at offset 54, tagged 0xFC.
public struct EDIDSummary {
    public let manufacturer: String
    public let productCode: UInt16
    public let serial: UInt32
    public let week: Int
    public let year: Int
    public let version: String
    public let modelName: String?

    public init?(block: Data) {
        guard block.count >= 128 else { return nil }
        let bytes = [UInt8](block)
        guard Array(bytes.prefix(8)) == [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        else { return nil }

        // Three five-bit letters packed big-endian into bytes 8–9.
        let packed = UInt16(bytes[8]) << 8 | UInt16(bytes[9])
        func letter(_ shift: UInt16) -> Character {
            Character(UnicodeScalar(UInt8(((packed >> shift) & 0x1F) + 64)))
        }
        self.manufacturer = String([letter(10), letter(5), letter(0)])
        self.productCode = UInt16(bytes[11]) << 8 | UInt16(bytes[10])
        self.serial = UInt32(bytes[15]) << 24 | UInt32(bytes[14]) << 16
            | UInt32(bytes[13]) << 8 | UInt32(bytes[12])
        self.week = Int(bytes[16])
        self.year = 1990 + Int(bytes[17])
        self.version = "\(bytes[18]).\(bytes[19])"

        var name: String?
        for base in stride(from: 54, to: 126, by: 18) where base + 18 <= bytes.count {
            guard bytes[base] == 0, bytes[base + 1] == 0, bytes[base + 3] == 0xFC else { continue }
            let text = bytes[(base + 5) ..< (base + 18)].prefix { $0 != 0x0A }
            name = String(decoding: text, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        self.modelName = name
    }
}
