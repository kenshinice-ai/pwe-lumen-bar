import AppKit
import Foundation
import LumenBarCore

/// Intercepts the keyboard's own brightness and volume keys.
///
/// Those keys only ever reach the built-in panel: press F1 with the pointer on
/// an external monitor and nothing happens. This tap catches them and routes
/// them to whichever display the pointer is on.
///
/// Keys aimed at the built-in display are deliberately passed through untouched
/// so macOS keeps handling them, HUD and all — there is no reason to reimplement
/// something the system already does well.
@MainActor
final class MediaKeyTap {

    enum Key {
        case brightnessUp, brightnessDown
        case volumeUp, volumeDown, mute
    }

    // NX_KEYTYPE_* constants from IOKit's HID event system.
    private enum KeyType {
        static let soundUp: Int32 = 0
        static let soundDown: Int32 = 1
        static let brightnessUp: Int32 = 2
        static let brightnessDown: Int32 = 3
        static let mute: Int32 = 7
    }

    private static let defaultsKey = "mediaKeysEnabled"

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Returns true when the key was consumed; false lets macOS have it.
    private let handler: (Key, Bool) -> Bool

    init(handler: @escaping (Key, Bool) -> Bool) {
        self.handler = handler
    }

    // No deinit teardown: the tap lives for the process's lifetime, and the
    // clean-up path is main-actor isolated, which deinit cannot reach.

    static var isEnabledInDefaults: Bool {
        Defaults.shared.bool(forKey: defaultsKey)
    }

    /// The tap needs Accessibility; this is the only permission PWE Lumen Bar asks for.
    static var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func setEnabled(_ enabled: Bool) -> Bool {
        Defaults.shared.set(enabled, forKey: Self.defaultsKey)
        if enabled {
            guard Self.hasPermission else {
                Log.error("media keys: AXIsProcessTrusted() is false — not authorised")
                Self.requestPermission()
                return false
            }
            Log.error("media keys: authorised, installing tap")
            return start()
        }
        stop()
        return true
    }

    // MARK: - Tap lifecycle

    private func start() -> Bool {
        guard tap == nil else { return true }

        // NSEvent.EventType.systemDefined is 14; the media keys arrive there
        // rather than as ordinary key events.
        let mask = CGEventMask(1 << 14)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let center = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
                return center.process(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            Log.error("media keys: tap creation refused despite being authorised")
            return false
        }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.error("media keys: tap installed successfully")
        return true
    }

    private func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    // MARK: - Event handling

    private nonisolated func process(type: CGEventType,
                                     event: CGEvent) -> Unmanaged<CGEvent>? {
        // A slow handler gets the tap switched off; turning it back on is our job.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor in
                if let tap = self.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else {   // NX_SUBTYPE_AUX_CONTROL_BUTTONS
            return Unmanaged.passUnretained(event)
        }

        let data = nsEvent.data1
        let keyCode = Int32((data & 0xFFFF_0000) >> 16)
        let isDown = ((data & 0xFF00) >> 8) == 0x0A
        let isRepeat = (data & 0x1) == 1
        guard isDown else { return Unmanaged.passUnretained(event) }

        let key: Key
        switch keyCode {
        case KeyType.brightnessUp: key = .brightnessUp
        case KeyType.brightnessDown: key = .brightnessDown
        case KeyType.soundUp: key = .volumeUp
        case KeyType.soundDown: key = .volumeDown
        case KeyType.mute: key = .mute
        default: return Unmanaged.passUnretained(event)
        }

        // The run loop source is attached to the main run loop, so this callback
        // is already on the main thread. Hopping to it with `DispatchQueue.main.sync`
        // would be the main thread waiting on itself — a hard freeze on the first
        // key press.
        let consumed = MainActor.assumeIsolated { self.handler(key, isRepeat) }
        return consumed ? nil : Unmanaged.passUnretained(event)
    }
}
