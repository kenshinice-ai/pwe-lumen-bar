import AppKit
import LumenBarCore
import SwiftUI

/// The menu bar presence.
///
/// SwiftUI's `MenuBarExtra` cannot see scroll events, and adjusting brightness
/// by scrolling over the icon is the fastest control this app can offer — so
/// the status item is managed directly instead.
@MainActor
public final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let controller: DisplayController
    private var scrollMonitor: Any?
    private var outsideClickMonitor: Any?
    /// Scroll deltas arrive far faster than a display can be driven; they are
    /// accumulated and only acted on once they add up to a visible step.
    private var scrollAccumulator: CGFloat = 0

    public init(controller: DisplayController) {
        self.controller = controller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureButton()
        configurePopover()
        controller.dismissPopover = { [weak self] in self?.popover.performClose(nil) }
        installScrollMonitor()
        installDismissObservers()
    }

    deinit {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    }

    /// `.transient` is supposed to dismiss the popover on an outside click, but
    /// an accessory app is usually not the active one, so the click never
    /// reaches it. Watching for clicks in *other* apps closes the gap.
    private func installDismissObservers() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.popover.isShown else { return }
                self.popover.performClose(nil)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.popover.isShown else { return }
                self.popover.performClose(nil)
            }
        }
        // A popover outranks ordinary windows, so it will happily sit on top of
        // PWE Lumen Bar's own settings window and stay there. Whenever one of our
        // windows takes focus, the popover gets out of the way.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                guard let self, self.popover.isShown else { return }
                guard let window = notification.object as? NSWindow,
                      window !== self.popover.contentViewController?.view.window else { return }
                self.popover.performClose(nil)
            }
        }
    }

    // MARK: - Status item

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = Self.menuBarImage()
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "PWE Lumen Bar"
    }

    /// Vector template art, so the icon stays crisp at any scale factor and
    /// macOS can tint it for light and dark menu bars.
    private static func menuBarImage() -> NSImage {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        let fallback = NSImage(systemSymbolName: "display", accessibilityDescription: "PWE Lumen Bar")
            ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }

    // MARK: - Popover

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MenuRootView().environmentObject(controller))
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return togglePopover() }
        if event.type == .rightMouseUp {
            showQuickMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        controller.refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    }

    /// Right-click reaches presets without opening the full panel.
    private func showQuickMenu() {
        let menu = NSMenu()
        let presets = PresetStore.shared.presets
        if presets.isEmpty {
            let item = NSMenuItem(title: L10n.t("还没有场景", "No presets yet"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for preset in presets {
                let item = NSMenuItem(title: preset.name,
                                      action: #selector(applyPreset(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = preset.id
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L10n.t("退出 PWE Lumen Bar", "Quit PWE Lumen Bar"),
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // A menu assigned to the status item would swallow later clicks, so it
        // is detached as soon as it has been shown.
        statusItem.menu = nil
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let preset = PresetStore.shared.presets.first(where: { $0.id == id }) else { return }
        controller.applyPreset(preset)
    }

    // MARK: - Scroll to adjust

    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  let button = self.statusItem.button,
                  event.window === button.window else { return event }
            self.handleScroll(event)
            return nil
        }
    }

    private func handleScroll(_ event: NSEvent) {
        scrollAccumulator += event.scrollingDeltaY
        let step: CGFloat = 3
        guard abs(scrollAccumulator) >= step else { return }
        let direction = scrollAccumulator > 0 ? 1.0 : -1.0
        scrollAccumulator = 0
        controller.nudgeBrightness(by: 0.02 * direction)
    }
}
