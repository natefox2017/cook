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

@Test
func multipleTimersRestoreIndependentlyAfterBackgroundElapsed() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    var oven = CookingTimer(durationSeconds: 900)
    var rice = CookingTimer(durationSeconds: 120)
    oven.start(at: start)
    rice.start(at: start.addingTimeInterval(20))

    // Encode running deadlines as if the app were terminated before completion.
    let saved = try JSONEncoder().encode([oven, rice])
    let restored = try JSONDecoder().decode([CookingTimer].self, from: saved)
    #expect(restored.count == 2)
    #expect(restored[0].remaining(at: start.addingTimeInterval(150)) == 750)
    #expect(restored[1].remaining(at: start.addingTimeInterval(150)) == 0)
    #expect(restored[1].isRunning)

    // Only an explicit restart resets a completed timer; the sibling is unchanged.
    var restartedRice = restored[1]
    restartedRice.start(at: start.addingTimeInterval(151))
    #expect(restartedRice.deadline == start.addingTimeInterval(271))
    #expect(restored[0].deadline == start.addingTimeInterval(900))
}

@Test
func pausedTimerStaysPausedWhileSiblingExpiresAcrossRestoration() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    var short = CookingTimer(durationSeconds: 60)
    var long = CookingTimer(durationSeconds: 600)
    short.start(at: start)
    long.start(at: start)
    short.pause(at: start.addingTimeInterval(20.5))

    let data = try JSONEncoder().encode([short, long])
    var restored = try JSONDecoder().decode([CookingTimer].self, from: data)
    #expect(!restored[0].isRunning)
    #expect(restored[0].remaining(at: start.addingTimeInterval(1_000)) == 40)
    #expect(restored[1].remaining(at: start.addingTimeInterval(1_000)) == 0)
    restored[1].reset()
    #expect(restored[1].remaining(at: start.addingTimeInterval(1_000)) == 600)
    #expect(restored[0].remainingSeconds == 40)
    restored[0].start(at: start.addingTimeInterval(1_000))
    #expect(restored[0].deadline == start.addingTimeInterval(1_040))
}
