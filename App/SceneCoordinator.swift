import AppKit
import SwiftUI

final class SceneCoordinator {
    let popover: NSPopover

    init<Content: View>(rootView: Content) {
        self.popover = NSPopover()
        self.popover.behavior = .transient // закрывается при клике вне
        self.popover.animates = true

        // Оборачиваем SwiftUI во вью-контроллер
        let hosting = NSHostingController(rootView: rootView)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        // Контроллер для поповера
        let containerVC = NSViewController()
        containerVC.view = NSView()
        containerVC.view.wantsLayer = true

        containerVC.addChild(hosting)
        containerVC.view.addSubview(hosting.view)

        // Констрейнты: задаём желаемый размер поповера
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: containerVC.view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: containerVC.view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: containerVC.view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: containerVC.view.bottomAnchor),
            containerVC.view.widthAnchor.constraint(equalToConstant: 380),
            containerVC.view.heightAnchor.constraint(equalToConstant: 460)
        ])

        self.popover.contentViewController = containerVC
    }
}
