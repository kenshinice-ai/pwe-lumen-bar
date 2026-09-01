import AppKit
import CoreGraphics
import Foundation

/// Live inventory of attached displays.
public final class DisplayRegistry {
    public static let shared = DisplayRegistry()

    /// Posted whenever displays are added, removed, or reconfigured.
    public static let didChange = Notification.Name("com.leeliu.lumen.displaysDidChange")

    private var callbackInstalled = false

    private init() {}

    public func startWatching() {
        guard !callbackInstalled else { return }
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            // Ignore the "about to change" half of every transaction.
            guard !flags.contains(.beginConfigurationFlag) else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: DisplayRegistry.didChange, object: nil)
            }
        }, nil)
        callbackInstalled = true
    }

    public func onlineDisplays() -> [DisplayInfo] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(32, &ids, &count) == .success else { return [] }

        var screensByID: [CGDirectDisplayID: NSScreen] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            screensByID[CGDirectDisplayID(number.uint32Value)] = screen
        }

        return ids[0 ..< Int(count)].map { id in
            let screen = screensByID[id]
            // The identity key has to be built before the name, because a
            // renamed display is looked up by identity, not by its old name.
            let key = CGDisplayIsBuiltin(id) == 1
                ? "builtin"
                : "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
            let systemName = screen?.localizedName
                ?? CoreDisplayInfo.productName(for: id)
                ?? fallbackName(for: id)
            return DisplayInfo(
                id: id,
                name: DisplayNameStore.shared.name(forKey: key) ?? systemName,
                isBuiltin: CGDisplayIsBuiltin(id) == 1,
                isMain: CGDisplayIsMain(id) == 1,
                vendor: CGDisplayVendorNumber(id),
                model: CGDisplayModelNumber(id),
                serial: CGDisplaySerialNumber(id),
                unitNumber: CGDisplayUnitNumber(id),
                bounds: CGDisplayBounds(id),
                rotation: Rotation.from(degrees: CGDisplayRotation(id)),
                backingScale: screen?.backingScaleFactor ?? 1,
                currentMode: ModeEngine.currentMode(for: id),
                mirrorSource: CGDisplayMirrorsDisplay(id),
                connection: CoreDisplayInfo.connectionType(for: id)
            )
        }
    }

    private func fallbackName(for id: CGDirectDisplayID) -> String {
        CGDisplayIsBuiltin(id) == 1
            ? L10n.t("内建显示器", "Built-in Display")
            : L10n.t("显示器 \(id)", "Display \(id)")
    }

    /// Index of a display among the external ones only — the pairing key used
    /// for DDC channels.
    public func externalIndex(of displayID: CGDirectDisplayID) -> Int? {
        let externals = onlineDisplays().filter { !$0.isBuiltin }
        return externals.firstIndex { $0.id == displayID }
    }
}
