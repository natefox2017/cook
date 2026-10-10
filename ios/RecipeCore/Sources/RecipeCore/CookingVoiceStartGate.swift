// Developer: gengyun
// Purpose: Ignore stale asynchronous voice-listening permission completions.

import Foundation

/// A controller reserves one token before asking iOS for Speech or mic access.
/// A cancellation makes delayed permission callbacks inert, even after a retry.
public struct CookingVoiceStartGate: Sendable {
    private var pending: UUID?

    public init() {}

    public mutating func reserve() -> UUID? {
        guard pending == nil else { return nil }
        let token = UUID()
        pending = token
        return token
    }

    public func isCurrent(_ token: UUID) -> Bool {
        pending == token
    }

    @discardableResult
    public mutating func complete(_ token: UUID) -> Bool {
        guard pending == token else { return false }
        pending = nil
        return true
    }

    public mutating func cancel() {
        pending = nil
    }
}
