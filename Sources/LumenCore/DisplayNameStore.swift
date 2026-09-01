import Foundation

/// User-chosen display names.
///
/// Two identical monitors report identical names, which makes the menu — and
/// any DDC channel troubleshooting — guesswork. Overrides are keyed by EDID
/// identity, so they survive reconnects.
public final class DisplayNameStore {
    public static let shared = DisplayNameStore()

    private static let storageKey = "displayNameOverrides"
    private let lock = NSLock()

    private init() {}

    private var names: [String: String] {
        get { Defaults.shared.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:] }
        set { Defaults.shared.set(newValue, forKey: Self.storageKey) }
    }

    public func name(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return names[key]
    }

    public func setName(_ name: String?, forKey key: String) {
        lock.lock()
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            names[key] = name
        } else {
            names.removeValue(forKey: key)
        }
        lock.unlock()
    }
}
