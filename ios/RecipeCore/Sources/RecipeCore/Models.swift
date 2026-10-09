// Developer: gengyun
// Purpose: Implements Models for the Recipe iOS app.

import Foundation

public enum RecipeCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case meals = "Meals"
    case breakfast = "Breakfast"
    case desserts = "Desserts"
    case drinks = "Drinks"
    case sides = "Sides"
    public var id: String { rawValue }
}

public enum GroceryCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case produce = "Produce"
    case proteins = "Proteins"
    case dairy = "Dairy & eggs"
    case pantry = "Pantry"
    case other = "Other"
    public var id: String { rawValue }
}

public enum MealSlot: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    public var id: String { rawValue }
}

public enum AppAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    public var id: String { rawValue }
}

public struct Recipe: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var summary: String
    public var category: RecipeCategory
    public var servings: Int?
    public var prepMinutes: Int?
    public var cookMinutes: Int?
    public var ingredients: [RecipeIngredient]
    public var steps: [RecipeStep]
    public var sourceURL: String?
    public var sourceText: String?
    public var sourceName: String?
    public var importRecord: RecipeImportRecord?
    public var coverData: Data?
    public var coverAsset: String?
    public var isFavorite: Bool
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(), title: String, summary: String = "",
        category: RecipeCategory = .meals, servings: Int? = 2,
        prepMinutes: Int? = nil, cookMinutes: Int? = nil,
        ingredients: [RecipeIngredient] = [], steps: [RecipeStep] = [],
        sourceURL: String? = nil, sourceText: String? = nil, sourceName: String? = nil,
        importRecord: RecipeImportRecord? = nil,
        coverData: Data? = nil, coverAsset: String? = nil,
        isFavorite: Bool = false, notes: String = "",
        createdAt: Date = .now, updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.category = category
        self.servings = servings
        self.prepMinutes = prepMinutes
        self.cookMinutes = cookMinutes
        self.ingredients = ingredients
        self.steps = steps
        self.sourceURL = sourceURL
        self.sourceText = sourceText
        self.sourceName = sourceName
        self.importRecord = importRecord
        self.coverData = coverData
        self.coverAsset = coverAsset
        self.isFavorite = isFavorite
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var needsReview: Bool {
        (importRecord?.result.resultStatus == .needsReview
            && importRecord?.reviewedAt == nil)
            || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || ingredients.isEmpty || steps.isEmpty
            || ingredients.contains {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            || steps.contains {
                $0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    public var totalMinutes: Int? {
        guard prepMinutes != nil || cookMinutes != nil else { return nil }
        let prep = prepMinutes ?? 0
        let cook = cookMinutes ?? 0
        guard prep >= 0, cook >= 0 else { return nil }
        let (total, overflow) = prep.addingReportingOverflow(cook)
        return overflow ? nil : total
    }
}

public struct RecipeCollection: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct RecipeCollectionMembership: Codable, Hashable, Sendable {
    public var recipeID: UUID
    public var collectionID: UUID

    public init(recipeID: UUID, collectionID: UUID) {
        self.recipeID = recipeID
        self.collectionID = collectionID
    }
}

public struct RecipeIngredient: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var amountText: String
    public var quantity: Decimal?
    public var unit: String?
    public var category: GroceryCategory

    public init(
        id: UUID = UUID(), name: String, amountText: String = "",
        quantity: Decimal? = nil, unit: String? = nil,
        category: GroceryCategory = .other
    ) {
        self.id = id
        self.name = name
        self.amountText = amountText
        self.quantity = quantity
        self.unit = unit
        self.category = category
    }

    public func displayAmount(multiplier: Decimal = 1) -> String {
        do {
            let amount = try IngredientAmount(originalText: amountText, value: quantity, unit: unit)
            let scaled = try amount.scaled(by: multiplier)
            guard let value = scaled.value else { return amountText }
            return Self.formatted(value, unit: unit)
        } catch {
            // Preserve the source if a caller supplied an invalid or inexact scale.
            return amountText
        }
    }

    /// Calculate quantity × requested / original before displaying a portion change.
    /// A Decimal multiplier alone cannot retain an exact ratio such as one third.
    public func displayAmount(servings: Int?, originalServings: Int?) -> String {
        guard quantity != nil else { return amountText }
        guard let servings, let originalServings, servings > 0, originalServings > 0,
            servings != originalServings
        else { return displayAmount() }
        let expression = "\(displayAmount()) × \(servings)/\(originalServings)"
        do {
            let source = try IngredientAmount(originalText: amountText, value: quantity, unit: unit)
            let multiplied = try source.scaled(by: Decimal(servings))
            guard let numerator = multiplied.value else { return amountText }
            guard let result = try Self.exactQuotient(numerator, by: Decimal(originalServings))
            else {
                return expression
            }
            return Self.formatted(result, unit: unit)
        } catch {
            // An exact expression also remains truthful when arithmetic would overflow.
            return expression
        }
    }

    // Immutable Foundation regex can be safely shared between import passes.
    // A failed pattern compilation must leave the original user text intact.
    private static let amountRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern:
            #"^((?:[0-9]+\s+)?[0-9]+/[0-9]+|[0-9]+(?:\.[0-9]+)?|\.[0-9]+)\s*([\p{L}µμ]+\.?(?:\s+(?:oz|ounces?))?)?$"#,
        options: .caseInsensitive
    )

    private static let vagueAmountUnits: Set<String> = [
        "about", "approximately", "approx", "roughly", "heaped",
        "heaping", "scant", "optional", "or", "to", "taste",
    ]

    /// Parse only explicit amounts; ambiguous quantities remain the original text.
    /// Ranges, approximate quantities and nonterminating fractions are not guessed.
    public static func from(
        name: String,
        amountText: String,
        category: GroceryCategory = .other
    ) -> RecipeIngredient {
        var result = RecipeIngredient(name: name, amountText: amountText, category: category)
        var text = amountText.trimmingCharacters(in: .whitespacesAndNewlines)

        for (symbol, fraction) in [
            ("¼", "1/4"), ("½", "1/2"), ("¾", "3/4"), ("⅛", "1/8"),
            ("⅜", "3/8"), ("⅝", "5/8"), ("⅞", "7/8"),
        ] {
            text = text.replacingOccurrences(of: symbol, with: " " + fraction)
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = Self.amountRegex else { return result }

        let fullRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: fullRange),
            let numberRange = Range(match.range(at: 1), in: text),
            let value = exactNumber(String(text[numberRange]))
        else {
            return result
        }

        if let unitRange = Range(match.range(at: 2), in: text) {
            let unit = String(text[unitRange])
            let normalizedUnit = unit.lowercased().trimmingCharacters(
                in: CharacterSet(charactersIn: ".")
            )
            guard !Self.vagueAmountUnits.contains(normalizedUnit) else {
                return result
            }
            result.unit = unit
        }

        result.quantity = value
        return result
    }

    static func formatted(_ value: Decimal, unit: String?) -> String {
        let number = NSDecimalNumber(decimal: value).stringValue
        guard let unit, !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return number
        }
        return number + " " + unit
    }

    /// Foundation can report success for a rounded quotient. Verify it using a
    /// reverse product whose coefficient fits in 38 digits, so that verification
    /// itself cannot round (for example, a rounded 2/3 must not multiply back to 2).
    /// High-precision edge cases conservatively remain source text.
    static func exactQuotient(_ numerator: Decimal, by denominator: Decimal) throws -> Decimal? {
        guard !numerator.isNaN, !denominator.isNaN, numerator >= 0, denominator > 0 else {
            throw IngredientAmount.ValidationError.arithmeticFailure
        }
        if numerator == 0 { return 0 }
        if denominator == 1 { return numerator }
        if numerator == denominator { return 1 }
        var dividend = numerator
        var divisor = denominator
        var quotient = Decimal()
        let status = NSDecimalDivide(&quotient, &dividend, &divisor, .plain)
        if status == .lossOfPrecision { return nil }
        guard status == .noError, !quotient.isNaN else {
            throw IngredientAmount.ValidationError.arithmeticFailure
        }
        guard coefficientDigits(quotient) + coefficientDigits(divisor) <= 38 else { return nil }
        var restored = Decimal()
        guard NSDecimalMultiply(&restored, &quotient, &divisor, .plain) == .noError,
            restored == numerator
        else { return nil }
        return quotient
    }

    private static func coefficientDigits(_ value: Decimal) -> Int {
        let coefficient =
            NSDecimalNumber(decimal: value).stringValue
            .split(whereSeparator: { $0 == "e" || $0 == "E" }).first ?? ""
        return coefficient.filter(\.isNumber).drop(while: { $0 == "0" })
            .reversed().drop(while: { $0 == "0" }).count
    }

    private static func exactNumber(_ text: String) -> Decimal? {
        let pieces = text.split(whereSeparator: \.isWhitespace)
        let locale = Locale(identifier: "en_US_POSIX")
        guard let last = pieces.last else { return nil }
        // Decimal has finite precision; never silently round a longer source token.
        let numericTokens = text.split { $0.isWhitespace || $0 == "/" }
        guard
            numericTokens.allSatisfy({
                $0.filter(\.isNumber).drop(while: { $0 == "0" }).count <= 38
            })
        else { return nil }
        if !last.contains("/") {
            guard let value = Decimal(string: String(last), locale: locale), !value.isNaN else {
                return nil
            }
            return value
        }
        let fraction = last.split(separator: "/")
        guard fraction.count == 2,
            let numerator = Decimal(string: String(fraction[0]), locale: locale),
            let denominator = Decimal(string: String(fraction[1]), locale: locale),
            denominator > 0
        else { return nil }
        guard var value = try? exactQuotient(numerator, by: denominator) else { return nil }
        if pieces.count == 2 {
            guard var whole = Decimal(string: String(pieces[0]), locale: locale) else { return nil }
            var total = Decimal()
            guard NSDecimalAdd(&total, &whole, &value, .plain) == .noError else { return nil }
            // Check this separate operation too; adding a whole number must not
            // swallow a small but exact fractional part.
            var recoveredFraction = Decimal()
            var recoveredWhole = Decimal()
            guard NSDecimalSubtract(&recoveredFraction, &total, &whole, .plain) == .noError,
                recoveredFraction == value,
                NSDecimalSubtract(&recoveredWhole, &total, &value, .plain) == .noError,
                recoveredWhole == whole
            else { return nil }
            value = total
        }
        return value.isNaN ? nil : value
    }
}

public struct CookingTemperature: Codable, Hashable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct RecipeStepTimer: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var label: String
    public var durationSeconds: Int

    public init(id: UUID = UUID(), label: String = "Timer", durationSeconds: Int) {
        self.id = id
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.durationSeconds = max(1, durationSeconds)
    }
}

public struct RecipeStep: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var instruction: String
    public var linkedIngredientIDs: [UUID]
    public var temperature: CookingTemperature?
    public var timers: [RecipeStepTimer]

    /// Compatibility bridge for recipes written before steps supported multiple timers.
    /// New code should use `timers`; old callers continue to read/write the first timer.
    public var durationSeconds: Int? {
        get { timers.first?.durationSeconds }
        set {
            guard let newValue, newValue > 0 else {
                if !timers.isEmpty { timers.removeFirst() }
                return
            }
            if timers.isEmpty {
                timers = [
                    RecipeStepTimer(
                        id: id, label: title.isEmpty ? "Step timer" : title,
                        durationSeconds: newValue)
                ]
            } else {
                timers[0].durationSeconds = newValue
            }
        }
    }

    public init(
        id: UUID = UUID(),
        title: String = "",
        instruction: String,
        durationSeconds: Int? = nil,
        linkedIngredientIDs: [UUID] = [],
        temperature: CookingTemperature? = nil,
        timers: [RecipeStepTimer] = []
    ) {
        self.id = id
        self.title = title
        self.instruction = instruction
        self.linkedIngredientIDs = linkedIngredientIDs
        self.temperature = temperature
        if timers.isEmpty, let durationSeconds, durationSeconds > 0 {
            self.timers = [
                RecipeStepTimer(
                    id: id,
                    label: title.isEmpty ? "Step timer" : title,
                    durationSeconds: durationSeconds
                )
            ]
        } else {
            self.timers = timers.filter { $0.durationSeconds > 0 }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case instruction
        case durationSeconds
        case linkedIngredientIDs
        case temperature
        case timers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        instruction = try container.decode(String.self, forKey: .instruction)
        linkedIngredientIDs =
            try container.decodeIfPresent([UUID].self, forKey: .linkedIngredientIDs) ?? []
        temperature = try container.decodeIfPresent(CookingTemperature.self, forKey: .temperature)
        timers = try container.decodeIfPresent([RecipeStepTimer].self, forKey: .timers) ?? []

        if timers.isEmpty,
            let legacyDuration = try container.decodeIfPresent(Int.self, forKey: .durationSeconds),
            legacyDuration > 0
        {
            timers = [
                RecipeStepTimer(
                    id: id,
                    label: title.isEmpty ? "Step timer" : title,
                    durationSeconds: legacyDuration
                )
            ]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(instruction, forKey: .instruction)
        try container.encode(linkedIngredientIDs, forKey: .linkedIngredientIDs)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encode(timers, forKey: .timers)
        // Keep one legacy duration for older builds that only understand one timer.
        try container.encodeIfPresent(timers.first?.durationSeconds, forKey: .durationSeconds)
    }
}

public struct GroceryItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var amountText: String
    public var quantity: Decimal?
    public var unit: String?
    public var category: GroceryCategory
    public var isChecked: Bool
    public var recipeIDs: [UUID]

    public init(
        id: UUID = UUID(), name: String, amountText: String = "",
        quantity: Decimal? = nil, unit: String? = nil,
        category: GroceryCategory = .other, isChecked: Bool = false,
        recipeIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.amountText = amountText
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.isChecked = isChecked
        self.recipeIDs = recipeIDs
    }
}

public struct MealPlanEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var recipeID: UUID
    public var date: Date
    public var slot: MealSlot

    public init(id: UUID = UUID(), recipeID: UUID, date: Date, slot: MealSlot = .dinner) {
        self.id = id
        self.recipeID = recipeID
        self.date = date
        self.slot = slot
    }
}

public struct RecipeSettings: Codable, Equatable, Sendable {
    public var displayName: String
    public var email: String
    public var appearance: AppAppearance
    public var keepScreenAwake: Bool
    public var timerNotifications: Bool

    public init(
        displayName: String = "", email: String = "",
        appearance: AppAppearance = .system, keepScreenAwake: Bool = true,
        timerNotifications: Bool = false
    ) {
        self.displayName = displayName
        self.email = email
        self.appearance = appearance
        self.keepScreenAwake = keepScreenAwake
        self.timerNotifications = timerNotifications
    }
}
