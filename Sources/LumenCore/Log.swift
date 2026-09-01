import Foundation
import os

/// Logging.
///
/// Unified logging turned out to be unreliable here — an ad-hoc signed menu bar
/// app produced no entries at all under `log show`, which makes diagnosing a
/// user's machine impossible. So everything also goes to a plain file the user
/// can hand over: `~/Library/Logs/Lumen/lumen.log`.
public enum Log {
    private static let logger = Logger(subsystem: "com.leeliu.lumen", category: "core")

    /// Mirrored to stderr so `lumenctl --verbose` shows the same trace.
    public static var echoToStderr = false

    public static let fileURL: URL = {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Lumen", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("lumen.log")
    }()

    private static let fileQueue = DispatchQueue(label: "com.leeliu.lumen.log")
    private static let maximumBytes = 512 * 1024
    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static func write(_ level: String, _ text: String) {
        let line = "\(timestamp.string(from: Date())) \(level) \(text)\n"
        fileQueue.async {
            // Truncate rather than grow without bound; this is a diagnostic
            // aid, not an audit trail.
            if let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
               size > maximumBytes {
                try? FileManager.default.removeItem(at: fileURL)
            }
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    public static func debug(_ message: @autoclosure () -> String) {
        let text = message()
        logger.debug("\(text, privacy: .public)")
        write("DEBUG", text)
        if echoToStderr { FileHandle.standardError.write("· \(text)\n".data(using: .utf8)!) }
    }

    public static func info(_ message: @autoclosure () -> String) {
        let text = message()
        logger.info("\(text, privacy: .public)")
        write("INFO ", text)
        if echoToStderr { FileHandle.standardError.write("· \(text)\n".data(using: .utf8)!) }
    }

    public static func error(_ message: @autoclosure () -> String) {
        let text = message()
        logger.error("\(text, privacy: .public)")
        write("ERROR", text)
        if echoToStderr { FileHandle.standardError.write("!! \(text)\n".data(using: .utf8)!) }
    }
}
