import CoreGraphics
import Foundation
import LumenBarCore

/// Staged displays for rendering the menu without the hardware attached.
///
/// The two-display case is the one worth looking at while designing the menu,
/// and it cannot be seen on a laptop with nothing plugged in.
public enum PreviewData {

    public static func sampleCards() -> [DisplayCard] {
        [builtInCard(), externalCard()]
    }

    static func mode(_ width: Int, _ height: Int, scale: Int, hz: Double, dpi: Int) -> DisplayMode {
        DisplayMode(id: "preview:\(width)x\(height)@\(scale)",
                    cgsNumber: nil, cgMode: nil,
                    width: width, height: height,
                    pixelWidth: width * scale, pixelHeight: height * scale,
                    refreshRate: hz, ioFlags: 0x1, dpi: dpi, usableForDesktop: true)
    }

    static func builtInCard() -> DisplayCard {
        let current = mode(1440, 900, scale: 2, hz: 60, dpi: 255)
        var card = DisplayCard(info: DisplayInfo(
            id: 1, name: "Built-in Retina Display", isBuiltin: true, isMain: true,
            vendor: 1552, model: 41033, serial: 0, unitNumber: 0,
            bounds: CGRect(x: 0, y: 0, width: 1440, height: 900),
            rotation: .zero, backingScale: 2, currentMode: current, mirrorSource: 0))
        card.brightness = 0.89
        card.brightnessChannel = .displayServices
        card.volume = 0.61
        card.volumeChannel = .coreAudio
        card.audioDeviceName = "MacBook Pro Speakers"
        card.currentMode = current
        card.recommendedModes = [
            mode(1680, 1050, scale: 2, hz: 60, dpi: 298),
            current,
            mode(1280, 800, scale: 2, hz: 60, dpi: 227),
            mode(1024, 640, scale: 2, hz: 60, dpi: 182),
        ]
        card.allModes = card.recommendedModes
        card.rotationSupported = false
        card.isLoaded = true
        return card
    }

    static func externalCard() -> DisplayCard {
        let current = mode(2560, 1440, scale: 2, hz: 144, dpi: 109)
        var card = DisplayCard(info: DisplayInfo(
            id: 2, name: "LG UltraFine 4K", isBuiltin: false, isMain: false,
            vendor: 7789, model: 23456, serial: 12345, unitNumber: 1,
            bounds: CGRect(x: 1440, y: 0, width: 2560, height: 1440),
            rotation: .ninety, backingScale: 2, currentMode: current, mirrorSource: 0))
        card.brightness = 0.55
        card.brightnessChannel = .ddc
        card.volume = 0.30
        card.volumeChannel = .ddc
        card.audioDeviceName = "LG UltraFine 4K"
        card.currentMode = current
        card.recommendedModes = [
            mode(3840, 2160, scale: 1, hz: 144, dpi: 163),
            current,
            mode(1920, 1080, scale: 2, hz: 144, dpi: 82),
        ]
        card.allModes = card.recommendedModes
        card.refreshOptions = [current, mode(2560, 1440, scale: 2, hz: 60, dpi: 109)]
        card.rotationSupported = true
        card.hasDDC = true
        card.isLoaded = true
        return card
    }
}
