import Foundation

/// What a monitor says it supports, parsed from its DDC/CI capabilities string.
///
/// This replaces guesswork. Input source codes above 0x12 are vendor-defined —
/// this Philips accepts `11 12 0F 15 21 22 2F 35`, four of which no standard
/// list contains — so offering a hard-coded menu means offering inputs the
/// monitor will reject.
public struct DDCCapabilities {
    public let raw: String
    public let model: String?
    public let mccsVersion: String?
    /// VCP codes the monitor implements.
    public let supported: Set<UInt8>
    /// For enumerated features, the values it accepts.
    public let enumeratedValues: [UInt8: [UInt8]]

    public func supports(_ vcp: VCP) -> Bool { supported.contains(vcp.rawValue) }

    /// The input sources this monitor actually accepts, in the order it lists them.
    public var inputSources: [UInt8] { enumeratedValues[VCP.inputSource.rawValue] ?? [] }

    // MARK: - Parsing

    /// Capabilities look like:
    /// `(prot(monitor)type(LCD)model(27B1U3900)cmds(…)vcp(02 10 12 60(11 12 0F) …)…)`
    public init?(raw: String) {
        guard raw.contains("vcp(") else { return nil }
        self.raw = raw
        self.model = Self.section(named: "model", in: raw)
        self.mccsVersion = Self.section(named: "mccs_ver", in: raw)

        guard let body = Self.section(named: "vcp", in: raw) else { return nil }

        var codes = Set<UInt8>()
        var values: [UInt8: [UInt8]] = [:]
        var index = body.startIndex

        while index < body.endIndex {
            // A code is a run of hex digits; anything longer than two is a
            // vendor-extended code this parser has no use for.
            guard body[index].isHexDigit else {
                index = body.index(after: index)
                continue
            }
            var end = index
            while end < body.endIndex, body[end].isHexDigit { end = body.index(after: end) }
            let token = String(body[index ..< end])
            index = end

            guard token.count == 2, let code = UInt8(token, radix: 16) else {
                // Skip this token's value list too, if it has one.
                if index < body.endIndex, body[index] == "(" ,
                   let close = body[index...].firstIndex(of: ")") {
                    index = body.index(after: close)
                }
                continue
            }
            codes.insert(code)

            if index < body.endIndex, body[index] == "(",
               let close = body[index...].firstIndex(of: ")") {
                let inner = body[body.index(after: index) ..< close]
                values[code] = inner.split(whereSeparator: \.isWhitespace)
                    .compactMap { UInt8($0, radix: 16) }
                index = body.index(after: close)
            }
        }
        self.supported = codes
        self.enumeratedValues = values
    }

    /// Extract `name(…)`, honouring nested parentheses.
    private static func section(named name: String, in text: String) -> String? {
        guard let start = text.range(of: name + "(") else { return nil }
        var depth = 1
        var index = start.upperBound
        while index < text.endIndex {
            if text[index] == "(" { depth += 1 }
            if text[index] == ")" {
                depth -= 1
                if depth == 0 { return String(text[start.upperBound ..< index]) }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
