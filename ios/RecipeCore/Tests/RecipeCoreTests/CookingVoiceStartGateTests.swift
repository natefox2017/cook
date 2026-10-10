// Developer: gengyun
// Purpose: Test token-gated microphone startup and stale authorization cancellation.

import Foundation
import Testing

@testable import RecipeCore

@Test
func onlyOneVoiceStartupCanReservePermissionFlow() throws {
    var gate = CookingVoiceStartGate()
    let first = try #require(gate.reserve())

    #expect(gate.reserve() == nil)
    #expect(gate.isCurrent(first))

    #expect(gate.complete(first))
    #expect(!gate.isCurrent(first))
    let second = try #require(gate.reserve())
    #expect(second != first)
}

@Test
func stopDuringAuthorizationInvalidatesInFlightStart() throws {
    var gate = CookingVoiceStartGate()
    let original = try #require(gate.reserve())
    gate.cancel()

    #expect(!gate.isCurrent(original))
    #expect(!gate.complete(original))

    let retry = try #require(gate.reserve())
    #expect(gate.isCurrent(retry))
    #expect(!gate.complete(original))
    #expect(gate.isCurrent(retry))
    #expect(gate.complete(retry))
}

@Test
func stalePermissionCompletionCannotCancelNewerVoiceAttempt() throws {
    var gate = CookingVoiceStartGate()
    let original = try #require(gate.reserve())
    gate.cancel()
    let retry = try #require(gate.reserve())

    #expect(!gate.complete(original))
    #expect(gate.reserve() == nil)
    #expect(gate.isCurrent(retry))
    gate.cancel()
    #expect(!gate.isCurrent(retry))
    #expect(gate.reserve() != nil)
}
