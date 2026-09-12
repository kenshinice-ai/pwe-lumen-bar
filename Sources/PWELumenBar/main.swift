import AppKit
import LumenBarCore
import LumenBarUI

// A plain AppKit entry point rather than a SwiftUI `App`: the menu bar item is
// managed directly so it can receive scroll events, which `MenuBarExtra` does
// not expose.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: DisplayController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        checkPlatform()
        let controller = DisplayController()
        self.controller = controller
        self.statusItem = StatusItemController(controller: controller)
        controller.showWelcomeIfFirstRun()

        // After the interface exists, never before it: an update check is a convenience, and a
        // convenience must not sit between launching and the menu bar appearing.
        Task { await controller.updates.checkIfDue(enabled: UpdateCheck.isEnabled) }
    }

    /// PWE Lumen Bar is an Apple Silicon app: DDC/CI here runs over `IOAVService`, which
    /// does not exist on Intel Macs, and the whole display stack it drives is
    /// the Apple Silicon one. On the wrong machine that shows up as controls
    /// that are mysteriously greyed out, so say it once, plainly, instead.
    ///
    /// An older-but-supported macOS gets no dialog: every private interface is
    /// resolved at run time and reported in Settings › System (and by
    /// `pwelumenctl compat`), which is a better answer than a version number.
    private func checkPlatform() {
        Log.error("launch: macOS \(Platform.osVersionString) (\(Platform.buildVersion)) · "
                  + "\(Platform.chipName) · appleSilicon=\(Platform.isAppleSilicon)")
        guard !Platform.isAppleSilicon else { return }

        let key = "intelWarningShown"
        guard !Defaults.shared.bool(forKey: key) else { return }
        Defaults.shared.set(true, forKey: key)

        let alert = NSAlert()
        alert.messageText = L10n.t("PWE Lumen Bar 只支持 Apple Silicon", "PWE Lumen Bar supports Apple Silicon only")
        alert.informativeText = L10n.t(
            "这台 Mac 是 \(Platform.chipName)。DDC/CI 在 PWE Lumen Bar 里走的是 Apple Silicon 专有的 "
            + "IOAVService 通道，Intel 机型上不存在，第三方显示器的亮度、音量、输入源都会不可用。\n\n"
            + "程序仍然可以运行，能用的功能会照常显示，用不了的会置灰。",
            "This Mac is an \(Platform.chipName). PWE Lumen Bar drives DDC/CI over IOAVService, which is "
            + "Apple Silicon only, so brightness, volume and input switching on third-party "
            + "monitors will be unavailable.\n\nThe app still runs: whatever works stays "
            + "available and the rest is greyed out.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.t("知道了", "OK"))
        alert.runModal()
    }

    /// An accessory app never shows a menu bar, but its main menu is still what
    /// supplies ⌘C/⌘V/⌘A and ⌘Q to any window it opens. Without one, the
    /// settings window's text fields would refuse to paste.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit PWE Lumen Bar",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    /// `pwelumen://` automation, reachable from Shortcuts' "Open URLs" action.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let controller else { return }
        for url in urls { URLCommands.handle(url, controller: controller) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Gamma changes outlive the process — never leave a screen dimmed or
        // tinted with no app around to undo it.
        BrightnessEngine.shared.restoreAllGamma()
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// Menu bar only: no Dock tile, no main window.
application.setActivationPolicy(.accessory)
application.run()
