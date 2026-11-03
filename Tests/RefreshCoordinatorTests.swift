import Foundation

@main struct RefreshCoordinatorTests {
    static func main() {
        var callbacks: [(Result<Quota, Error>) -> Void] = []
        var intervals: [TimeInterval] = []
        var timer: (() -> Void)?
        var cancelled = false
        var starts = 0, finishes = 0
        let coordinator = RefreshCoordinator(fetch: { callbacks.append($0) }, cancelFetch: { cancelled = true }, schedule: { interval, action in intervals.append(interval); timer = action }, cancelTimer: { timer = nil })
        coordinator.onStart = { starts += 1 }
        coordinator.onFinish = { _ in finishes += 1 }
        let quota = Quota(windows: [], conflictingDurations: [])
        coordinator.refresh(); coordinator.refresh()
        precondition(starts == 1 && coordinator.running)
        coordinator.changed(); coordinator.changed()
        callbacks.removeFirst()(.success(quota))
        precondition(starts == 2 && finishes == 1 && intervals.isEmpty)
        callbacks.removeFirst()(.failure(QuotaError.timeout))
        precondition(intervals == [360] && !coordinator.running)
        timer?(); precondition(starts == 3)
        callbacks.removeFirst()(.success(quota))
        precondition(intervals == [360, 180])
        coordinator.changed(); precondition(starts == 4 && timer == nil)
        coordinator.stop(); callbacks.removeFirst()(.success(quota))
        coordinator.changed(); coordinator.refresh()
        precondition(cancelled && starts == 4 && finishes == 3 && !coordinator.running && timer == nil)
        print("Refresh coordinator tests passed")
    }
}
