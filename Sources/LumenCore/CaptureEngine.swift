import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Per-display screen capture.
///
/// macOS's own ⌘⇧3 captures every display at once; picking one by name is the
/// thing a display utility is in a position to do. Built on ScreenCaptureKit
/// because `CGDisplayCreateImage` is deprecated and now returns nothing useful.
public enum CaptureEngine {

    public enum CaptureError: LocalizedError {
        case noPermission
        case displayUnavailable
        case captureFailed(String)
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noPermission:
                return L10n.t("需要「屏幕录制」权限。已打开系统设置，勾选 Lumen 后重试。",
                              "Screen Recording permission is required. System Settings has been opened — tick Lumen, then try again.")
            case .displayUnavailable:
                return L10n.t("这块屏当前无法截取。", "This display cannot be captured right now.")
            case .captureFailed(let reason):
                return L10n.t("截图失败：\(reason)", "Capture failed: \(reason)")
            case .writeFailed(let reason):
                return L10n.t("保存失败：\(reason)", "Could not save: \(reason)")
            }
        }
    }

    // MARK: - Permission

    public static var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Raises the system prompt once; afterwards macOS only shows the settings
    /// pane, so open it directly for the user rather than leaving them hunting.
    public static func requestPermission() {
        if !CGRequestScreenCaptureAccess() {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Capture

    public static func capture(_ display: DisplayInfo) async throws -> CGImage {
        guard hasPermission else {
            requestPermission()
            throw CaptureError.noPermission
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }

        guard let target = content.displays.first(where: { $0.displayID == display.id }) else {
            throw CaptureError.displayUnavailable
        }

        let configuration = SCStreamConfiguration()
        // Capture at the framebuffer's real pixel size, not the layout size —
        // a HiDPI screenshot that comes back at point resolution is half wasted.
        if let mode = display.currentMode {
            configuration.width = mode.pixelWidth
            configuration.height = mode.pixelHeight
        } else {
            configuration.width = target.width
            configuration.height = target.height
        }
        configuration.showsCursor = false
        configuration.captureResolution = .best

        let filter = SCContentFilter(display: target, excludingWindows: [])
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                              configuration: configuration)
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }

    // MARK: - Output

    public static func pngData(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    @discardableResult
    public static func copyToPasteboard(_ image: CGImage) -> Bool {
        guard let data = pngData(from: image) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: .png)
    }

    /// Saves where macOS puts its own screenshots, with the display's name in
    /// the filename so a multi-monitor capture set stays sortable.
    public static func save(_ image: CGImage, display: DisplayInfo,
                            to directory: URL? = nil) throws -> URL {
        guard let data = pngData(from: image) else {
            throw CaptureError.writeFailed("PNG encoding")
        }
        let folder = directory
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let safeName = display.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = folder.appendingPathComponent(
            "Lumen \(safeName) \(formatter.string(from: Date())).png")

        do {
            try data.write(to: url)
        } catch {
            throw CaptureError.writeFailed(error.localizedDescription)
        }
        Log.info("captured \(display.name) → \(url.lastPathComponent)")
        return url
    }
}
