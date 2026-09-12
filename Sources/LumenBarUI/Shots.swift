import AppKit
import LumenBarCore
import SwiftUI

/// Renders the welcome window to a PNG, in both appearances.
///
/// This is the brand check. The wing is drawn from imported geometry through a
/// coordinate system that flips between AppKit and SwiftUI, and the accent has
/// to swap between amber and deep amber with the appearance — both are the kind
/// of thing that looks fine in code and wrong on screen, and neither shows up in
/// a build log. Rendering the real view is the only way to see it.
///
/// It is deliberately only this window. `ImageRenderer` cannot draw AppKit-backed
/// controls — sliders, pickers and menus come out as placeholder tiles — so the
/// panel and the settings window have to be captured from the running app.
///
/// Re-tested on macOS 26.6 (2026-09-12), because the main surface having no check at all is
/// worth ten minutes to recheck: still placeholder tiles. The panel's header and empty state
/// do render, but a shot that draws a third of the panel and leaves the display list blank is
/// worse than no shot — it looks like the bug it is not.
@MainActor
public enum Shots {

    public static func renderWelcome(to url: URL, dark: Bool = false, scale: CGFloat = 2) throws {
        let controller = DisplayController(previewCards: PreviewData.sampleCards())
        // Both halves are needed. The environment is what SwiftUI's own views
        // read; `NSAppearance.current` is what a dynamic `NSColor` — which is how
        // Brand.accent keeps amber off a paper ground — resolves against.
        NSAppearance.current = NSAppearance(named: dark ? .darkAqua : .aqua)
        // The window supplies its own ground; a rendered view has none, and white
        // text on nothing is not a screenshot.
        let renderer = ImageRenderer(content: WelcomeView(controller: controller, onDismiss: {})
                                        .background(Color(nsColor: .windowBackgroundColor))
                                        .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try png.write(to: url)
    }
}
