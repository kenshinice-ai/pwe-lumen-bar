import Foundation
import ServiceManagement

/// Launch at login, via the modern per-app registration.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration fails for a bundle running outside /Applications;
            // not worth an alert, but worth a trace.
            LumenBarLog.loginItemFailure(error)
        }
    }
}
