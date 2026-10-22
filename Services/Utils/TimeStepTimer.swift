import Foundation

final class TimeStepTimer: ObservableObject {
    @Published var now: Date = Date()

    private static let boundaryOffset: TimeInterval = 0.03

    private var timer: Timer?
    private var activity: NSObjectProtocol?

    init() {
        start()
    }

    deinit {
        stop()
    }

    private func start() {

        now = Date()
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Live OTP countdown"
        )
        scheduleNextTick()
    }

    private func scheduleNextTick() {
        let current = Date().timeIntervalSince1970
        let delay = current.rounded(.down) + 1 + Self.boundaryOffset - current
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.now = Date()
            self.scheduleNextTick()
        }
        t.tolerance = 0.01
        // .common keeps the countdown ticking during menu tracking / scrolling,
        // which a default-mode scheduled timer would pause.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    func resume() {
        if timer == nil {
            start()
        }
    }

    func pause() {
        stop()
    }

}
