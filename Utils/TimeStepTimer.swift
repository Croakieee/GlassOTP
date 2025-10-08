import Foundation

/// Таймер на GCD, тикает раз в 1 сек и не "залипает" при transient-поповере
final class TimeStepTimer: ObservableObject {
    @Published var now: Date = Date()

    private var timer: DispatchSourceTimer?

    init() {
        start()
    }

    deinit {
        stop()
    }

    private func start() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        t.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in
            self?.now = Date()
        }
        t.resume()
        self.timer = t
    }

    private func stop() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }
}
