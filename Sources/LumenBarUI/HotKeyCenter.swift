import AppKit
import Carbon.HIToolbox
import Foundation
import LumenBarCore

/// System-wide keyboard shortcuts.
///
/// Uses Carbon's `RegisterEventHotKey`, which is the one global-hotkey API that
/// needs no Accessibility permission — a menu bar utility should not have to
/// ask for control of the whole machine just to dim a screen.
///
/// Every shortcut acts on the display under the pointer, so one set of keys
/// serves any number of screens without asking which one was meant.
/// A key combination, stored as the Carbon values the hot key API wants plus
/// the label captured when it was recorded — building a readable name back
/// from a key code needs the keyboard layout, which can change.
struct KeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String
}

final class HotKeyCenter {
    static let shared = HotKeyCenter()

    enum Action: UInt32, CaseIterable {
        case brightnessUp = 1
        case brightnessDown
        case volumeUp
        case volumeDown
        case muteToggle
        case capture
        case sleepDisplay

        /// Control–Option plus a key that is not spoken for by macOS.
        var defaultKeyCode: UInt32 {
            switch self {
            case .brightnessUp: return UInt32(kVK_UpArrow)
            case .brightnessDown: return UInt32(kVK_DownArrow)
            case .volumeUp: return UInt32(kVK_RightArrow)
            case .volumeDown: return UInt32(kVK_LeftArrow)
            case .muteToggle: return UInt32(kVK_ANSI_M)
            case .capture: return UInt32(kVK_ANSI_S)
            case .sleepDisplay: return UInt32(kVK_ANSI_P)
            }
        }

        var defaultModifiers: UInt32 { UInt32(controlKey | optionKey) }

        var defaultLabel: String {
            switch self {
            case .brightnessUp: return "⌃⌥↑"
            case .brightnessDown: return "⌃⌥↓"
            case .volumeUp: return "⌃⌥→"
            case .volumeDown: return "⌃⌥←"
            case .muteToggle: return "⌃⌥M"
            case .capture: return "⌃⌥S"
            case .sleepDisplay: return "⌃⌥P"
            }
        }

        var defaultBinding: KeyBinding {
            KeyBinding(keyCode: defaultKeyCode, modifiers: defaultModifiers, label: defaultLabel)
        }

        /// What is bound now — the user's choice, or the default.
        var binding: KeyBinding {
            HotKeyCenter.storedBindings()[rawValue] ?? defaultBinding
        }

        var shortcutLabel: String { binding.label }

        var describe: String {
            switch self {
            case .brightnessUp: return L10n.t("调亮", "Brighter")
            case .brightnessDown: return L10n.t("调暗", "Dimmer")
            case .volumeUp: return L10n.t("音量加", "Volume up")
            case .volumeDown: return L10n.t("音量减", "Volume down")
            case .muteToggle: return L10n.t("静音开关", "Toggle mute")
            case .capture: return L10n.t("截图这块屏", "Capture this display")
            case .sleepDisplay: return L10n.t("关闭/唤醒这块屏", "Turn this display off / on")
            }
        }
    }

    private static let signature: OSType = 0x4C554D4E // 'LUMN'
    private static let defaultsKey = "globalShortcutsEnabled"
    private static let bindingsKey = "shortcutBindings"

    private var registered: [EventHotKeyRef?] = []
    /// Actions the system refused, so a conflict is reported against the right one.
    private var failedActions: Set<UInt32> = []
    private var eventHandler: EventHandlerRef?
    private var perform: ((Action) -> Void)?

    private init() {}

    static var isEnabledInDefaults: Bool {
        Defaults.shared.bool(forKey: defaultsKey)
    }

    static func storedBindings() -> [UInt32: KeyBinding] {
        guard let data = Defaults.shared.data(forKey: bindingsKey),
              let decoded = try? JSONDecoder().decode([UInt32: KeyBinding].self, from: data)
        else { return [:] }
        return decoded
    }

    /// Rebind one action. Registration is redone immediately so a combination
    /// another app already owns is reported now rather than silently ignored.
    @discardableResult
    func rebind(_ action: Action, to binding: KeyBinding?) -> Bool {
        var bindings = Self.storedBindings()
        if let binding {
            bindings[action.rawValue] = binding
        } else {
            bindings.removeValue(forKey: action.rawValue)
        }
        if let data = try? JSONEncoder().encode(bindings) {
            Defaults.shared.set(data, forKey: Self.bindingsKey)
        }
        guard eventHandler != nil else { return true }
        uninstall()
        install()
        // Report on the binding that was actually edited. Counting every
        // registration blamed this combination for a conflict somewhere else.
        return failedActions.contains(action.rawValue) == false
    }

    /// The step one press moves a slider. Small enough to be precise, large
    /// enough that holding the key is not a chore.
    static let step = 0.05

    func setEnabled(_ enabled: Bool, perform: @escaping (Action) -> Void) {
        Defaults.shared.set(enabled, forKey: Self.defaultsKey)
        self.perform = perform
        enabled ? install() : uninstall()
    }

    private func install() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard result == noErr, let action = Action(rawValue: hotKeyID.id) else { return noErr }
            DispatchQueue.main.async { HotKeyCenter.shared.perform?(action) }
            return noErr
        }, 1, &eventType, nil, &eventHandler)

        guard status == noErr else {
            Log.error("InstallEventHandler failed: \(status)")
            return
        }

        failedActions.removeAll()
        for action in Action.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let binding = action.binding
            let registerStatus = RegisterEventHotKey(binding.keyCode, binding.modifiers, id,
                                                     GetApplicationEventTarget(), 0, &ref)
            if registerStatus == noErr {
                registered.append(ref)
            } else {
                // Almost always means another app already owns the combination.
                failedActions.insert(action.rawValue)
                Log.error("hotkey \(action.shortcutLabel) unavailable: \(registerStatus)")
            }
        }
        Log.info("global shortcuts installed: \(registered.count)/\(Action.allCases.count)")
    }

    private func uninstall() {
        for ref in registered { if let ref { UnregisterEventHotKey(ref) } }
        registered.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
