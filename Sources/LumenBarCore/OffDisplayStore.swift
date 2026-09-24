import CoreGraphics
import Foundation

/// A display PWE Lumen Bar took off the desktop.
///
/// Soft disconnect is committed permanently, and — verified on macOS 26.6.2 —
/// the private `CGSConfigureDisplayEnabled` ignores the configuration scope: a
/// display switched off with `.forAppOnly` stays off after the process that did
/// it exits. So the window server will not remember to bring it back, and this
/// record is the only thing that can. It lives in the shared settings suite, so
/// it survives a crash, and the app and `pwelumenctl` see the same list.
public struct OffRecord: Codable, Equatable, Identifiable, Sendable {
    public enum Reason: String, Codable, Sendable {
        /// The Turn off button, the ⋯ menu, a shortcut or a URL.
        case manual
        /// "Put the built-in panel away when an external display connects".
        case automatic
        /// `pwelumenctl off` / `disconnect`.
        case commandLine
    }

    public var key: String
    /// Valid for the session that switched the display off. Re-enabling an ID
    /// that no longer exists fails harmlessly, so a stale one costs nothing.
    public var displayID: CGDirectDisplayID
    public var name: String
    public var reason: Reason
    /// Where the card sat in the panel, so the row that brings it back appears
    /// in the same place the card left from.
    public var slot: Int
    /// Another display was online with the same identity when this one went
    /// off — two identical monitors that report no serial number. The identity
    /// cannot then tell them apart, so only the display ID may retire the record.
    public var keyWasShared: Bool
    public var date: Date

    public var id: String { "\(key)#\(displayID)" }

    public init(key: String, displayID: CGDirectDisplayID, name: String, reason: Reason,
                slot: Int, keyWasShared: Bool, date: Date = Date()) {
        self.key = key
        self.displayID = displayID
        self.name = name
        self.reason = reason
        self.slot = slot
        self.keyWasShared = keyWasShared
        self.date = date
    }
}

public final class OffDisplayStore: @unchecked Sendable {
    public static let shared = OffDisplayStore()

    private let defaultsKey = "offDisplays"
    private let lock = NSLock()

    private init() {}

    /// Read straight from the store every time: `pwelumenctl` writes to it from
    /// another process, and a cached copy would miss that.
    public var records: [OffRecord] {
        lock.lock(); defer { lock.unlock() }
        return load()
    }

    public func add(_ record: OffRecord) {
        mutate { records in
            records.removeAll { $0.displayID == record.displayID || $0.id == record.id }
            records.append(record)
        }
    }

    public func remove(_ record: OffRecord) {
        mutate { $0.removeAll { $0.id == record.id } }
    }

    public func removeAll() {
        mutate { $0.removeAll() }
    }

    /// Drop records for displays that are back, and return the ones still off.
    @discardableResult
    public func reconcile(active displays: [DisplayInfo]) -> [OffRecord] {
        var stillOff: [OffRecord] = []
        mutate { records in
            let split = Self.reconcile(records,
                                       activeIDs: Set(displays.map(\.id)),
                                       activeKeys: displays.map(\.persistentKey))
            records = split.stillOff
            stillOff = split.stillOff
        }
        return stillOff
    }

    /// Which records still describe a display that is off.
    ///
    /// A record is retired when its display ID is active again, or when its
    /// identity is — a replugged monitor comes back under a new ID. The second
    /// test is skipped when the identity was shared at the time: with two
    /// identical monitors online, "that identity is active" may be the *other*
    /// one, and dropping the record would lose the only way back to this one.
    /// Keeping a stale record is the safe mistake; its row turns nothing on and
    /// then goes away.
    static func reconcile(_ records: [OffRecord],
                          activeIDs: Set<CGDirectDisplayID>,
                          activeKeys: [String]) -> (stillOff: [OffRecord], stale: [OffRecord]) {
        let keys = Set(activeKeys)
        var stillOff: [OffRecord] = []
        var stale: [OffRecord] = []
        for record in records {
            let back = activeIDs.contains(record.displayID)
                || (!record.keyWasShared && keys.contains(record.key))
            if back { stale.append(record) } else { stillOff.append(record) }
        }
        return (stillOff, stale)
    }

    // MARK: - Storage

    private func mutate(_ change: (inout [OffRecord]) -> Void) {
        lock.lock(); defer { lock.unlock() }
        var records = load()
        change(&records)
        save(records)
    }

    private func load() -> [OffRecord] {
        guard let data = Defaults.shared.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([OffRecord].self, from: data)) ?? []
    }

    private func save(_ records: [OffRecord]) {
        if records.isEmpty {
            Defaults.shared.removeObject(forKey: defaultsKey)
        } else if let data = try? JSONEncoder().encode(records) {
            Defaults.shared.set(data, forKey: defaultsKey)
        }
    }
}
