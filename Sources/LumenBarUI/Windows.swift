import AppKit
import LumenBarCore
import SwiftUI

/// Modal text prompt.
///
/// A popover-based menu cannot present a sheet, so naming a preset goes
/// through a plain AppKit alert.
enum Prompt {
    static func text(title: String, message: String, defaultValue: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.t("好", "OK"))
        alert.addButton(withTitle: L10n.t("取消", "Cancel"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = defaultValue
        field.placeholderString = L10n.t("场景名称", "Preset name")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// `confirmLabel` names the action on the default button. Pass a verb
    /// ("Cut Power") when one fits; it falls back to a plain "Continue".
    static func confirm(title: String, message: String, confirmLabel: String? = nil) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmLabel ?? L10n.t("继续", "Continue"))
        alert.addButton(withTitle: L10n.t("取消", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// Hosts a SwiftUI view in a real window, for content that does not belong in
/// a transient popover.
@MainActor
final class LumenBarWindow {
    private static var open: [String: NSWindow] = [:]

    static func close(id: String) {
        open[id]?.performClose(nil)
    }

    static func show<Content: View>(id: String, title: String,
                                    size: NSSize = NSSize(width: 460, height: 520),
                                    @ViewBuilder content: () -> Content) {
        if let existing = open[id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = title
        window.contentViewController = NSHostingController(rootView: content())
        // An NSWindow adopts its hosting controller's fitting size, and a
        // SwiftUI Form with no height constraint fits to nothing — which is how
        // the settings window ended up 440×1 and looked like it never opened.
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        open[id] = window

        // The token has to be captured so the observer can remove itself;
        // otherwise every open/close cycle leaves one behind.
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { open.removeValue(forKey: id) }
            if let token { NotificationCenter.default.removeObserver(token) }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Read-only report about one display, with the raw text one copy away.
struct DisplayDetailsView: View {
    let details: DisplayDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Text(details.plainText())
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Button(L10n.t("拷贝", "Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(details.plainText(), forType: .string)
                }
                if details.rawEDID != nil {
                    Button(L10n.t("导出 EDID", "Export EDID")) { exportEDID() }
                }
                Spacer()
                Button(L10n.t("存为文本", "Save as text")) { exportText() }
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 420)
    }

    private var desktop: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private func safeName(_ suffix: String) -> URL {
        let name = details.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return desktop.appendingPathComponent("PWE Lumen Bar \(name).\(suffix)")
    }

    private func exportText() {
        try? details.plainText().write(to: safeName("txt"), atomically: true, encoding: .utf8)
    }

    private func exportEDID() {
        guard let edid = details.rawEDID else { return }
        try? edid.write(to: safeName("edid.bin"))
    }
}
