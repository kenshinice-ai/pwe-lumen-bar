import Foundation
import LumenCore

enum LumenLog {
    static func loginItemFailure(_ error: Error) {
        Log.error("login item registration failed: \(error.localizedDescription)")
    }
}
