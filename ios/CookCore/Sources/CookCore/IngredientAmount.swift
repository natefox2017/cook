import Foundation

/// A local cooking value, not an API DTO. No text parser infers a number or unit.
public struct IngredientAmount: Equatable, Sendable {
    public let originalText: String
    public let value: Decimal?
    public let unit: String?

    public enum ValidationError: Error, Equatable {
        case invalidValue
        case invalidScale
        case arithmeticFailure
    }

    /// Callers provide a numeric value only when the source or user establishes it.
    public init(originalText: String, value: Decimal? = nil, unit: String? = nil) throws {
        if let value, value.isNaN || value < 0 {
            throw ValidationError.invalidValue
        }
        self.originalText = originalText
        self.value = value
        self.unit = unit
    }

    /// Keeps unknown amounts and original evidence intact; never converts units.
    public func scaled(by factor: Decimal) throws -> IngredientAmount {
        guard !factor.isNaN, factor > 0 else { throw ValidationError.invalidScale }
        guard var value else { return self }
        var factor = factor
        var result = Decimal()
        guard NSDecimalMultiply(&result, &value, &factor, .plain) == .noError else {
            throw ValidationError.arithmeticFailure
        }
        return try IngredientAmount(originalText: originalText, value: result, unit: unit)
    }
}

extension IngredientAmount.ValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidValue:
            "Ingredient amounts must be finite numbers of zero or more."
        case .invalidScale:
            "Choose a positive, finite serving multiplier."
        case .arithmeticFailure:
            "This amount cannot be calculated without losing precision. Keep the original amount or edit it."
        }
    }
}
