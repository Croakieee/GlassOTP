import Foundation
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()

    private let pinKey = "GlassOTP.pinPopover"

    @Published var pinPopover: Bool {
        didSet { UserDefaults.standard.set(pinPopover, forKey: pinKey) }
    }

    private init() {
        self.pinPopover = UserDefaults.standard.bool(forKey: pinKey)
    }
}
