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

@Test
func legacyCookingTimerJSONKeepsPausedRemainingTime() throws {
    let data = Data(
        #"{"durationSeconds":60,"remainingSeconds":42}"#.utf8
    )

    let restored = try JSONDecoder().decode(CookingTimer.self, from: data)

    #expect(!restored.isRunning)
    #expect(restored.remainingSeconds == 42)
}

@Test
func legacyRecipeStepDurationKeepsItsStepIDAsTimerID() throws {
    let stepID = UUID(uuidString: "C0050000-0000-4000-8000-000000000001")!
    let json = """
        {
            "id": "\(stepID.uuidString)",
            "title": "Boil",
            "instruction": "Boil water.",
            "durationSeconds": 300
        }
        """

    let restored = try JSONDecoder().decode(RecipeStep.self, from: Data(json.utf8))

    #expect(restored.timers.count == 1)
    #expect(restored.timers[0].id == stepID)
    #expect(restored.timers[0].durationSeconds == 300)
}

@Test
func roastChickenSampleStepIDsAreDeterministic() throws {
    let firstRecipe = try #require(
        SampleRecipes.recipes.first { $0.id == SampleRecipes.roastChickenID }
    )
    let secondRecipe = try #require(
        SampleRecipes.recipes.first { $0.id == SampleRecipes.roastChickenID }
    )
    let firstStepIDs = firstRecipe.steps.map(\.id)

    #expect(firstStepIDs.count == 8)
    #expect(Set(firstStepIDs).count == firstStepIDs.count)
    #expect(secondRecipe.steps.map(\.id) == firstStepIDs)
}

@Test
func reminderWarningUsesDeadlineAndSkipsShortPausedOrExpiredTimers() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var timer = CookingTimer(durationSeconds: 120)
    timer.start(at: now)
    let plan = CookingReminderPlan(timer: timer, warningSeconds: 30, now: now)
    #expect(plan?.deadline == now.addingTimeInterval(120))
    #expect(plan?.earlyWarningAt == now.addingTimeInterval(90))
    #expect(
        CookingReminderPlan(
            timer: timer, warningSeconds: 30, now: now.addingTimeInterval(92)
        )?.earlyWarningAt == nil
    )
    #expect(CookingReminderPlan(timer: timer, warningSeconds: 0, now: now)?.earlyWarningAt == nil)
    timer.pause(at: now.addingTimeInterval(40))
    #expect(CookingReminderPlan(timer: timer, warningSeconds: 30, now: now) == nil)
    timer.start(at: now.addingTimeInterval(50))
    #expect(
        CookingReminderPlan(timer: timer, warningSeconds: 60, now: now.addingTimeInterval(85))?
            .earlyWarningAt == nil
    )
}
