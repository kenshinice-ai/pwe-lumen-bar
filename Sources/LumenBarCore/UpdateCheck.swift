import Foundation

/// The update check — and the only outgoing request PWE Lumen Bar has ever made.
///
/// Until 1.1.0 this app had no way to tell anyone a new version existed. Its repository is
/// private, so there is no releases page to watch; the only channel was the reader happening to
/// visit pwestudio.site again. A display utility is the kind of thing you set up once and then
/// never open, which makes it the worst possible candidate for "check back occasionally".
///
/// **What it sends is the whole of it: the product, this build's version, and the macOS
/// version.** No machine fingerprint, no display models, no serials, no settings. This app reads
/// EDIDs and panel serial numbers to do its job, and none of that has ever left the machine —
/// adding the first network request is not the moment to start.
///
/// Off until it is turned on. Pressing "Check for Updates" is that one check's own consent.
///
/// **This file is duplicated in three apps, deliberately, and the duplication is checked.**
/// PWE AI Bar, PWE Monitor and PWE Lumen Bar each carry a copy differing only in `product`, in
/// `downloadPage`, and in which function answers "is the interface in Chinese".
///
/// A shared package was designed and then measured against what it would buy. Three repositories
/// and three build systems -- SwiftPM, a raw `swiftc` line, and an Xcode project -- mean a package
/// costs a fourth repository, a build-system migration for one app, and "edit, tag, bump three
/// dependents" on every change: the same work moved somewhere else, plus a mechanism to learn.
/// What the duplication actually costs is one thing, and only one: nobody being told when a fix
/// reaches one copy and not the others.
///
/// `07 TOOLS/check-shared-sources.py` is that one thing. It compares the five functions carrying
/// the behaviour, ignores the configuration that is supposed to differ, and all three release
/// scripts run it. **Change all three -- and the release will tell you if you did not.**
@MainActor
public final class UpdateCheck: ObservableObject {

    public struct Release: Decodable, Equatable, Sendable {
        public let version: String
        public var published: String?
        public var notes_en: String?
        public var notes_cn: String?
        public var download: String?

        /// The reader's language first, the other one rather than nothing.
        public var notes: String? {
            let (own, other) = L10n.isChinese ? (notes_cn, notes_en) : (notes_en, notes_cn)
            return own?.isEmpty == false ? own : other
        }
    }

    @Published public private(set) var available: Release?

    /// The product page, not the file. It states the checksum and what the download contains, and
    /// a download that starts with no explanation is the one a careful person cancels.
    public nonisolated static let downloadPage = URL(string: "https://pwestudio.site/lumen")!

    private let endpoint = URL(string: "https://pwestudio.site/app/check")!
    private let defaults: UserDefaults
    private let now: () -> Date
    private let fetch: (URLRequest) async throws -> (Data, URLResponse)

    private let lastCheckKey = "updateLastCheck"
    private let dismissedKey = "updateDismissedVersion"
    private nonisolated static let enabledKey = "updateChecks"

    public nonisolated static let interval: TimeInterval = 24 * 60 * 60
    public nonisolated static let product = "lumenbar"

    public nonisolated static var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    public nonisolated static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }

    /// Whether the daily check may run. Stored in the shared suite so `pwelumenctl` reads the
    /// same answer the menu does.
    public nonisolated static var isEnabled: Bool {
        get { Defaults.shared.bool(forKey: enabledKey) }
        set { Defaults.shared.set(newValue, forKey: enabledKey) }
    }

    public init(defaults: UserDefaults = Defaults.shared,
                now: @escaping () -> Date = Date.init,
                fetch: @escaping (URLRequest) async throws -> (Data, URLResponse) = {
                    try await URLSession.shared.data(for: $0)
                }) {
        self.defaults = defaults
        self.now = now
        self.fetch = fetch
    }

    /// Runs at most once a day, does nothing without consent, and fails silently.
    public func checkIfDue(enabled: Bool?, version: String = UpdateCheck.currentVersion) async {
        guard enabled == true else { return }
        if let last = defaults.object(forKey: lastCheckKey) as? Date,
           now().timeIntervalSince(last) < Self.interval { return }
        await check(version: version)
    }

    /// The check itself. Returns whether the site answered, so a menu item that was pressed can
    /// say "could not reach it" rather than nothing at all.
    @discardableResult
    public func check(version: String = UpdateCheck.currentVersion) async -> Bool {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try? JSONSerialization.data(withJSONObject: Self.payload(version: version))

        guard let (data, response) = try? await fetch(request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data) else { return false }

        // Only an answered round trip counts as "checked today"; offline today must not cost
        // tomorrow's check.
        defaults.set(now(), forKey: lastCheckKey)

        guard Self.isNewer(release.version, than: version),
              defaults.string(forKey: dismissedKey) != release.version else {
            available = nil
            return true
        }
        available = release
        return true
    }

    /// Everything that leaves the machine, in one place, so that reading this function is the
    /// whole audit. A test fails if a key is ever added to it.
    public nonisolated static func payload(version: String) -> [String: String] {
        ["product": product, "version": version, "os": osVersion]
    }

    public func dismiss() {
        if let version = available?.version { defaults.set(version, forKey: dismissedKey) }
        available = nil
    }

    /// Numeric, component by component, so 1.10 is correctly newer than 1.9 — which a string
    /// comparison gets backwards, and which this project will reach.
    public nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }
}
