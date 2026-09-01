import AppKit
import Foundation
import LumenBarUI

// Renders the welcome window for the documentation and for checking the brand:
//
//     swift run pwelumenshots docs/images
//
// Writes welcome-light.png and welcome-dark.png. A development tool; it is not
// part of the app.

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
              ? CommandLine.arguments[1] : "docs/images")

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    do {
        for (name, dark) in [("welcome-light.png", false), ("welcome-dark.png", true)] {
            app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            try Shots.renderWelcome(to: out.appendingPathComponent(name), dark: dark)
        }
        print("wrote welcome-light.png and welcome-dark.png to \(out.path)")
    } catch {
        FileHandle.standardError.write("failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
