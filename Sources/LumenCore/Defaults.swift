import Foundation

/// The one settings store both the app and `lumenctl` write to.
///
/// `UserDefaults.standard` resolves to a domain derived from the running
/// binary: the app lands in `com.leeliu.lumen`, while a bare command line
/// executable lands somewhere else entirely. They were silently keeping
/// separate settings — a preset saved in the menu was invisible to the CLI, and
/// a display locked from the CLI was never enforced by the running app.
///
/// An explicit suite name makes them the same store from both sides.
public enum Defaults {
    private static let suiteName = "com.leeliu.lumen.settings"

    public static let shared: UserDefaults = {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Log.error("could not open the shared defaults suite; falling back to standard")
            return .standard
        }
        return defaults
    }()

    /// macOS's own preferences, read-only.
    ///
    /// `.standard` is the right store for these: its search list includes
    /// `NSGlobalDomain`, which is where system-wide settings such as
    /// "play feedback when volume is changed" live. Lumen never writes here.
    public static let system: UserDefaults = .standard
}
