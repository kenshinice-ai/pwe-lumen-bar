import AppKit
import Foundation
import LumenCore

/// Automation entry point: `lumen://` URLs.
///
/// Deliberately excludes screen capture. Any app or web page can open a custom
/// URL scheme, and Lumen holds Screen Recording permission — exposing capture
/// here would hand silent screenshots to anything that can open a link. Display
/// settings are reversible and visible, so they are safe to automate.
///
/// Shortcuts reaches these through its "Open URLs" action.
@MainActor
public enum URLCommands {

    public static func handle(_ url: URL, controller: DisplayController) {
        guard url.scheme?.lowercased() == "lumen" else { return }
        let command = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        let query = parameters(of: url)

        switch command {
        case "brightness":
            adjust(query, controller: controller) { card, value in
                controller.setBrightness(value, for: card)
            } current: { $0.brightness }

        case "volume":
            adjust(query, controller: controller) { card, value in
                controller.setVolume(value, for: card)
            } current: { $0.volume }

        case "warmth":
            adjust(query, controller: controller) { card, value in
                controller.setWarmth(value, for: card)
            } current: { $0.warmth }

        case "contrast":
            adjust(query, controller: controller) { card, value in
                controller.setContrast(value, for: card)
            } current: { $0.contrast ?? 0 }

        case "off":
            guard let card = resolve(query["display"], controller: controller) else {
                report(controller, L10n.t("找不到那块屏", "No such display")); return
            }
            controller.sleepDisplay(card)

        case "on":
            let token = query["display"]
            if let entry = controller.offDisplays.first(where: {
                guard let token, !token.isEmpty else { return true }
                return $0.info.name.localizedCaseInsensitiveContains(token)
                    || String($0.id) == token
            }) {
                controller.wake(entry.info)
            } else {
                report(controller, L10n.t("没有被关闭的屏幕", "No display is switched off"))
            }

        case "link":
            let state = query["state"]?.lowercased() ?? "toggle"
            let linked = state == "toggle" ? !controller.brightnessLinked : (state == "on" || state == "true")
            controller.setBrightnessLinked(linked)

        case "matchbrightness":
            guard let card = resolve(query["display"], controller: controller) else {
                report(controller, L10n.t("找不到那块屏", "No such display")); return
            }
            controller.matchBrightnessToAll(from: card)

        case "main":
            guard let card = resolve(query["display"], controller: controller) else {
                report(controller, L10n.t("找不到那块屏", "No such display")); return
            }
            controller.setAsMain(card)

        case "link":
            let state = query["state"]?.lowercased() ?? "toggle"
            let linked = state == "toggle" ? !controller.brightnessLinked : (state == "on" || state == "true")
            controller.setBrightnessLinked(linked)

        case "matchbrightness":
            guard let card = resolve(query["display"], controller: controller) else {
                report(controller, L10n.t("找不到那块屏", "No such display")); return
            }
            controller.matchBrightnessToAll(from: card)

        case "mirror":
            guard let card = resolve(query["display"], controller: controller) else {
                report(controller, L10n.t("找不到那块屏", "No such display")); return
            }
            controller.toggleMirror(card)

        case "mute":
            guard let card = resolve(query["display"], controller: controller) else { return }
            let state = query["state"]?.lowercased() ?? "toggle"
            let shouldMute = state == "toggle" ? !card.isMuted : (state == "on" || state == "true")
            if shouldMute != card.isMuted { controller.toggleMute(card) }

        case "rotate":
            guard let card = resolve(query["display"], controller: controller) else {
                report(controller, L10n.t("找不到那块屏", "No such display")); return
            }
            guard let angle = query["angle"].flatMap({ Int($0) }),
                  let rotation = Rotation(rawValue: angle) else {
                report(controller, L10n.t("angle 只能是 0/90/180/270", "angle must be 0, 90, 180 or 270"))
                return
            }
            controller.rotate(card, to: rotation)

        case "mode":
            guard let card = resolve(query["display"], controller: controller) else {
                report(controller, L10n.t("找不到那块屏", "No such display")); return
            }
            guard let id = query["id"], let mode = card.allModes.first(where: { $0.id == id }) else {
                report(controller, L10n.t("这块屏没有 id 为 \(query["id"] ?? "?") 的模式",
                                          "No mode with id \(query["id"] ?? "?") on that display"))
                return
            }
            controller.applyMode(mode, for: card)

        case "input":
            // Accepts a friendly name or a raw code, since vendor-defined
            // inputs (0x15, 0x21 …) have no standard name to type.
            guard let card = resolve(query["display"], controller: controller),
                  let token = query["source"]?.lowercased() else { return }
            let raw: UInt16? = InputSource.allCases.first {
                $0.label.lowercased().replacingOccurrences(of: " ", with: "") == token
            }?.rawValue ?? UInt16(token.replacingOccurrences(of: "0x", with: ""), radix: 16)
            guard let raw else {
                report(controller, L10n.t("认不出这个输入源：\(token)", "Unrecognised input source: \(token)"))
                return
            }
            controller.selectInput(rawValue: raw, for: card)

        case "preset":
            guard let name = query["name"],
                  let preset = PresetStore.shared.preset(named: name) else {
                controller.status = L10n.t("找不到这个场景", "No preset by that name")
                return
            }
            controller.applyPreset(preset)

        case "arrange":
            if query["tile"] != nil || query["mode"] == "tile" {
                controller.tileHorizontally()
            } else if let card = resolve(query["display"], controller: controller),
                      let edge = query["edge"].flatMap({ ArrangementEdge(rawValue: $0.lowercased()) }) {
                controller.place(card, edge)
            }

        case "refresh":
            controller.refresh()

        case "settings":
            controller.openSettings()

        case "sleep":
            controller.sleepAll()

        default:
            report(controller, L10n.t("收到无法识别的 lumen:// 命令\n\(command)",
                                      "Received an unrecognised lumen:// command\n\(command)"))
        }
    }

    /// Automation is fired from Shortcuts, not from the open popover, so a
    /// failure written only into the menu's status line is a failure nobody
    /// sees. Errors go on screen.
    private static func report(_ controller: DisplayController, _ message: String) {
        controller.status = message
        OSDWindow.shared.showMessage(
            message,
            source: L10n.t("Lumen · 自动化命令", "Lumen · automation command"),
            on: CGMainDisplayID())
    }

    // MARK: - Helpers

    private static func parameters(of url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return [:] }
        var result: [String: String] = [:]
        for item in items { result[item.name.lowercased()] = item.value ?? "" }
        return result
    }

    /// `display=` accepts `cursor`, `main`, a display ID, or part of a name.
    private static func resolve(_ token: String?, controller: DisplayController) -> DisplayCard? {
        guard let token, !token.isEmpty else { return controller.cardUnderCursor() }
        switch token.lowercased() {
        case "cursor": return controller.cardUnderCursor()
        case "main": return controller.cards.first { $0.info.isMain }
        case "builtin", "internal": return controller.cards.first { $0.info.isBuiltin }
        default:
            if let id = UInt32(token), let match = controller.cards.first(where: { $0.id == id }) {
                return match
            }
            return controller.cards.first { $0.info.name.localizedCaseInsensitiveContains(token) }
        }
    }

    /// Shared shape for the level controls: `value` sets, `delta` nudges.
    /// Both are percentages, so automation never has to think in 0–1 floats.
    private static func adjust(_ query: [String: String],
                               controller: DisplayController,
                               apply: (DisplayCard, Double) -> Void,
                               current: (DisplayCard) -> Double) {
        guard let card = resolve(query["display"], controller: controller) else {
            report(controller, L10n.t("找不到那块屏：\(query["display"] ?? "?")",
                                      "No such display: \(query["display"] ?? "?")"))
            return
        }
        if let raw = query["value"], let percent = Double(raw) {
            apply(card, min(max(percent / 100, 0), 1))
        } else if let raw = query["delta"], let percent = Double(raw) {
            apply(card, min(max(current(card) + percent / 100, 0), 1))
        } else {
            report(controller, L10n.t("需要 value 或 delta 参数", "Needs a value or delta parameter"))
        }
    }
}
