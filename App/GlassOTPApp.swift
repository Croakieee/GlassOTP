import SwiftUI
import AppKit

@main
struct GlassOTPApp: App {
    // Маковский AppDelegate для статуса/поповера
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Обычных окон не создаём — всё живёт в статус-баре.
        Settings {
            // В будущем пихуйнуть сюда настройки.
            EmptyView()
        }
    }
}
