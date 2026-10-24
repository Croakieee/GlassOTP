import AppKit

extension StatusBarController: NSWindowDelegate {
    private static let dropTypes: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .tiff, .png]
    private static let dropSetupAttempts = 5

    func installDropTarget(attempt: Int = 0) {
        guard let window = statusItem.button?.window else {
            guard attempt < Self.dropSetupAttempts else { return }
            DispatchQueue.main.async { [weak self] in self?.installDropTarget(attempt: attempt + 1) }
            return
        }
        window.registerForDraggedTypes(Self.dropTypes)
        window.delegate = self
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: Self.dropTypes) != nil else { return [] }
        statusItem.button?.highlight(true)
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        statusItem.button?.highlight(false)
    }

    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        statusItem.button?.highlight(false)
        let payload = QuickAddPayload.read(from: sender.draggingPasteboard)
        guard !payload.isEmpty else { return false }
        quickAdd(payload)
        return true
    }

    func concludeDragOperation(_ sender: NSDraggingInfo?) {
        statusItem.button?.highlight(false)
    }
}
