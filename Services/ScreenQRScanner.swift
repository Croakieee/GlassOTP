import AppKit
import CoreGraphics

enum ScreenScanError: Error, LocalizedError, Equatable {
    case permissionNeeded
    case cancelled
    case captureFailed
    case nothingFound

    var errorDescription: String? {
        switch self {
        case .permissionNeeded:
            return "GlassOTP needs Screen Recording permission to look for QR codes on the screen."
        case .cancelled:
            return nil
        case .captureFailed:
            return "Couldn't take a screenshot."
        case .nothingFound:
            return "No QR code with an account was found on the screen."
        }
    }
}

enum ScreenQRScanner {
    typealias Capture = (_ selectingArea: Bool, _ files: [URL]) -> Bool

    private static let screencapture = URL(fileURLWithPath: "/usr/sbin/screencapture")
    private static let privacySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    private static let hideDelay: TimeInterval = 0.3

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openPrivacySettings() {
        NSWorkspace.shared.open(privacySettings)
    }

    static func scan(selectingArea: Bool, completion: @escaping (Result<[String], ScreenScanError>) -> Void) {
        capture(selectingArea: selectingArea, hidingWindows: true, read: links(in:), completion: completion)
    }

    static func capture<Value>(selectingArea: Bool, hidingWindows: Bool,
                               read: @escaping ([CGImage]) -> Result<Value, ScreenScanError>,
                               completion: @escaping (Result<Value, ScreenScanError>) -> Void) {
        guard hasPermission else {
            completion(.failure(.permissionNeeded))
            return
        }
        let screens = max(NSScreen.screens.count, 1)
        let hidden = hidingWindows ? NSApp.windows.filter { $0.isVisible && $0.canBecomeKey } : []
        hidden.forEach { $0.orderOut(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + (hidingWindows ? hideDelay : 0)) {
            DispatchQueue.global(qos: .userInitiated).async {
                let result = images(selectingArea: selectingArea, screens: screens, capture: runScreencapture).flatMap(read)
                DispatchQueue.main.async {
                    hidden.forEach { $0.orderFront(nil) }
                    NSApp.activate(ignoringOtherApps: true)
                    hidden.first?.makeKey()
                    completion(result)
                }
            }
        }
    }

    static func links(selectingArea: Bool, screens: Int, capture: Capture) -> Result<[String], ScreenScanError> {
        images(selectingArea: selectingArea, screens: screens, capture: capture).flatMap(links(in:))
    }

    static func images(selectingArea: Bool, screens: Int, capture: Capture) -> Result<[CGImage], ScreenScanError> {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        let stamp = UUID().uuidString
        let files = (0..<(selectingArea ? 1 : screens)).map { folder.appendingPathComponent("GlassOTP-screen-\(stamp)-\($0).png") }
        defer { files.forEach { try? FileManager.default.removeItem(at: $0) } }

        let finished = capture(selectingArea, files)
        let images = files.compactMap { NSImage(contentsOf: $0)?.cgImage() }
        guard !images.isEmpty else { return .failure(selectingArea ? .cancelled : .captureFailed) }
        guard finished else { return .failure(.captureFailed) }
        return .success(images)
    }

    static func links(in images: [CGImage]) -> Result<[String], ScreenScanError> {
        var found: [String] = []
        for image in images {
            for link in (try? QRService.scanAllOtpauth(from: image)) ?? [] where !found.contains(link) {
                found.append(link)
            }
        }
        return found.isEmpty ? .failure(.nothingFound) : .success(found)
    }

    private static func runScreencapture(selectingArea: Bool, files: [URL]) -> Bool {
        let process = Process()
        process.executableURL = screencapture
        process.arguments = (selectingArea ? ["-i", "-x", "-t", "png"] : ["-x", "-t", "png"]) + files.map(\.path)
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
