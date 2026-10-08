// Developer: gengyun
// Purpose: Tests cooking timer start, pause, reset, and deadline behavior.

import Foundation
import Testing
@testable import RecipeCore

@Test
func deadlineTimerDoesNotDependOnTicksAndSupportsPauseResume() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    var timer = CookingTimer(durationSeconds: 60)
    timer.start(at: start)
    #expect(timer.isRunning)
    #expect(timer.remaining(at: start.addingTimeInterval(21.2)) == 39)
    timer.pause(at: start.addingTimeInterval(22.2))
    #expect(!timer.isRunning)
    #expect(timer.remainingSeconds == 38)
    #expect(timer.remaining(at: start.addingTimeInterval(90)) == 38)
    timer.start(at: start.addingTimeInterval(100))
    #expect(timer.deadline == start.addingTimeInterval(138))
    timer.start(at: start.addingTimeInterval(110))
    #expect(timer.deadline == start.addingTimeInterval(138))
    let restored = try JSONDecoder().decode(CookingTimer.self, from: JSONEncoder().encode(timer))
    #expect(restored == timer)
    #expect(restored.remaining(at: start.addingTimeInterval(120)) == 18)
    #expect(restored.remaining(at: start.addingTimeInterval(1000)) == 0)
    // Completion does not mutate a recipe, step or stored deadline.
    #expect(timer.deadline == start.addingTimeInterval(138))
    timer.reset()
    #expect(!timer.isRunning)
    #expect(timer.remainingSeconds == 60)
}

@Test
func timerHandlesZeroClockReversalAndRestart() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    var zero = CookingTimer(durationSeconds: -1)
    zero.start(at: start)
    #expect(!zero.isRunning)
    #expect(zero.remaining(at: start) == 0)
    var timer = CookingTimer(durationSeconds: 10)
    timer.start(at: start)
    #expect(timer.remaining(at: start.addingTimeInterval(-100)) == 10)
    #expect(timer.remaining(at: start.addingTimeInterval(10)) == 0)
    timer.pause(at: start.addingTimeInterval(30))
    timer.start(at: start.addingTimeInterval(40))
    #expect(timer.deadline == start.addingTimeInterval(50))
}
