// Developer: gengyun
// Purpose: Builds a consolidated weekly grocery preview from a meal plan snapshot without mutating the store.

import CryptoKit
import Foundation

/// Pure, store-independent weekly grocery preview.
///
/// Reuses the existing grocery consolidation rule: ingredient names ignore
/// case and extra spaces, while units stay case-sensitive (t and T differ).
/// Only exact quantities with an equal unit merge; unknown or vague amounts
/// keep their original text and source instead of inventing a number. The
/// same recipe planned for two meals yields two sources and counts twice.
public enum RecipeWeeklyGroceryPreview {

    /// One contributing meal occurrence (recipe + day + slot).
    public struct Source: Hashable, Sendable, Identifiable {
        public let recipeID: UUID
        public let recipeTitle: String
        public let date: Date
        public let slot: MealSlot

        public var id: String {
            "\(recipeID.uuidString)-\(slot.rawValue)-\(date.timeIntervalSinceReferenceDate)"
        }
    }

    /// A consolidated preview row. `isKept` is user-editable: deselecting an
    /// item the user already has at home removes it from the final append.
    public struct Line: Hashable, Sendable, Identifiable {
        public let id: UUID
        public let name: String
        public var amountText: String
        public var quantity: Decimal?
        public let unit: String?
        public let category: GroceryCategory
        public var isKept: Bool
        public var sources: [Source]

        public init(
            id: UUID = UUID(),
            name: String,
            amountText: String = "",
            quantity: Decimal? = nil,
            unit: String? = nil,
            category: GroceryCategory = .other,
            isKept: Bool = true,
            sources: [Source]
        ) {
            self.id = id
            self.name = name
            self.amountText = amountText
            self.quantity = quantity
            self.unit = unit
            self.category = category
            self.isKept = isKept
            self.sources = sources
        }
    }

    /// A planned meal whose recipe no longer exists in the snapshot.
    public struct MissingRecipe: Hashable, Sendable, Identifiable {
        public let entryID: UUID
        public let recipeID: UUID
        public let date: Date
        public let slot: MealSlot

        public var id: UUID { entryID }
    }

    public struct BuildResult: Equatable, Sendable {
        public var lines: [Line]
        public var missingRecipes: [MissingRecipe]

        public init(lines: [Line] = [], missingRecipes: [MissingRecipe] = []) {
            self.lines = lines
            self.missingRecipes = missingRecipes
        }
    }

    /// Builds the preview for the given week. Entries whose date falls outside
    /// `weekDates` are ignored. A planned meal whose recipe is gone is skipped
    /// and reported instead of fabricating a row; an empty week or a week whose
    /// recipes are all gone yields an empty preview (drives the empty state).
    public static func build(
        entries: [MealPlanEntry],
        recipes: [Recipe],
        weekDates: [Date],
        calendar: Calendar
    ) -> BuildResult {
        var recipeByID: [UUID: Recipe] = [:]
        for recipe in recipes {
            recipeByID[recipe.id] = recipe
        }
        var lines: [Line] = []
        var missingRecipes: [MissingRecipe] = []
        var indices: [ConsolidationKey: Int] = [:]

        for entry in entries
        where weekDates.contains(where: { calendar.isDate($0, inSameDayAs: entry.date) }) {
            guard let recipe = recipeByID[entry.recipeID] else {
                missingRecipes.append(
                    MissingRecipe(
                        entryID: entry.id,
                        recipeID: entry.recipeID,
                        date: entry.date,
                        slot: entry.slot
                    )
                )
                continue
            }

            let source = Source(
                recipeID: recipe.id,
                recipeTitle: recipe.title,
                date: entry.date,
                slot: entry.slot
            )

            for ingredient in recipe.ingredients where !normalized(ingredient.name).isEmpty {
                let quantity = ingredient.quantity
                let amountText =
                    quantity.map { RecipeIngredient.formatted($0, unit: ingredient.unit) }
                    ?? ingredient.amountText
                appendLine(
                    name: ingredient.name,
                    amountText: amountText,
                    quantity: quantity,
                    unit: ingredient.unit,
                    category: ingredient.category,
                    source: source,
                    lines: &lines,
                    indices: &indices
                )
            }
        }

        return BuildResult(lines: lines, missingRecipes: missingRecipes)
    }

    /// A stable content fingerprint for the plan + recipes that produced a
    /// preview. Any change to the planned meals or their ingredients changes
    /// the signature, so a confirm can detect a stale preview before appending.
    public static func sourceSignature(
        entries: [MealPlanEntry],
        recipes: [Recipe]
    ) -> String {
        struct SignatureIngredient: Codable {
            let name: String
            let amountText: String
            let quantity: Decimal?
            let unit: String?
            let category: GroceryCategory
        }
        struct SignatureRecipe: Codable {
            let id: UUID
            let title: String
            let ingredients: [SignatureIngredient]
        }
        struct SignatureEntry: Codable {
            let id: UUID
            let recipeID: UUID
            let date: Date
            let slot: MealSlot
        }
        struct SignaturePayload: Codable {
            let entries: [SignatureEntry]
            let recipes: [SignatureRecipe]
        }

        let referencedIDs = Set(entries.map(\.recipeID))
        let payload = SignaturePayload(
            entries: entries.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                SignatureEntry(id: $0.id, recipeID: $0.recipeID, date: $0.date, slot: $0.slot)
            },
            recipes: recipes
                .filter { referencedIDs.contains($0.id) }
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map { recipe in
                    SignatureRecipe(
                        id: recipe.id,
                        title: recipe.title,
                        ingredients: recipe.ingredients.map {
                            SignatureIngredient(
                                name: $0.name,
                                amountText: $0.amountText,
                                quantity: $0.quantity,
                                unit: $0.unit,
                                category: $0.category
                            )
                        }
                    )
                }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload),
            let text = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return Self.sha256Hex(text)
    }

    /// Derives a stable operation identifier from the source signature and the
    /// exact rows being appended. Rebuilding the same preview with the same
    /// kept selection yields the same identifier, so a persisted operation log
    /// can reject a duplicate append across double-taps, retries or restarts.
    public static func operationID(
        sourceSignature: String,
        items: [WeeklyGroceryAppendItem]
    ) -> UUID {
        let canonicalItems = items
            .sorted { lhs, rhs in
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                if lhs.unit != rhs.unit {
                    return (lhs.unit ?? "") < (rhs.unit ?? "")
                }
                return lhs.amountText < rhs.amountText
            }
            .map {
                [
                    $0.name,
                    $0.amountText,
                    $0.quantity.map(\.description) ?? "",
                    $0.unit ?? "",
                    $0.category.rawValue,
                    $0.recipeIDs.map(\.uuidString).sorted().joined(separator: ","),
                ].joined(separator: "\u{1f}")
            }
            .joined(separator: "\u{1e}")

        let digest = Data(SHA256.hash(data: Data("\(sourceSignature)\u{1d}\(canonicalItems)".utf8)))
        var bytes = [UInt8](digest.prefix(16))
        // Mark as a name-based (v5) UUID so the derived value is well-formed.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    // MARK: - Consolidation

    /// Matches the existing grocery consolidation rule: names ignore case and
    /// extra spaces, while units remain case-sensitive (t and T differ).
    private struct ConsolidationKey: Hashable {
        let name: String
        let unit: String
    }

    private static func appendLine(
        name: String,
        amountText: String,
        quantity: Decimal?,
        unit: String?,
        category: GroceryCategory,
        source: Source,
        lines: inout [Line],
        indices: inout [ConsolidationKey: Int]
    ) {
        let key = ConsolidationKey(name: normalized(name), unit: unitKey(unit))

        if let quantity,
            let index = indices[key],
            var existing = lines[index].quantity
        {
            var added = quantity
            var total = Decimal()
            guard NSDecimalAdd(&total, &existing, &added, .plain) == .noError else {
                // An overflow must preserve evidence rather than invent a value.
                lines.append(
                    Line(
                        name: name, amountText: amountText, quantity: quantity,
                        unit: unit, category: category, sources: [source]
                    )
                )
                return
            }
            lines[index].quantity = total
            lines[index].amountText = RecipeIngredient.formatted(total, unit: lines[index].unit)
            if !lines[index].sources.contains(source) {
                lines[index].sources.append(source)
            }
            return
        }

        lines.append(
            Line(
                name: name, amountText: amountText, quantity: quantity,
                unit: unit, category: category, sources: [source]
            )
        )
        if quantity != nil, indices[key] == nil {
            indices[key] = lines.count - 1
        }
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    private static func unitKey(_ unit: String?) -> String {
        // Case can carry meaning, such as t (teaspoon) versus T (tablespoon).
        (unit ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// A grocery row to append, already consolidated and carrying its source
/// recipes so the "From …" attribution survives into the grocery list.
public struct WeeklyGroceryAppendItem: Hashable, Sendable {
    public let name: String
    public let amountText: String
    public let quantity: Decimal?
    public let unit: String?
    public let category: GroceryCategory
    public let recipeIDs: [UUID]

    public init(
        name: String,
        amountText: String = "",
        quantity: Decimal? = nil,
        unit: String? = nil,
        category: GroceryCategory = .other,
        recipeIDs: [UUID] = []
    ) {
        self.name = name
        self.amountText = amountText
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.recipeIDs = recipeIDs
    }

    public init(line: RecipeWeeklyGroceryPreview.Line) {
        self.name = line.name
        self.amountText = line.amountText
        self.quantity = line.quantity
        self.unit = line.unit
        self.category = line.category
        var seen = Set<UUID>()
        self.recipeIDs = line.sources.map(\.recipeID).filter { seen.insert($0).inserted }
    }
}

/// The typed payload the preview sheet hands to its injected atomic append port.
public struct WeeklyGroceryAppendRequest: Hashable, Sendable {
    public let operationID: UUID
    public let items: [WeeklyGroceryAppendItem]
    public let sourceSignature: String

    public init(
        operationID: UUID,
        items: [WeeklyGroceryAppendItem],
        sourceSignature: String
    ) {
        self.operationID = operationID
        self.items = items
        self.sourceSignature = sourceSignature
    }
}

/// Outcome of an atomic append. `.alreadyCommitted` is a success: the same
/// operation was already persisted, so the caller must not append again.
public enum WeeklyGroceryAppendOutcome: Equatable, Sendable {
    case appended
    case alreadyCommitted
    case staleSource
    case failed(String)

    public var isSuccess: Bool {
        switch self {
        case .appended, .alreadyCommitted:
            true
        case .staleSource, .failed:
            false
        }
    }
}
