import Foundation

/// Serializes hardware writes off the main thread.
///
/// A DDC write costs tens of milliseconds and the I2C bus tolerates exactly one
/// conversation at a time, so dragging a slider must not turn into a queue of
/// hundreds of writes. Values coalesce: only the latest one for a given control
/// is ever sent.
final class HardwareQueue {
    static let shared = HardwareQueue()

    private let queue = DispatchQueue(label: "com.pwegroup.pwelumenbar.hardware", qos: .userInitiated)
    private var pending: [String: Double] = [:]
    private var scheduled: Set<String> = []
    private let lock = NSLock()

    private init() {}

    func run(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    /// Latest-value-wins. `work` runs at most once per `interval` per key.
    func coalesce(key: String, value: Double,
                  interval: TimeInterval = 0.05,
                  _ work: @escaping (Double) -> Void) {
        lock.lock()
        pending[key] = value
        let alreadyScheduled = scheduled.contains(key)
        if !alreadyScheduled { scheduled.insert(key) }
        lock.unlock()

        guard !alreadyScheduled else { return }
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let latest = self.pending.removeValue(forKey: key)
            self.scheduled.remove(key)
            self.lock.unlock()
            if let latest { work(latest) }
        }
    }
}
