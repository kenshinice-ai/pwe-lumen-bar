import AppKit
import LumenCore
import SwiftUI

/// The heads-up display shown while a level is being changed.
///
/// macOS shows its own HUD for the built-in panel, but nothing at all when an
/// external display's brightness moves over DDC — which makes a working control
/// feel broken. This fills that gap, and appears on the display being adjusted
/// rather than always on the main one.
@MainActor
final class OSDWindow {
    static let shared = OSDWindow()

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    private let model = Model()

    final class Model: ObservableObject {
        @Published var value: Double = 0
        @Published var symbol: String = "sun.max.fill"
        @Published var caption: String = ""
        @Published var muted = false
        /// Message mode drops the level bar and just says something.
        @Published var messageOnly = false
        /// Who is talking, shown above the message.
        @Published var source: String?
    }

    private init() {}

    /// `value` is 0…1; `caption` names the display so it is obvious which one moved.
    func show(value: Double, symbol: String, caption: String,
              muted: Bool = false, on displayID: CGDirectDisplayID) {
        model.value = min(max(value, 0), 1)
        model.symbol = symbol
        model.caption = caption
        model.muted = muted
        model.messageOnly = false
        model.source = nil

        let panel = existingPanel()
        position(panel, on: displayID)
        panel.orderFrontRegardless()

        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    /// For anything that has to reach a user who is not looking at the menu —
    /// an automation failure, most of all.
    /// `source` names what produced the message. A warning that appears out of
    /// nowhere with no attribution just makes people wonder what is wrong with
    /// their Mac — the first person shown one asked exactly that.
    func showMessage(_ text: String, source: String? = nil,
                     on displayID: CGDirectDisplayID) {
        model.messageOnly = true
        model.symbol = "exclamationmark.triangle.fill"
        model.caption = text
        model.source = source
        model.muted = false

        let panel = existingPanel()
        position(panel, on: displayID)
        panel.orderFrontRegardless()

        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }

    private func existingPanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // Above full-screen apps and menus, like the system's own HUD.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentViewController = NSHostingController(rootView: OSDView(model: model))
        self.panel = panel
        return panel
    }

    /// Bottom-centre of the display being adjusted, matching where macOS puts its own.
    private func position(_ panel: NSPanel, on displayID: CGDirectDisplayID) {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == displayID
        } ?? NSScreen.main

        guard let frame = screen?.frame else { return }
        let size = NSSize(width: 200, height: 200)
        panel.setFrame(NSRect(x: frame.midX - size.width / 2,
                              y: frame.minY + frame.height * 0.09,
                              width: size.width, height: size.height),
                       display: false)
    }
}

private struct OSDView: View {
    @ObservedObject var model: OSDWindow.Model

    var body: some View {
        VStack(spacing: 14) {
            if let source = model.source {
                Text(source)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: model.muted ? "speaker.slash.fill" : model.symbol)
                .font(.system(size: 62, weight: .regular))
                .foregroundStyle(.primary)
                .frame(height: 70)

            if !model.messageOnly {
                // Sixteen blocks, the way the system HUD reads a level.
                HStack(spacing: 2) {
                    ForEach(0 ..< 16, id: \.self) { index in
                        Rectangle()
                            .fill(Double(index) / 16 < model.value ? AnyShapeStyle(.primary)
                                                                   : AnyShapeStyle(.quaternary))
                            .frame(width: 8, height: 8)
                    }
                }
            }

            Text(model.caption)
                .font(model.messageOnly ? .callout : .caption)
                .foregroundStyle(model.messageOnly ? .primary : .secondary)
                .multilineTextAlignment(.center)
                // Two lines, because a volume HUD may need to name both the
                // display it moved and the device you are actually hearing.
                .lineLimit(model.messageOnly ? 4 : 2)
                .frame(maxWidth: 176)
        }
        .padding(20)
        .frame(width: 200, height: 200)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
