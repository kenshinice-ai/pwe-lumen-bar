import AppKit
import LumenBarCore
import SwiftUI

/// A floating "keep or revert" prompt with a countdown.
///
/// Any change that can make a screen unreadable — a resolution the monitor
/// cannot show, a rotation that puts the menu bar on the side — goes through
/// here. Doing nothing is the safe outcome: the change reverts on its own.
@MainActor
final class ConfirmRevertPanel {
    private static var active: ConfirmRevertPanel?

    private var panel: NSPanel?
    private var timer: Timer?
    private let model: Model
    private let onKeep: () -> Void
    private let onRevert: () -> Void
    private let keepIsDefault: Bool
    private let avoiding: CGDirectDisplayID?

    final class Model: ObservableObject {
        @Published var remaining: Int
        let title: String
        let message: String
        /// Kept so the progress bar tracks the real duration instead of a
        /// hard-coded 15.
        let total: Int
        init(title: String, message: String, remaining: Int) {
            self.title = title
            self.message = message
            self.remaining = remaining
            self.total = remaining
        }
    }

    /// - Parameters:
    ///   - keepIsDefault: whether Return keeps the change. Off when the change
    ///     may have left someone unable to see — a reflexive Return must not
    ///     make that stick.
    ///   - avoiding: a display the panel must not appear on, because the change
    ///     being confirmed is that display going dark.
    static func present(title: String,
                        message: String,
                        seconds: Int = 15,
                        keepIsDefault: Bool = true,
                        avoiding: CGDirectDisplayID? = nil,
                        onKeep: @escaping () -> Void,
                        onRevert: @escaping () -> Void) {
        // Supersede by *reverting* the pending change, not by dropping it.
        // Abandoning it would leave an unconfirmed change permanently applied —
        // exactly the outcome this panel exists to prevent.
        active?.dismiss(keep: false, runHandler: true)
        let instance = ConfirmRevertPanel(title: title, message: message, seconds: seconds,
                                          keepIsDefault: keepIsDefault, avoiding: avoiding,
                                          onKeep: onKeep, onRevert: onRevert)
        active = instance
        instance.show()
    }

    private init(title: String, message: String, seconds: Int,
                 keepIsDefault: Bool, avoiding: CGDirectDisplayID?,
                 onKeep: @escaping () -> Void, onRevert: @escaping () -> Void) {
        self.model = Model(title: title, message: message, remaining: seconds)
        self.keepIsDefault = keepIsDefault
        self.avoiding = avoiding
        self.onKeep = onKeep
        self.onRevert = onRevert
    }

    private func show() {
        let content = ConfirmRevertView(
            model: model,
            keepIsDefault: keepIsDefault,
            keep: { [weak self] in self?.dismiss(keep: true, runHandler: true) },
            revert: { [weak self] in self?.dismiss(keep: false, runHandler: true) })

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 168),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: content)
        place(panel)
        panel.orderFrontRegardless()
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.model.remaining -= 1
                if self.model.remaining <= 0 { self.dismiss(keep: false, runHandler: true) }
            }
        }
    }

    /// On the screen the pointer is on — that is where the eyes and the hand
    /// are — unless that is the display going dark, in which case on one that
    /// is not. `NSScreen.screens` can still list the departing display for a
    /// moment after it leaves, which is why it is excluded by ID, not trusted
    /// to be gone.
    private func place(_ panel: NSPanel) {
        func number(_ screen: NSScreen) -> CGDirectDisplayID? {
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                .map { CGDirectDisplayID($0.uint32Value) }
        }
        let usable = NSScreen.screens.filter { avoiding == nil || number($0) != avoiding }
        let mouse = NSEvent.mouseLocation
        guard let screen = usable.first(where: { $0.frame.contains(mouse) }) ?? usable.first else {
            panel.center()
            return
        }
        let area = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2))
    }

    private func dismiss(keep: Bool, runHandler: Bool) {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        if Self.active === self { Self.active = nil }
        guard runHandler else { return }
        keep ? onKeep() : onRevert()
    }
}

private struct ConfirmRevertView: View {
    @ObservedObject var model: ConfirmRevertPanel.Model
    let keepIsDefault: Bool
    let keep: () -> Void
    let revert: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.title).font(.headline)
            Text(model.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: Double(model.remaining), total: Double(model.total))
                .controlSize(.small)
            HStack {
                Text(L10n.t("\(model.remaining) 秒后自动恢复",
                            "Reverts in \(model.remaining)s"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                // Escape reverts: the safe action deserves the reflexive key.
                Button(L10n.t("恢复", "Revert"), action: revert)
                    .keyboardShortcut(.cancelAction)
                if keepIsDefault {
                    Button(L10n.t("保留", "Keep"), action: keep)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(L10n.t("保留", "Keep"), action: keep)
                }
            }
            // ⌘. is the Mac's other "stop"; it reverts too.
            Button("", action: revert)
                .keyboardShortcut(".", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(20)
        .frame(width: 340)
    }
}
