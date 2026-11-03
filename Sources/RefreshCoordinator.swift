import Foundation

// All methods and callbacks are used on the main queue.
final class RefreshCoordinator {
    typealias Fetch = (@escaping (Result<Quota, Error>) -> Void) -> Void
    private let fetch: Fetch
    private let cancelFetch: () -> Void
    private let scheduleTimer: (TimeInterval, @escaping () -> Void) -> Void
    private let cancelTimer: () -> Void
    private var schedule = RefreshSchedule()
    private var pending = false
    private var stopped = false
    private var generation = 0
    private(set) var running = false
    var onStart: (() -> Void)?
    var onFinish: ((Result<Quota, Error>) -> Void)?

    init(fetch: @escaping Fetch, cancelFetch: @escaping () -> Void,
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void,
         cancelTimer: @escaping () -> Void) {
        self.fetch = fetch; self.cancelFetch = cancelFetch
        self.scheduleTimer = schedule; self.cancelTimer = cancelTimer
    }

    func refresh() {
        guard !stopped, !running else { return }
        cancelTimer(); running = true; generation += 1
        let request = generation
        onStart?()
        fetch { [weak self] result in
            guard let self = self, !self.stopped, self.generation == request else { return }
            self.running = false
            self.onFinish?(result)
            guard !self.stopped else { return }
            let interval: TimeInterval
            switch result { case .success: interval = self.schedule.record(success: true); case .failure: interval = self.schedule.record(success: false) }
            if self.pending { self.pending = false; self.refresh() }
            else { self.scheduleTimer(interval) { [weak self] in self?.refresh() } }
        }
    }

    func changed() {
        guard !stopped else { return }
        if running { pending = true } else { refresh() }
    }

    func stop() {
        stopped = true; generation += 1; pending = false; running = false
        cancelTimer(); cancelFetch()
    }
}
