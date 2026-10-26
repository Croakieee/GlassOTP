import AppKit
import LocalAuthentication

enum DeviceAuth {
    static func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        authenticate(reason: reason, context: LAContext(), onUnavailable: showUnavailable, completion: completion)
    }

    static func authenticate(reason: String, context: LAContext,
                             onUnavailable: (NSError?) -> Void,
                             completion: @escaping (Bool) -> Void) {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            onUnavailable(error)
            completion(false)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    static func unavailableMessage(for error: NSError?) -> String {
        if error?.code == LAError.passcodeNotSet.rawValue {
            return "Your Mac has no login password, so GlassOTP can't confirm it's you. Set a password in System Settings → Users & Groups, then try again."
        }
        let reason = error?.localizedDescription ?? "Unknown error."
        return "macOS couldn't start Touch ID or password verification, so GlassOTP kept your data locked. \(reason)"
    }

    private static func showUnavailable(_ error: NSError?) {
        let alert = NSAlert()
        alert.messageText = "Can't verify it's you"
        alert.informativeText = unavailableMessage(for: error)
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
