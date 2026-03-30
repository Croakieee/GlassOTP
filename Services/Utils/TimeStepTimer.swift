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

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.now = Date()
        }

        timer?.tolerance = 0.3
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
