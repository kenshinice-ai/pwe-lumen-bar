import CoreGraphics
import Foundation
import Testing
@testable import LumenBarCore

// MARK: - What is left on screen

@Suite("A display may be switched off only if a lit one remains")
struct RemainingDisplayTests {
    private func display(_ name: String, mirror: Bool = false, dark: Bool = false) -> PowerEngine.RemainingDisplay {
        .init(isMirror: mirror, isDark: dark, name: name)
    }

    @Test func anotherLitDisplayAllowsIt() {
        #expect(PowerEngine.assessRemaining([display("Studio Display")]) == .lit)
    }

    @Test func nothingLeftRefuses() {
        #expect(PowerEngine.assessRemaining([]) == .none)
    }

    @Test func aMirrorDoesNotCount() {
        // A mirror follows its source; with the source gone it cannot be relied on.
        #expect(PowerEngine.assessRemaining([display("TV", mirror: true)]) == .none)
    }

    @Test func aDarkDisplayIsNamed() {
        // Online but with its backlight cut over DDC: present, and showing nothing.
        #expect(PowerEngine.assessRemaining([display("Philips", dark: true)]) == .onlyDark(name: "Philips"))
    }

    @Test func oneLitAmongDarkIsEnough() {
        let remaining = [display("Philips", dark: true), display("Studio Display")]
        #expect(PowerEngine.assessRemaining(remaining) == .lit)
    }
}

// MARK: - Whether a record still describes a display that is off

@Suite("Off records retire only when their display is certainly back")
struct OffRecordReconcileTests {
    private func record(_ key: String, _ id: CGDirectDisplayID, shared: Bool = false) -> OffRecord {
        OffRecord(key: key, displayID: id, name: key, reason: .manual, slot: 0, keyWasShared: shared)
    }

    @Test func stillOffWhileNeitherIDNorIdentityIsActive() {
        let split = OffDisplayStore.reconcile([record("builtin", 1)], activeIDs: [3, 5], activeKeys: ["a", "b"])
        #expect(split.stillOff.count == 1)
        #expect(split.stale.isEmpty)
    }

    @Test func retiredWhenItsIDIsActiveAgain() {
        let split = OffDisplayStore.reconcile([record("builtin", 1)], activeIDs: [1, 3], activeKeys: ["builtin", "a"])
        #expect(split.stillOff.isEmpty)
    }

    @Test func retiredWhenAReplugBringsItBackUnderANewID() {
        let split = OffDisplayStore.reconcile([record("610-44602-123", 5)], activeIDs: [3, 7],
                                              activeKeys: ["a", "610-44602-123"])
        #expect(split.stillOff.isEmpty)
    }

    @Test func aSharedIdentityCannotRetireIt() {
        // Two identical monitors with no serial: the active one carrying the same
        // identity may be the *other* one. Dropping this record would lose the only
        // way back to the display that is actually off.
        let split = OffDisplayStore.reconcile([record("DEL-1234-0", 5, shared: true)], activeIDs: [3, 6],
                                              activeKeys: ["a", "DEL-1234-0"])
        #expect(split.stillOff.count == 1)
    }

    @Test func recordsSurviveARoundTripThroughStorage() throws {
        let original = [record("builtin", 1), record("DEL-1234-0", 5, shared: true)]
        let decoded = try JSONDecoder().decode([OffRecord].self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
