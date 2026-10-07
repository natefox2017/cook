import Foundation
import Observation

public enum CookStoreError: LocalizedError, Equatable {
    case unreadableLibrary(String)
    case missingRecipe
    case missingItem
    case invalidValue(String)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unreadableLibrary(let reason):
            "Your library could not be read. Its original file has been preserved. \(reason)"
        case .missingRecipe:
            "This recipe is no longer in your library."
        case .missingItem:
            "This item is no longer available. Please reopen the recipe or list."
        case .invalidValue(let message):
            message
        case .unsupportedVersion:
            "This library was saved in an unsupported format. Its original file has been preserved."
        }
    }
}

private struct LibrarySnapshot: Codable {
    var version = 1
    var recipes: [Recipe] = []
    var groceries: [GroceryItem] = []
    var mealPlan: [MealPlanEntry] = []
    var settings = CookSettings()
}

@Observable @MainActor
public final class CookStore {
    public private(set) var recipes: [Recipe] = []
    public private(set) var groceries: [GroceryItem] = []
    public private(set) var mealPlan: [MealPlanEntry] = []
    public private(set) var settings = CookSettings()
    public private(set) var loadError: String?

    @ObservationIgnored private let fileURL: URL?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        reload()
    }

    public static func defaultFileURL() -> URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Cook", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    public func recipe(id: UUID) -> Recipe? {
        recipes.first { $0.id == id }
    }

    public func upsert(_ recipe: Recipe) throws {
        var next = snapshot
        var saved = recipe
        saved.updatedAt = .now
        if let index = next.recipes.firstIndex(where: { $0.id == recipe.id }) {
            saved.createdAt = next.recipes[index].createdAt
            next.recipes[index] = saved
        } else {
            next.recipes.append(saved)
        }
        try commit(next)
    }

    public func deleteRecipe(id: UUID) throws {
        var next = snapshot
        next.recipes.removeAll { $0.id == id }
        next.mealPlan.removeAll { $0.recipeID == id }
        for index in next.groceries.indices {
            // Keep the shopping item; deleting a source should not erase a shopping task.
            next.groceries[index].recipeIDs.removeAll { $0 == id }
        }
        try commit(next)
    }

    public func toggleFavorite(id: UUID) throws {
        guard let index = recipes.firstIndex(where: { $0.id == id }) else {
            throw CookStoreError.missingRecipe
        }
        var next = snapshot
        next.recipes[index].isFavorite.toggle()
        next.recipes[index].updatedAt = .now
        try commit(next)
    }

    public func addToGroceries(recipeID: UUID, servings: Int?,
                               ingredientIDs: Set<UUID>) throws {
        guard let recipe = recipe(id: recipeID) else { throw CookStoreError.missingRecipe }
        guard ingredientIDs.isSubset(of: Set(recipe.ingredients.map(\.id))) else {
            throw CookStoreError.missingItem
        }
        guard !ingredientIDs.isEmpty else { return }
        if let servings, servings <= 0 {
            throw CookStoreError.invalidValue("Choose a serving count greater than zero.")
        }
        if servings != nil, recipe.servings == nil {
            throw CookStoreError.invalidValue("Set the recipe's original serving count before scaling it.")
        }
        let originalServings = recipe.servings ?? 1
        let requestedServings = servings ?? originalServings
        guard originalServings > 0 else {
            throw CookStoreError.invalidValue("The recipe's serving count must be greater than zero.")
        }

        var next = snapshot
        for ingredient in recipe.ingredients where ingredientIDs.contains(ingredient.id) {
            guard !normalized(ingredient.name).isEmpty else {
                throw CookStoreError.invalidValue("Give each selected ingredient a name before adding it.")
            }
            let item = try groceryItem(from: ingredient, recipeID: recipeID,
                                       originalServings: originalServings,
                                       requestedServings: requestedServings)
            if let index = next.groceries.firstIndex(where: {
                !$0.isChecked && $0.quantity != nil && item.quantity != nil
                    && normalized($0.name) == normalized(item.name)
                    && unitKey($0.unit) == unitKey(item.unit)
            }), var existing = next.groceries[index].quantity, var added = item.quantity {
                var total = Decimal()
                guard NSDecimalAdd(&total, &existing, &added, .plain) == .noError else {
                    throw IngredientAmount.ValidationError.arithmeticFailure
                }
                next.groceries[index].quantity = total
                next.groceries[index].amountText = RecipeIngredient.formatted(
                    total, unit: next.groceries[index].unit
                )
                if !next.groceries[index].recipeIDs.contains(recipeID) {
                    next.groceries[index].recipeIDs.append(recipeID)
                }
            } else {
                next.groceries.append(item)
            }
        }
        try commit(next)
    }

    public func upsertGrocery(_ item: GroceryItem) throws {
        var next = snapshot
        if let index = next.groceries.firstIndex(where: { $0.id == item.id }) {
            next.groceries[index] = item
        } else {
            next.groceries.append(item)
        }
        try commit(next)
    }

    public func toggleGrocery(id: UUID) throws {
        guard let index = groceries.firstIndex(where: { $0.id == id }) else {
            throw CookStoreError.missingItem
        }
        var next = snapshot
        next.groceries[index].isChecked.toggle()
        try commit(next)
    }

    public func deleteGrocery(id: UUID) throws {
        var next = snapshot
        next.groceries.removeAll { $0.id == id }
        try commit(next)
    }

    public func clearCheckedGroceries() throws {
        var next = snapshot
        next.groceries.removeAll(where: \.isChecked)
        try commit(next)
    }

    public func upsertMeal(_ entry: MealPlanEntry) throws {
        guard recipe(id: entry.recipeID) != nil else { throw CookStoreError.missingRecipe }
        guard entry.date.timeIntervalSinceReferenceDate.isFinite else {
            throw CookStoreError.invalidValue("Choose a valid date for your meal.")
        }
        var next = snapshot
        var saved = entry
        saved.date = Calendar.current.startOfDay(for: entry.date)
        // One recipe per day and meal slot, including when editing an existing entry.
        next.mealPlan.removeAll {
            $0.id == entry.id
                || ($0.slot == entry.slot && Calendar.current.isDate($0.date, inSameDayAs: entry.date))
        }
        next.mealPlan.append(saved)
        next.mealPlan.sort { $0.date < $1.date }
        try commit(next)
    }

    public func deleteMeal(id: UUID) throws {
        var next = snapshot
        next.mealPlan.removeAll { $0.id == id }
        try commit(next)
    }

    public func updateSettings(_ settings: CookSettings) throws {
        var next = snapshot
        next.settings = settings
        try commit(next)
    }

    public func reload() {
        guard let fileURL else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let loaded = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
            try validate(loaded)
            publish(loaded)
            loadError = nil
        } catch {
            let cocoaError = error as NSError
            if cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == NSFileReadNoSuchFileError {
                publish(LibrarySnapshot())
                loadError = nil
            } else {
                // Do not replace either the original file or the last good in-memory data.
                loadError = error.localizedDescription
            }
        }
    }

    public func resetLibrary() throws {
        try commit(LibrarySnapshot())
    }

    public func loadSampleRecipes() throws {
        var next = snapshot
        let existingIDs = Set(next.recipes.map(\.id))
        next.recipes.append(contentsOf: SampleRecipes.recipes.filter { !existingIDs.contains($0.id) })
        try commit(next)
    }

    public func exportData() throws -> Data {
        if let loadError { throw CookStoreError.unreadableLibrary(loadError) }
        return try encoded(snapshot)
    }

    private var snapshot: LibrarySnapshot {
        LibrarySnapshot(recipes: recipes, groceries: groceries, mealPlan: mealPlan, settings: settings)
    }

    private func commit(_ next: LibrarySnapshot) throws {
        if let loadError { throw CookStoreError.unreadableLibrary(loadError) }
        try validate(next)
        let data = try encoded(next)
        if let fileURL {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        }
        // UI observes a mutation only after its complete snapshot is safely written.
        publish(next)
    }

    private func encoded(_ snapshot: LibrarySnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    private func publish(_ snapshot: LibrarySnapshot) {
        recipes = snapshot.recipes
        groceries = snapshot.groceries
        mealPlan = snapshot.mealPlan
        settings = snapshot.settings
    }

    private func validate(_ snapshot: LibrarySnapshot) throws {
        guard snapshot.version == 1 else { throw CookStoreError.unsupportedVersion(snapshot.version) }
        func unique(_ ids: [UUID]) -> Bool { Set(ids).count == ids.count }
        guard unique(snapshot.recipes.map(\.id)), unique(snapshot.groceries.map(\.id)),
              unique(snapshot.mealPlan.map(\.id)) else {
            throw CookStoreError.invalidValue("The library contains duplicate identifiers.")
        }
        let recipeIDs = Set(snapshot.recipes.map(\.id))
        for recipe in snapshot.recipes {
            guard recipe.servings.map({ $0 > 0 }) ?? true,
                  recipe.prepMinutes.map({ $0 >= 0 }) ?? true,
                  recipe.cookMinutes.map({ $0 >= 0 }) ?? true,
                  unique(recipe.ingredients.map(\.id)), unique(recipe.steps.map(\.id)),
                  recipe.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  recipe.updatedAt.timeIntervalSinceReferenceDate.isFinite else {
                throw CookStoreError.invalidValue("Check the recipe's servings, times and ingredient identifiers.")
            }
            for ingredient in recipe.ingredients {
                _ = try IngredientAmount(originalText: ingredient.amountText,
                                         value: ingredient.quantity, unit: ingredient.unit)
            }
            guard recipe.steps.allSatisfy({ $0.durationSeconds.map { $0 > 0 } ?? true }) else {
                throw CookStoreError.invalidValue("A cooking timer must be longer than zero seconds.")
            }
        }
        for item in snapshot.groceries {
            guard !normalized(item.name).isEmpty, Set(item.recipeIDs).isSubset(of: recipeIDs),
                  unique(item.recipeIDs) else {
                throw CookStoreError.invalidValue("Check the grocery item's name and recipe sources.")
            }
            _ = try IngredientAmount(originalText: item.amountText, value: item.quantity, unit: item.unit)
        }
        var occupiedSlots: Set<String> = []
        for entry in snapshot.mealPlan {
            guard recipeIDs.contains(entry.recipeID), entry.date.timeIntervalSinceReferenceDate.isFinite else {
                throw CookStoreError.invalidValue("A meal plan refers to an unavailable recipe or date.")
            }
            let day = Calendar.current.startOfDay(for: entry.date).timeIntervalSinceReferenceDate
            guard occupiedSlots.insert("\(day):\(entry.slot.rawValue)").inserted else {
                throw CookStoreError.invalidValue("A day contains more than one recipe in the same meal slot.")
            }
        }
    }

    private func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    private func unitKey(_ unit: String?) -> String {
        // Case can carry meaning, such as t (teaspoon) versus T (tablespoon).
        (unit ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func groceryItem(from ingredient: RecipeIngredient, recipeID: UUID,
                             originalServings: Int, requestedServings: Int) throws -> GroceryItem {
        let source = try IngredientAmount(originalText: ingredient.amountText,
                                          value: ingredient.quantity, unit: ingredient.unit)
        var quantity = source.value
        var text = source.originalText
        if quantity != nil, originalServings != requestedServings {
            let multiplied = try source.scaled(by: Decimal(requestedServings))
            if let numerator = multiplied.value {
                if let divided = try RecipeIngredient.exactQuotient(numerator, by: Decimal(originalServings)) {
                    quantity = divided
                } else {
                    // Keep an exact visible expression instead of inventing a rounded quantity.
                    quantity = nil
                    text = "\(ingredient.displayAmount()) × \(requestedServings)/\(originalServings)"
                }
            }
        }
        if let quantity {
            text = RecipeIngredient.formatted(quantity, unit: ingredient.unit)
        }
        return GroceryItem(name: ingredient.name, amountText: text, quantity: quantity,
                           unit: ingredient.unit, category: ingredient.category, recipeIDs: [recipeID])
    }
}
