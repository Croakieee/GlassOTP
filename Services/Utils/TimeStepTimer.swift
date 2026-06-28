import Foundation

final class TimeStepTimer: ObservableObject {
    @Published var now: Date = Date()

    private var timer: Timer?

    init() {
        start()
    }

    deinit {
        stop()
    }

    private func start() {

        // Refresh immediately: the scheduled timer's first fire is up to 1s away, and after a
        // pause/resume (popover reopen) or sleep `now` is otherwise stale, briefly showing the
        // code/countdown from when the timer was last running.
        now = Date()

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
        t.tolerance = 0.3
        // .common keeps the countdown ticking during menu tracking / scrolling,
        // which a default-mode scheduled timer would pause.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
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
