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
    var version: Int
    var recipes: [Recipe]
    var groceries: [GroceryItem]
    var mealPlan: [MealPlanEntry]
    var collections: [RecipeCollection]
    var collectionMemberships: [RecipeCollectionMembership]
    var settings: CookSettings

    init(
        version: Int = 2,
        recipes: [Recipe] = [],
        groceries: [GroceryItem] = [],
        mealPlan: [MealPlanEntry] = [],
        collections: [RecipeCollection] = [],
        collectionMemberships: [RecipeCollectionMembership] = [],
        settings: CookSettings = CookSettings()
    ) {
        self.version = version
        self.recipes = recipes
        self.groceries = groceries
        self.mealPlan = mealPlan
        self.collections = collections
        self.collectionMemberships = collectionMemberships
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case recipes
        case groceries
        case mealPlan
        case collections
        case collectionMemberships
        case settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        recipes = try container.decodeIfPresent([Recipe].self, forKey: .recipes) ?? []
        groceries = try container.decodeIfPresent([GroceryItem].self, forKey: .groceries) ?? []
        mealPlan = try container.decodeIfPresent([MealPlanEntry].self, forKey: .mealPlan) ?? []
        collections = try container.decodeIfPresent([RecipeCollection].self, forKey: .collections) ?? []
        collectionMemberships = try container.decodeIfPresent(
            [RecipeCollectionMembership].self,
            forKey: .collectionMemberships
        ) ?? []
        settings = try container.decodeIfPresent(CookSettings.self, forKey: .settings) ?? CookSettings()
    }
}

@Observable @MainActor
public final class CookStore {
    public private(set) var recipes: [Recipe] = []
    public private(set) var groceries: [GroceryItem] = []
    public private(set) var mealPlan: [MealPlanEntry] = []
    public private(set) var collections: [RecipeCollection] = []
    public private(set) var collectionMemberships: [RecipeCollectionMembership] = []
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

    public func collection(id: UUID) -> RecipeCollection? {
        collections.first { $0.id == id }
    }

    public func collectionIDs(forRecipe recipeID: UUID) -> Set<UUID> {
        Set(
            collectionMemberships
                .filter { $0.recipeID == recipeID }
                .map(\.collectionID)
        )
    }

    public func recipes(inCollection collectionID: UUID) -> [Recipe] {
        let recipeIDs = Set(
            collectionMemberships
                .filter { $0.collectionID == collectionID }
                .map(\.recipeID)
        )
        return recipes.filter { recipeIDs.contains($0.id) }
    }

    @discardableResult
    public func createCollection(name: String) throws -> RecipeCollection {
        let cleaned = try validatedCollectionName(name)
        guard !collections.contains(where: {
            normalized($0.name) == normalized(cleaned)
        }) else {
            throw CookStoreError.invalidValue("A collection with this name already exists.")
        }

        var next = snapshot
        let collection = RecipeCollection(name: cleaned)
        next.collections.append(collection)
        next.collections.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        try commit(next)
        return collection
    }

    public func renameCollection(id: UUID, name: String) throws {
        guard let index = collections.firstIndex(where: { $0.id == id }) else {
            throw CookStoreError.missingItem
        }
        let cleaned = try validatedCollectionName(name)
        guard !collections.contains(where: {
            $0.id != id && normalized($0.name) == normalized(cleaned)
        }) else {
            throw CookStoreError.invalidValue("A collection with this name already exists.")
        }

        var next = snapshot
        next.collections[index].name = cleaned
        next.collections[index].updatedAt = .now
        next.collections.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        try commit(next)
    }

    public func deleteCollection(id: UUID) throws {
        guard collections.contains(where: { $0.id == id }) else {
            throw CookStoreError.missingItem
        }
        var next = snapshot
        next.collections.removeAll { $0.id == id }
        next.collectionMemberships.removeAll { $0.collectionID == id }
        try commit(next)
    }

    public func setRecipe(
        _ recipeID: UUID,
        inCollection collectionID: UUID,
        isMember: Bool
    ) throws {
        guard recipe(id: recipeID) != nil else { throw CookStoreError.missingRecipe }
        guard collection(id: collectionID) != nil else { throw CookStoreError.missingItem }

        let membership = RecipeCollectionMembership(
            recipeID: recipeID,
            collectionID: collectionID
        )
        let exists = collectionMemberships.contains(membership)
        guard exists != isMember else { return }

        var next = snapshot
        if isMember {
            next.collectionMemberships.append(membership)
        } else {
            next.collectionMemberships.removeAll { $0 == membership }
        }
        try commit(next)
    }

    @discardableResult
    public func importLegacyCollectionNames(_ names: [String]) throws -> Int {
        let cleanedNames = names.compactMap { raw -> String? in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, normalized(value) != "favorites" else { return nil }
            return value
        }

        var next = snapshot
        var existing = Set(next.collections.map { normalized($0.name) })
        var added = 0

        for name in cleanedNames {
            let key = normalized(name)
            guard !existing.contains(key) else { continue }
            next.collections.append(RecipeCollection(name: name))
            existing.insert(key)
            added += 1
        }

        guard added > 0 else { return 0 }
        next.collections.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        try commit(next)
        return added
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
        next.collectionMemberships.removeAll { $0.recipeID == id }
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
            if next.settings.consolidateCompatibleGroceries,
               let index = next.groceries.firstIndex(where: {
                   !$0.isChecked && $0.quantity != nil && item.quantity != nil
                       && normalized($0.name) == normalized(item.name)
                       && unitKey($0.unit) == unitKey(item.unit)
               }),
               var existing = next.groceries[index].quantity,
               var added = item.quantity {
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
        LibrarySnapshot(
            recipes: recipes,
            groceries: groceries,
            mealPlan: mealPlan,
            collections: collections,
            collectionMemberships: collectionMemberships,
            settings: settings
        )
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
        collections = snapshot.collections
        collectionMemberships = snapshot.collectionMemberships
        settings = snapshot.settings
    }

    private func validate(_ snapshot: LibrarySnapshot) throws {
        guard snapshot.version == 1 || snapshot.version == 2 else {
            throw CookStoreError.unsupportedVersion(snapshot.version)
        }
        func unique(_ ids: [UUID]) -> Bool { Set(ids).count == ids.count }
        guard unique(snapshot.recipes.map(\.id)), unique(snapshot.groceries.map(\.id)),
              unique(snapshot.mealPlan.map(\.id)), unique(snapshot.collections.map(\.id)) else {
            throw CookStoreError.invalidValue("The library contains duplicate identifiers.")
        }
        let recipeIDs = Set(snapshot.recipes.map(\.id))
        let collectionIDs = Set(snapshot.collections.map(\.id))

        var collectionNameKeys: Set<String> = []
        for collection in snapshot.collections {
            let name = collection.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  collection.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  collection.updatedAt.timeIntervalSinceReferenceDate.isFinite,
                  collectionNameKeys.insert(normalized(name)).inserted else {
                throw CookStoreError.invalidValue(
                    "Collection names must be unique and cannot be empty."
                )
            }
        }

        var membershipKeys: Set<String> = []
        for membership in snapshot.collectionMemberships {
            guard recipeIDs.contains(membership.recipeID),
                  collectionIDs.contains(membership.collectionID),
                  membershipKeys.insert(
                    "\(membership.recipeID.uuidString):\(membership.collectionID.uuidString)"
                  ).inserted else {
                throw CookStoreError.invalidValue(
                    "A collection contains an unavailable or duplicate recipe relationship."
                )
            }
        }

        for recipe in snapshot.recipes {
            guard recipe.servings.map({ $0 > 0 }) ?? true,
                  recipe.prepMinutes.map({ $0 >= 0 }) ?? true,
                  recipe.cookMinutes.map({ $0 >= 0 }) ?? true,
                  unique(recipe.ingredients.map(\.id)), unique(recipe.steps.map(\.id)),
                  recipe.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  recipe.updatedAt.timeIntervalSinceReferenceDate.isFinite else {
                throw CookStoreError.invalidValue("Check the recipe's servings, times and ingredient identifiers.")
            }
            let ingredientIDs = Set(recipe.ingredients.map(\.id))
            for ingredient in recipe.ingredients {
                _ = try IngredientAmount(
                    originalText: ingredient.amountText,
                    value: ingredient.quantity,
                    unit: ingredient.unit
                )
            }
            for step in recipe.steps {
                guard unique(step.linkedIngredientIDs),
                      Set(step.linkedIngredientIDs).isSubset(of: ingredientIDs),
                      unique(step.timers.map(\.id)),
                      step.timers.allSatisfy({ $0.durationSeconds > 0 }) else {
                    throw CookStoreError.invalidValue(
                        "Check the cooking step's ingredient links and timers."
                    )
                }
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

    private func validatedCollectionName(_ name: String) throws -> String {
        let cleaned = name
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw CookStoreError.invalidValue("Give the collection a name.")
        }
        guard cleaned.count <= 80 else {
            throw CookStoreError.invalidValue("Collection names can be up to 80 characters.")
        }
        guard normalized(cleaned) != "favorites" else {
            throw CookStoreError.invalidValue("Favorites is already built in.")
        }
        return cleaned
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
