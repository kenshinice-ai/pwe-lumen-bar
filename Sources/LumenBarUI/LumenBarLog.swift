import Foundation
import LumenBarCore

enum LumenBarLog {
    static func loginItemFailure(_ error: Error) {
        Log.error("login item registration failed: \(error.localizedDescription)")
    }
}
