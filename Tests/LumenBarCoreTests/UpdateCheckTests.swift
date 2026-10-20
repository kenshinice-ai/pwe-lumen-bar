import Foundation
import Testing
@testable import LumenBarCore

// What a check reports. `pwelumenctl updatecheck` covers the payload and the daily gate; these
// cover the answer, which needs a scripted server rather than a refused connection.

@Suite("A manual check answers what the newest version is")
@MainActor
struct UpdateCheckOutcomeTests {
    private static let ok = HTTPURLResponse(url: URL(string: "https://pwestudio.site/app/check")!,
                                            statusCode: 200, httpVersion: nil, headerFields: nil)!

    /// A release as the site announces one: every entry in `_release.js` has a date and a page.
    private static func announced(_ version: String) -> String {
        #"{"version":"\#(version)","published":"2026-10-14","download":"https://pwestudio.site/lumen"}"#
    }

    /// A check against a scripted answer, in a defaults suite of its own that `cleanUp` removes.
    private func updates(_ suite: String,
                         answering json: @escaping () -> String) -> UpdateCheck {
        UpdateCheck(defaults: UserDefaults(suiteName: suite)!, now: { Date() },
                    fetch: { _ in (Data(json().utf8), Self.ok) })
    }

    private static func suite() -> String { "LumenBarCoreTests.\(UUID().uuidString)" }

    private func cleanUp(_ suite: String) {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    /// "Later" quiets the daily reminder. It must not make a check the reader asked for say
    /// there is nothing newer.
    @Test func aManualCheckShowsADismissedVersion() async {
        let suite = Self.suite(); defer { cleanUp(suite) }
        let updates = updates(suite) { Self.announced("1.3.0") }
        await updates.check(version: "1.2.0")
        #expect(updates.available?.version == "1.3.0")
        updates.dismiss()

        let daily = await updates.check(version: "1.2.0")
        #expect(daily == .newer(UpdateCheck.Release(version: "1.3.0", published: "2026-10-14",
                                                    download: "https://pwestudio.site/lumen")))
        #expect(updates.available == nil, "the daily reminder respects Later")

        let asked = await updates.check(version: "1.2.0", manual: true)
        #expect(asked == daily)
        #expect(updates.available?.version == "1.3.0", "asked for, it is shown")
    }

    @Test func anAnnouncedReleaseEqualToThisBuildIsCurrent() async {
        let suite = Self.suite(); defer { cleanUp(suite) }
        let updates = updates(suite) { Self.announced("1.2.0") }
        #expect(await updates.check(version: "1.2.0", manual: true) == .current)
        #expect(updates.available == nil)
    }

    /// `check.js` answers a product it has not been told about with the caller's own version
    /// and nothing else. That is no information, not "up to date".
    @Test func anEchoWithNoReleaseFieldsIsUnknown() async {
        let suite = Self.suite(); defer { cleanUp(suite) }
        let updates = updates(suite) { #"{"version":"1.2.0"}"# }
        #expect(await updates.check(version: "1.2.0", manual: true) == .unknown)
        #expect(updates.available == nil)
    }

    @Test func noAnswerIsUnreachable() async {
        let suite = Self.suite(); defer { cleanUp(suite) }
        let updates = UpdateCheck(defaults: UserDefaults(suiteName: suite)!, now: { Date() },
                                  fetch: { _ in throw URLError(.notConnectedToInternet) })
        #expect(await updates.check(version: "1.2.0", manual: true) == .unreachable)
    }
}
