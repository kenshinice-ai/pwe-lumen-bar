import Foundation

/// Bilingual copy, resolved at the point of use.
///
/// PWE Lumen Bar ships two languages and assembles its own bundle, so a `.lproj`
/// resource pipeline would add a failure mode (a missing bundle silently
/// showing raw keys) for no benefit. Pairing the two strings at the call site
/// keeps them impossible to desynchronise and readable in review.
///
/// Developer-facing text — `Log` messages, `pwelumenctl` symbol dumps — stays in
/// English on purpose: it ends up in bug reports.
public enum Language: String, CaseIterable, Sendable {
    case system
    case chinese = "zh"
    case english = "en"

    public var displayName: String {
        switch self {
        case .system: return L10n.t("跟随系统", "System")
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

public enum L10n {
    private static let overrideKey = "languageOverride"

    /// The user's explicit choice, or `.system` to follow the OS.
    public static var override: Language {
        get {
            guard let raw = Defaults.shared.string(forKey: overrideKey),
                  let language = Language(rawValue: raw) else { return .system }
            return language
        }
        set {
            Defaults.shared.set(newValue.rawValue, forKey: overrideKey)
            resolved = resolve()
        }
    }

    /// Set by `pwelumenctl --lang`, which has no business writing user defaults.
    public static var transientOverride: Language? {
        didSet { resolved = resolve() }
    }

    private(set) static var resolved: Language = resolve()

    public static var isChinese: Bool { resolved == .chinese }

    private static func resolve() -> Language {
        if let transient = transientOverride, transient != .system { return transient }
        let stored = override
        if stored != .system { return stored }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .chinese : .english
    }

    /// Pick the copy for the active language.
    public static func t(_ chinese: String, _ english: String) -> String {
        isChinese ? chinese : english
    }
}
