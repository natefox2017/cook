import Foundation

// Local client records, not API DTOs. Remote import integration awaits the frozen contract.
struct IngredientRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var amount: String = ""
    var unit: String = ""

    func displayedAmount(for servings: Int, originalServings: Int?) -> String {
        guard let originalServings, originalServings > 0, servings > 0,
              let quantity = Quantity.parse(amount),
              let scaled = Quantity.multiply(quantity, by: Decimal(servings) / Decimal(originalServings))
        else { return [amount, unit].filter { !$0.isEmpty }.joined(separator: " ") }
        return [Quantity.format(scaled), unit].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum Quantity {
    static func parse(_ raw: String) -> Decimal? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^\d+(?:\.\d+)?$"#, options: .regularExpression) != nil,
              let result = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
              result >= 0 else { return nil }
        return result
    }
    static func multiply(_ value: Decimal, by factor: Decimal) -> Decimal? {
        var value = value, factor = factor, result = Decimal()
        guard NSDecimalMultiply(&result, &value, &factor, .plain) == .noError else { return nil }
        return result
    }
    static func add(_ a: Decimal, _ b: Decimal) -> Decimal? {
        var a = a, b = b, result = Decimal()
        guard NSDecimalAdd(&result, &a, &b, .plain) == .noError else { return nil }
        return result
    }
    static func format(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
}

struct StepRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var instruction: String
    var durationSeconds: Int?
}

struct ReviewField: Codable, Identifiable, Equatable {
    var id = UUID()
    var ingredientID: UUID
    var question: String
    var evidence: String
}

struct RecipeRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var servings: Int? = 2
    var ingredients: [IngredientRecord] = []
    var steps: [StepRecord] = []
    var sourceURL: URL?
    var sourcePlatform: String = ""
    var sourceAuthor: String = ""
    var sourceTitle: String = ""
    var coverData: Data?
    var favorite = false
    var reviewFields: [ReviewField] = []
    var createdAt = Date()

    var searchableText: String {
        ([title] + ingredients.map(\.name) + steps.map(\.instruction)).joined(separator: " ")
    }
    var sourceSummary: String {
        [sourcePlatform, sourceAuthor].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct GroceryRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var amount: String
    var unit: String
    var checked = false
    var sourceRecipeIDs: [UUID] = []
    var summary: String { [amount, unit].filter { !$0.isEmpty }.joined(separator: " ") }
}

struct LocalCapture: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case url, text, image, file }
    var id = UUID()
    var kind: Kind
    var value: String
    var attachmentName: String?
    var capturedAt = Date()
}

struct LocalSnapshot: Codable, Equatable {
    var version = 1
    var recipes: [RecipeRecord] = []
    var groceries: [GroceryRecord] = []
    var captures: [LocalCapture] = []
}

enum LocalStoreError: LocalizedError {
    case invalidURL, emptyInput, oversizedAttachment, oversizedCover, unsupportedVersion
    var errorDescription: String? {
        switch self {
        case .invalidURL: String(localized: "Enter a complete http or https recipe link.")
        case .emptyInput: String(localized: "Add some content before saving.")
        case .oversizedAttachment: String(localized: "Choose a file smaller than 20 MB.")
        case .oversizedCover: String(localized: "Choose a photo smaller than 5 MB after compression.")
        case .unsupportedVersion: String(localized: "This collection needs a newer version of Cook. Your saved file has been kept.")
        }
    }
}
