import Foundation

// A wall-clock deadline avoids timer drift and catches up after app suspension.
struct CookingTimer: Equatable {
    private(set) var duration: TimeInterval
    private(set) var pausedRemaining: TimeInterval
    private(set) var deadline: Date?
    private(set) var finished = false

    init(seconds: Int) {
        duration = TimeInterval(max(0, seconds))
        pausedRemaining = duration
    }
    var running: Bool { deadline != nil }
    func remaining(at now: Date) -> TimeInterval {
        deadline.map { max(0, $0.timeIntervalSince(now)) } ?? pausedRemaining
    }
    mutating func start(at now: Date) {
        guard duration > 0 else { return }
        let remaining = finished ? duration : pausedRemaining
        deadline = now.addingTimeInterval(remaining)
        finished = false
    }
    mutating func pause(at now: Date) {
        guard deadline != nil else { return }
        pausedRemaining = remaining(at: now)
        deadline = nil
        finished = pausedRemaining == 0
    }
    mutating func tick(at now: Date) {
        if let deadline, now >= deadline {
            self.deadline = nil
            pausedRemaining = 0
            finished = true
        }
    }
    mutating func reset() {
        deadline = nil
        pausedRemaining = duration
        finished = false
    }
}
