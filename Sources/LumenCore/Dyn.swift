import Foundation

/// Runtime resolution of private/undocumented symbols.
///
/// Everything Lumen needs beyond the public CoreGraphics surface is looked up
/// lazily at run time. If Apple renames or removes a symbol in a future macOS,
/// the corresponding capability degrades to "unsupported" instead of taking the
/// whole app down at launch with a dyld error.
public enum Dyn {
    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

    private static var openedHandles: [String: UnsafeMutableRawPointer] = [:]
    private static let lock = NSLock()

    /// Load a framework by absolute path so its symbols become visible to `symbol(_:as:)`.
    @discardableResult
    public static func load(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if openedHandles[path] != nil { return true }
        guard let handle = dlopen(path, RTLD_LAZY) else {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown"
            Log.debug("dlopen failed for \(path): \(reason)")
            return false
        }
        openedHandles[path] = handle
        return true
    }

    /// Look up a C function and reinterpret it as the given Swift `@convention(c)` type.
    public static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let pointer = dlsym(rtldDefault, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    public static func has(_ name: String) -> Bool {
        dlsym(rtldDefault, name) != nil
    }
}
