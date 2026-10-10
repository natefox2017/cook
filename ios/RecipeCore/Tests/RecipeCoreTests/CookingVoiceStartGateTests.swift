// Developer: gengyun
// Purpose: Test token-gated microphone startup and stale authorization cancellation.

import Foundation
import Testing

@testable import RecipeCore

@Test
func onlyOneVoiceStartupCanReservePermissionFlow() throws {
    var gate = CookingVoiceStartGate()
    let firstReservation = gate.reserve()
    let first = try #require(firstReservation)

    let duplicateReservation = gate.reserve()
    #expect(duplicateReservation == nil)
    #expect(gate.isCurrent(first))

    let completedFirst = gate.complete(first)
    #expect(completedFirst)
    #expect(!gate.isCurrent(first))

    let secondReservation = gate.reserve()
    let second = try #require(secondReservation)
    #expect(second != first)
}

@Test
func stopDuringAuthorizationInvalidatesInFlightStart() throws {
    var gate = CookingVoiceStartGate()
    let firstReservation = gate.reserve()
    let original = try #require(firstReservation)
    gate.cancel()

    #expect(!gate.isCurrent(original))
    let staleCompletion = gate.complete(original)
    #expect(!staleCompletion)

    let retryReservation = gate.reserve()
    let retry = try #require(retryReservation)
    #expect(gate.isCurrent(retry))

    let replayCompletion = gate.complete(original)
    #expect(!replayCompletion)
    #expect(gate.isCurrent(retry))

    let retryCompleted = gate.complete(retry)
    #expect(retryCompleted)
}

@Test
func stalePermissionCompletionCannotCancelNewerVoiceAttempt() throws {
    var gate = CookingVoiceStartGate()
    let firstReservation = gate.reserve()
    let original = try #require(firstReservation)
    gate.cancel()

    let retryReservation = gate.reserve()
    let retry = try #require(retryReservation)
    let staleCompletion = gate.complete(original)
    #expect(!staleCompletion)

    let overlappingReservation = gate.reserve()
    #expect(overlappingReservation == nil)
    #expect(gate.isCurrent(retry))

    gate.cancel()
    #expect(!gate.isCurrent(retry))

    let newReservation = gate.reserve()
    #expect(newReservation != nil)
}
