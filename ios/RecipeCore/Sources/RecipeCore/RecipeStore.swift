// Developer: gengyun
// Purpose: Owns RecipePouch's validated local library and cloud snapshot synchronization boundary.

import Foundation
import Observation

public enum RecipeStoreError: LocalizedError, Equatable {
    case unreadableLibrary(String)
    case missingRecipe
    case missingItem
    case invalidValue(String)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unreadableLibrary(let reason):
            RecipeLanguage.localized("Your library could not be read. Its original file has been preserved. %@", reason)
        case .missingRecipe:
            RecipeLanguage.localized("This recipe is no longer in your library.")
        case .missingItem:
            RecipeLanguage.localized("This item is no longer available. Please reopen the recipe or list.")
        case .invalidValue(let message):
            message
        case .unsupportedVersion:
            RecipeLanguage.localized("This library was saved in an unsupported format. Its original file has been preserved.")
        }
    }
}

public struct RecipeLibrarySnapshot: Codable, Sendable, Equatable {
    public var version: Int
    public var recipes: [Recipe]
    public var groceries: [GroceryItem]
    public var mealPlan: [MealPlanEntry]
    public var collections: [RecipeCollection]
    public var collectionMemberships: [RecipeCollectionMembership]
    public var settings: RecipeSettings
    public var deletedEntities: Set<String>?

    public init(
        version: Int = 2,
        recipes: [Recipe] = [],
        groceries: [GroceryItem] = [],
        mealPlan: [MealPlanEntry] = [],
        collections: [RecipeCollection] = [],
        collectionMemberships: [RecipeCollectionMembership] = [],
        settings: RecipeSettings = RecipeSettings(),
        deletedEntities: Set<String>? = []
    ) {
        self.version = version
        self.recipes = recipes
        self.groceries = groceries
        self.mealPlan = mealPlan
        self.collections = collections
        self.collectionMemberships = collectionMemberships
        self.settings = settings
        self.deletedEntities = deletedEntities
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case recipes
        case groceries
        case mealPlan
        case collections
        case collectionMemberships
        case settings
        case deletedEntities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        recipes = try container.decodeIfPresent([Recipe].self, forKey: .recipes) ?? []
        groceries = try container.decodeIfPresent([GroceryItem].self, forKey: .groceries) ?? []
        mealPlan = try container.decodeIfPresent([MealPlanEntry].self, forKey: .mealPlan) ?? []
        collections =
            try container.decodeIfPresent([RecipeCollection].self, forKey: .collections) ?? []
        collectionMemberships =
            try container.decodeIfPresent(
                [RecipeCollectionMembership].self,
                forKey: .collectionMemberships
            ) ?? []
        settings =
            try container.decodeIfPresent(RecipeSettings.self, forKey: .settings)
            ?? RecipeSettings()
        deletedEntities =
            try container.decodeIfPresent(Set<String>.self, forKey: .deletedEntities) ?? []
    }
}

private typealias LibrarySnapshot = RecipeLibrarySnapshot

public enum LibraryMergeEntity: String, Codable, Sendable {
    case recipe
    case grocery
    case meal
    case collection
    case membership
    case settings
}

public struct LibraryMergeConflict: Hashable, Sendable, Identifiable {
    public let entity: LibraryMergeEntity
    public let entityID: UUID?
    public let scopeID: String?

    public init(
        entity: LibraryMergeEntity,
        entityID: UUID?,
        scopeID: String? = nil
    ) {
        self.entity = entity
        self.entityID = entityID
        self.scopeID = scopeID
    }

    public var id: String {
        scopeID ?? "\(entity.rawValue):\(entityID?.uuidString ?? "settings")"
    }
}

public enum LibraryMergeSource: Sendable, Equatable, Hashable {
    case local
    case cloud
}

public struct LibraryMergeChoice: Sendable {
    public let conflict: LibraryMergeConflict
    public let source: LibraryMergeSource

    public init(conflict: LibraryMergeConflict, source: LibraryMergeSource) {
        self.conflict = conflict
        self.source = source
    }
}

private enum LibraryMergeState<Value: Hashable>: Equatable {
    case absent
    case value(Value)
    case deleted
}

/// Matches the existing grocery consolidation rule: names ignore case and
/// extra spaces, while units remain case-sensitive (t and T differ).
private struct GroceryConsolidationKey: Hashable {
    let name: String
    let unit: String
}

@Observable @MainActor
public final class RecipeStore {
    public private(set) var recipes: [Recipe] = []
    public private(set) var groceries: [GroceryItem] = []
    public private(set) var mealPlan: [MealPlanEntry] = []
    public private(set) var collections: [RecipeCollection] = []
    public private(set) var collectionMemberships: [RecipeCollectionMembership] = []
    public private(set) var settings = RecipeSettings()
    public private(set) var loadError: String?
    public private(set) var changeToken: UInt64 = 0
    private var deletedEntities: Set<String> = []

    public var hasUserData: Bool {
        !recipes.isEmpty || !groceries.isEmpty || !mealPlan.isEmpty
            || !collections.isEmpty || settings != RecipeSettings()
    }

    @ObservationIgnored private let fileURL: URL?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        reload()
    }

    public static func defaultFileURL() -> URL {
        let supportDirectory = URL.applicationSupportDirectory
        let recipeDirectory =
            supportDirectory
            .appendingPathComponent("Recipe", isDirectory: true)
        let recipeFile = recipeDirectory.appendingPathComponent("library.json")

        // Preserve existing installs that stored the library under the old Cook
        // directory. Copy once so the technical rename never loses user data.
        let legacyFile =
            supportDirectory
            .appendingPathComponent("Cook", isDirectory: true)
            .appendingPathComponent("library.json")
        let fileManager = FileManager.default

        guard !fileManager.fileExists(atPath: recipeFile.path),
            fileManager.fileExists(atPath: legacyFile.path)
        else {
            return recipeFile
        }

        do {
            try fileManager.createDirectory(
                at: recipeDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: legacyFile, to: recipeFile)
            return recipeFile
        } catch {
            // If migration cannot safely copy the file, keep using the original
            // location rather than risking an empty library.
            return legacyFile
        }
    }

    public func recipe(id: UUID) -> Recipe? {
        recipes.first { $0.id == id }
    }

    public func collection(id: UUID) -> RecipeCollection? {
        collections.first { $0.id == id }
    }

    public func collectionIDs(forRecipe recipeID: UUID) -> Set<UUID> {
        Set(
            collectionMemberships.lazy
                .filter { $0.recipeID == recipeID }
                .map(\.collectionID)
        )
    }

    public func recipes(inCollection collectionID: UUID) -> [Recipe] {
        let recipeIDs = Set(
            collectionMemberships.lazy
                .filter { $0.collectionID == collectionID }
                .map(\.recipeID)
        )
        return recipes.filter { recipeIDs.contains($0.id) }
    }

    @discardableResult
    public func createCollection(name: String) throws -> RecipeCollection {
        let cleaned = try validatedCollectionName(name)
        guard
            !collections.contains(where: {
                normalized($0.name) == normalized(cleaned)
            })
        else {
            throw RecipeStoreError.invalidValue(RecipeLanguage.localized("A collection with this name already exists."))
        }

        var next = snapshot
        let collection = RecipeCollection(name: cleaned)
        next.deletedEntities?.remove(Self.deletionKey(.collection, collection.id))
        next.collections.append(collection)
        next.collections.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        try commit(next)
        return collection
    }

    public func renameCollection(id: UUID, name: String) throws {
        guard let index = collections.firstIndex(where: { $0.id == id }) else {
            throw RecipeStoreError.missingItem
        }
        let cleaned = try validatedCollectionName(name)
        guard
            !collections.contains(where: {
                $0.id != id && normalized($0.name) == normalized(cleaned)
            })
        else {
            throw RecipeStoreError.invalidValue(RecipeLanguage.localized("A collection with this name already exists."))
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
            throw RecipeStoreError.missingItem
        }
        var next = snapshot
        next.collections.removeAll { $0.id == id }
        next.deletedEntities?.insert(Self.deletionKey(.collection, id))
        next.collectionMemberships.removeAll { $0.collectionID == id }
        try commit(next)
    }

    public func setRecipe(
        _ recipeID: UUID,
        inCollection collectionID: UUID,
        isMember: Bool
    ) throws {
        guard recipe(id: recipeID) != nil else { throw RecipeStoreError.missingRecipe }
        guard collection(id: collectionID) != nil else { throw RecipeStoreError.missingItem }

        let membership = RecipeCollectionMembership(
            recipeID: recipeID,
            collectionID: collectionID
        )
        let exists = collectionMemberships.contains(membership)
        guard exists != isMember else { return }

        var next = snapshot
        let membershipKey = Self.membershipDeletionKey(membership)
        if isMember {
            next.deletedEntities?.remove(membershipKey)
            next.collectionMemberships.append(membership)
        } else {
            next.deletedEntities?.insert(membershipKey)
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
        next.deletedEntities?.remove(Self.deletionKey(.recipe, recipe.id))
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
        next.deletedEntities?.insert(Self.deletionKey(.recipe, id))
        for membership in next.collectionMemberships where membership.recipeID == id {
            next.deletedEntities?.insert(Self.membershipDeletionKey(membership))
        }
        for entry in next.mealPlan where entry.recipeID == id {
            next.deletedEntities?.insert(Self.deletionKey(.meal, entry.id))
        }
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
            throw RecipeStoreError.missingRecipe
        }
        var next = snapshot
        next.recipes[index].isFavorite.toggle()
        next.recipes[index].updatedAt = .now
        try commit(next)
    }

    public func addToGroceries(
        recipeID: UUID,
        servings: Int?,
        ingredientIDs: Set<UUID>,
        consolidateCompatibleIngredients: Bool = true
    ) throws {
        guard let recipe = recipe(id: recipeID) else { throw RecipeStoreError.missingRecipe }
        guard ingredientIDs.isSubset(of: Set(recipe.ingredients.map(\.id))) else {
            throw RecipeStoreError.missingItem
        }
        guard !ingredientIDs.isEmpty else { return }
        if let servings, servings <= 0 {
            throw RecipeStoreError.invalidValue(RecipeLanguage.localized("Choose a serving count greater than zero."))
        }
        if servings != nil, recipe.servings == nil {
            throw RecipeStoreError.invalidValue(
                RecipeLanguage.localized("Set the recipe's original serving count before scaling it."))
        }
        let originalServings = recipe.servings ?? 1
        let requestedServings = servings ?? originalServings
        guard originalServings > 0 else {
            throw RecipeStoreError.invalidValue(
                RecipeLanguage.localized("The recipe's serving count must be greater than zero."))
        }

        var next = snapshot
        var consolidationIndices: [GroceryConsolidationKey: Int] = [:]

        if consolidateCompatibleIngredients {
            // Preserve the original first-unchecked-match behavior when two
            // existing grocery rows have the same name and unit.
            for (index, grocery) in next.groceries.enumerated()
            where !grocery.isChecked && grocery.quantity != nil {
                let key = GroceryConsolidationKey(
                    name: normalized(grocery.name),
                    unit: unitKey(grocery.unit)
                )
                if consolidationIndices[key] == nil {
                    consolidationIndices[key] = index
                }
            }
        }

        for ingredient in recipe.ingredients where ingredientIDs.contains(ingredient.id) {
            guard !normalized(ingredient.name).isEmpty else {
                throw RecipeStoreError.invalidValue(
                    RecipeLanguage.localized("Give each selected ingredient a name before adding it."))
            }

            let item = try groceryItem(
                from: ingredient, recipeID: recipeID,
                originalServings: originalServings,
                requestedServings: requestedServings
            )
            let key = GroceryConsolidationKey(
                name: normalized(item.name),
                unit: unitKey(item.unit)
            )

            if consolidateCompatibleIngredients,
                let index = consolidationIndices[key],
                var existing = next.groceries[index].quantity,
                var added = item.quantity
            {
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
                // The next selected ingredient may combine with this new row.
                if consolidateCompatibleIngredients,
                    item.quantity != nil,
                    consolidationIndices[key] == nil
                {
                    consolidationIndices[key] = next.groceries.count - 1
                }
            }
        }
        try commit(next)
    }

    public func upsertGrocery(_ item: GroceryItem) throws {
        var next = snapshot
        next.deletedEntities?.remove(Self.deletionKey(.grocery, item.id))
        if let index = next.groceries.firstIndex(where: { $0.id == item.id }) {
            next.groceries[index] = item
        } else {
            next.groceries.append(item)
        }
        try commit(next)
    }

    public func toggleGrocery(id: UUID) throws {
        guard let index = groceries.firstIndex(where: { $0.id == id }) else {
            throw RecipeStoreError.missingItem
        }
        var next = snapshot
        next.groceries[index].isChecked.toggle()
        try commit(next)
    }

    public func deleteGrocery(id: UUID) throws {
        var next = snapshot
        next.groceries.removeAll { $0.id == id }
        next.deletedEntities?.insert(Self.deletionKey(.grocery, id))
        try commit(next)
    }

    public func clearCheckedGroceries() throws {
        var next = snapshot
        for item in next.groceries where item.isChecked {
            next.deletedEntities?.insert(Self.deletionKey(.grocery, item.id))
        }
        next.groceries.removeAll(where: \.isChecked)
        try commit(next)
    }

    public func upsertMeal(_ entry: MealPlanEntry) throws {
        guard recipe(id: entry.recipeID) != nil else { throw RecipeStoreError.missingRecipe }
        guard entry.date.timeIntervalSinceReferenceDate.isFinite else {
            throw RecipeStoreError.invalidValue(RecipeLanguage.localized("Choose a valid date for your meal."))
        }
        var next = snapshot
        next.deletedEntities?.remove(Self.deletionKey(.meal, entry.id))
        var saved = entry
        saved.date = Calendar.current.startOfDay(for: entry.date)
        // One recipe per day and meal slot, including when editing an existing entry.
        let replacedIDs = next.mealPlan.filter {
            $0.id == entry.id
                || ($0.slot == entry.slot
                    && Calendar.current.isDate($0.date, inSameDayAs: entry.date))
        }.map(\.id).filter { $0 != entry.id }
        for replacedID in replacedIDs {
            next.deletedEntities?.insert(Self.deletionKey(.meal, replacedID))
        }
        next.mealPlan.removeAll {
            $0.id == entry.id
                || ($0.slot == entry.slot
                    && Calendar.current.isDate($0.date, inSameDayAs: entry.date))
        }
        next.mealPlan.append(saved)
        next.mealPlan.sort { $0.date < $1.date }
        try commit(next)
    }

    public func deleteMeal(id: UUID) throws {
        var next = snapshot
        next.mealPlan.removeAll { $0.id == id }
        next.deletedEntities?.insert(Self.deletionKey(.meal, id))
        try commit(next)
    }

    public func updateSettings(_ settings: RecipeSettings) throws {
        var next = snapshot
        next.settings = settings
        try commit(next)
    }

    public func reload() {
        guard let fileURL else {
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            var loaded = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
            try validate(loaded)
            if migrateKnownSampleCover(in: &loaded) {
                try encoded(loaded).write(to: fileURL, options: .atomic)
            }
            publish(loaded)
            loadError = nil
        } catch {
            let cocoaError = error as NSError
            if cocoaError.domain == NSCocoaErrorDomain
                && cocoaError.code == NSFileReadNoSuchFileError
            {
                publish(LibrarySnapshot())
                loadError = nil
            } else {
                // Do not replace either the original file or the last good in-memory data.
                loadError = error.localizedDescription
            }
        }
    }

    private func migrateKnownSampleCover(in snapshot: inout LibrarySnapshot) -> Bool {
        // Migrate only this sample's stale bundled default; preserve user-selected coverData.
        guard
            let index = snapshot.recipes.firstIndex(where: {
                $0.id == SampleRecipes.roastChickenID
                    && $0.coverAsset == "salmon"
                    && $0.coverData == nil
            })
        else {
            return false
        }

        snapshot.recipes[index].coverAsset = "chicken"
        return true
    }

    /// Erase this device's library without creating cloud deletion tombstones.
    /// The caller must invalidate the previous cloud lineage before invoking
    /// this mutation, so an I/O failure cannot cause an empty-library upload.
    public func clearLocalLibraryOnly() throws {
        try commit(LibrarySnapshot())
    }

    /// Remove a legacy file only after the canonical empty snapshot is saved.
    /// Failure here must never retain a usable cloud baseline for re-upload.
    public func removeLegacyLibraryCopyAfterLocalErase() throws {
        let support = URL.applicationSupportDirectory
        let canonical =
            support
            .appendingPathComponent("Recipe", isDirectory: true)
            .appendingPathComponent("library.json")
        let legacy =
            support
            .appendingPathComponent("Cook", isDirectory: true)
            .appendingPathComponent("library.json")

        // If the app still uses the legacy path as its active storage because
        // migration failed, do not remove that newly emptied active file.
        guard fileURL?.standardizedFileURL == canonical.standardizedFileURL,
            FileManager.default.fileExists(atPath: legacy.path)
        else {
            return
        }
        try FileManager.default.removeItem(at: legacy)
    }

    public func resetLibrary() throws {
        var empty = LibrarySnapshot()
        empty.deletedEntities = deletedEntities
        empty.deletedEntities?.formUnion(recipes.map { Self.deletionKey(.recipe, $0.id) })
        empty.deletedEntities?.formUnion(groceries.map { Self.deletionKey(.grocery, $0.id) })
        empty.deletedEntities?.formUnion(mealPlan.map { Self.deletionKey(.meal, $0.id) })
        empty.deletedEntities?.formUnion(collections.map { Self.deletionKey(.collection, $0.id) })
        try commit(empty)
    }

    public func loadSampleRecipes() throws {
        var next = snapshot
        let existingIDs = Set(next.recipes.map(\.id))
        let samplesToAdd = SampleRecipes.recipes.filter { !existingIDs.contains($0.id) }

        for recipe in samplesToAdd {
            next.deletedEntities?.remove(Self.deletionKey(.recipe, recipe.id))
        }
        next.recipes.append(contentsOf: samplesToAdd)
        try commit(next)
    }

    public func exportData() throws -> Data {
        if let loadError { throw RecipeStoreError.unreadableLibrary(loadError) }
        return try encoded(snapshot)
    }

    public func exportCloudSnapshot() throws -> RecipeLibrarySnapshot {
        if let loadError { throw RecipeStoreError.unreadableLibrary(loadError) }
        return snapshot
    }

    public func replaceLibrary(with data: Data) throws {
        if let loadError { throw RecipeStoreError.unreadableLibrary(loadError) }
        let incoming = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        try validate(incoming)
        try commit(incoming)
    }

    public func replaceLibrary(with snapshot: RecipeLibrarySnapshot) throws {
        if let loadError { throw RecipeStoreError.unreadableLibrary(loadError) }
        try validate(snapshot)
        try commit(snapshot)
    }

    /// Performs a three-way merge against the last shared base and reports unresolved conflicts.
    /// Local values remain selected until the caller supplies an explicit choice.
    @discardableResult
    public func mergeCloudLibrary(
        with data: Data,
        base: RecipeLibrarySnapshot? = nil,
        choices: [LibraryMergeChoice] = []
    ) throws -> [LibraryMergeConflict] {
        let cloud = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        return try mergeCloudLibrary(
            with: cloud,
            base: base,
            choices: choices
        )
    }

    /// Decodes a cloud snapshot, then applies the same validated three-way merge as the typed API.
    @discardableResult
    public func mergeCloudLibrary(
        with cloud: RecipeLibrarySnapshot,
        base: RecipeLibrarySnapshot? = nil,
        choices: [LibraryMergeChoice] = []
    ) throws -> [LibraryMergeConflict] {
        if let loadError {
            throw RecipeStoreError.unreadableLibrary(loadError)
        }

        try validate(cloud)
        let ancestor = base ?? LibrarySnapshot()
        try validate(ancestor)

        let local = snapshot
        let localDeleted = local.deletedEntities ?? []
        let cloudDeleted = cloud.deletedEntities ?? []
        let baseDeleted = ancestor.deletedEntities ?? []
        var mergedDeleted = localDeleted.union(cloudDeleted).union(baseDeleted)

        var choicesByID: [String: LibraryMergeSource] = [:]
        for choice in choices {
            choicesByID[choice.conflict.id] = choice.source
        }

        var conflictsByID: [String: LibraryMergeConflict] = [:]

        func record(_ conflict: LibraryMergeConflict) {
            conflictsByID[conflict.id] = conflict
        }

        func itemState<T: Hashable>(
            id: UUID,
            values: [UUID: T],
            deleted: Set<String>,
            entity: LibraryMergeEntity
        ) -> LibraryMergeState<T> {
            if deleted.contains(Self.deletionKey(entity, id)) {
                return .deleted
            }
            if let value = values[id] {
                return .value(value)
            }
            return .absent
        }

        func selectedState<T: Hashable>(
            local: LibraryMergeState<T>,
            cloud: LibraryMergeState<T>,
            base: LibraryMergeState<T>,
            conflict: LibraryMergeConflict
        ) -> LibraryMergeState<T> {
            if local == cloud {
                return local
            }
            if local == base {
                return cloud
            }
            if cloud == base {
                return local
            }
            if let source = choicesByID[conflict.id] {
                return source == .local ? local : cloud
            }

            record(conflict)
            return local
        }

        func mergeItems<T: Identifiable & Hashable>(
            local localItems: [T],
            cloud cloudItems: [T],
            base baseItems: [T],
            entity: LibraryMergeEntity
        ) -> [T] where T.ID == UUID {
            let localByID = Dictionary(
                uniqueKeysWithValues: localItems.map { ($0.id, $0) }
            )
            let cloudByID = Dictionary(
                uniqueKeysWithValues: cloudItems.map { ($0.id, $0) }
            )
            let baseByID = Dictionary(
                uniqueKeysWithValues: baseItems.map { ($0.id, $0) }
            )

            let ids = Set(localByID.keys)
                .union(cloudByID.keys)
                .union(baseByID.keys)
                .union(
                    localDeleted.compactMap {
                        Self.deletedID($0, entity: entity)
                    }
                )
                .union(
                    cloudDeleted.compactMap {
                        Self.deletedID($0, entity: entity)
                    }
                )
                .union(
                    baseDeleted.compactMap {
                        Self.deletedID($0, entity: entity)
                    })

            var result: [T] = []

            for id in ids {
                let localState = itemState(
                    id: id,
                    values: localByID,
                    deleted: localDeleted,
                    entity: entity
                )
                let cloudState = itemState(
                    id: id,
                    values: cloudByID,
                    deleted: cloudDeleted,
                    entity: entity
                )
                let baseState = itemState(
                    id: id,
                    values: baseByID,
                    deleted: baseDeleted,
                    entity: entity
                )
                let conflict = LibraryMergeConflict(
                    entity: entity,
                    entityID: id
                )
                let selected = selectedState(
                    local: localState,
                    cloud: cloudState,
                    base: baseState,
                    conflict: conflict
                )
                let deletionKey = Self.deletionKey(entity, id)

                switch selected {
                case .value(let value):
                    mergedDeleted.remove(deletionKey)
                    result.append(value)
                case .deleted:
                    mergedDeleted.insert(deletionKey)
                case .absent:
                    mergedDeleted.remove(deletionKey)
                }
            }

            return result
        }

        func membershipState(
            _ membership: RecipeCollectionMembership,
            values: Set<RecipeCollectionMembership>,
            deleted: Set<String>
        ) -> LibraryMergeState<RecipeCollectionMembership> {
            if deleted.contains(Self.membershipDeletionKey(membership)) {
                return .deleted
            }
            if values.contains(membership) {
                return .value(membership)
            }
            return .absent
        }

        let localMemberships = Set(local.collectionMemberships)
        let cloudMemberships = Set(cloud.collectionMemberships)
        let baseMemberships = Set(ancestor.collectionMemberships)
        var allMemberships =
            localMemberships
            .union(cloudMemberships)
            .union(baseMemberships)

        for key in localDeleted.union(cloudDeleted).union(baseDeleted) {
            if let membership = Self.membershipFromDeletionKey(key) {
                allMemberships.insert(membership)
            }
        }

        var memberships: Set<RecipeCollectionMembership> = []
        for membership in allMemberships {
            let key = Self.membershipDeletionKey(membership)
            let conflict = LibraryMergeConflict(
                entity: .membership,
                entityID: membership.collectionID,
                scopeID: key
            )
            let selected = selectedState(
                local: membershipState(
                    membership,
                    values: localMemberships,
                    deleted: localDeleted
                ),
                cloud: membershipState(
                    membership,
                    values: cloudMemberships,
                    deleted: cloudDeleted
                ),
                base: membershipState(
                    membership,
                    values: baseMemberships,
                    deleted: baseDeleted
                ),
                conflict: conflict
            )

            switch selected {
            case .value:
                mergedDeleted.remove(key)
                memberships.insert(membership)
            case .deleted:
                mergedDeleted.insert(key)
            case .absent:
                mergedDeleted.remove(key)
            }
        }

        var merged = LibrarySnapshot(
            recipes: mergeItems(
                local: local.recipes,
                cloud: cloud.recipes,
                base: ancestor.recipes,
                entity: .recipe
            ),
            groceries: mergeItems(
                local: local.groceries,
                cloud: cloud.groceries,
                base: ancestor.groceries,
                entity: .grocery
            ),
            mealPlan: mergeItems(
                local: local.mealPlan,
                cloud: cloud.mealPlan,
                base: ancestor.mealPlan,
                entity: .meal
            ),
            collections: mergeItems(
                local: local.collections,
                cloud: cloud.collections,
                base: ancestor.collections,
                entity: .collection
            ),
            collectionMemberships: Array(memberships),
            settings: local.settings,
            deletedEntities: mergedDeleted
        )

        let settingsConflict = LibraryMergeConflict(
            entity: .settings,
            entityID: nil
        )
        if local.settings == cloud.settings {
            merged.settings = local.settings
        } else if local.settings == ancestor.settings {
            merged.settings = cloud.settings
        } else if cloud.settings == ancestor.settings {
            merged.settings = local.settings
        } else if let source = choicesByID[settingsConflict.id] {
            merged.settings =
                source == .local
                ? local.settings
                : cloud.settings
        } else {
            record(settingsConflict)
        }

        resolveCollectionNameCollisions(
            in: &merged,
            local: local,
            cloud: cloud,
            choicesByID: choicesByID,
            conflictsByID: &conflictsByID
        )
        resolveMealSlotCollisions(
            in: &merged,
            local: local,
            cloud: cloud,
            choicesByID: choicesByID,
            conflictsByID: &conflictsByID
        )

        let conflicts = conflictsByID.values.sorted { $0.id < $1.id }
        guard conflicts.isEmpty else {
            return conflicts
        }

        let recipeIDs = Set(merged.recipes.map(\.id))
        let collectionIDs = Set(merged.collections.map(\.id))

        for membership in merged.collectionMemberships
        where !recipeIDs.contains(membership.recipeID)
            || !collectionIDs.contains(membership.collectionID)
        {
            merged.deletedEntities?.insert(
                Self.membershipDeletionKey(membership)
            )
        }
        merged.collectionMemberships.removeAll {
            !recipeIDs.contains($0.recipeID)
                || !collectionIDs.contains($0.collectionID)
        }

        for entry in merged.mealPlan
        where !recipeIDs.contains(entry.recipeID) {
            merged.deletedEntities?.insert(
                Self.deletionKey(.meal, entry.id)
            )
        }
        merged.mealPlan.removeAll {
            !recipeIDs.contains($0.recipeID)
        }

        for index in merged.groceries.indices {
            merged.groceries[index].recipeIDs.removeAll {
                !recipeIDs.contains($0)
            }
        }

        try commit(merged)
        return []
    }

    private func resolveCollectionNameCollisions(
        in merged: inout LibrarySnapshot,
        local: LibrarySnapshot,
        cloud: LibrarySnapshot,
        choicesByID: [String: LibraryMergeSource],
        conflictsByID: inout [String: LibraryMergeConflict]
    ) {
        let groups = Dictionary(
            grouping: merged.collections,
            by: { normalized($0.name) }
        )

        for (nameKey, values) in groups where values.count > 1 {
            let conflict = LibraryMergeConflict(
                entity: .collection,
                entityID: nil,
                scopeID: "collection-name:\(nameKey)"
            )
            guard let source = choicesByID[conflict.id] else {
                conflictsByID[conflict.id] = conflict
                continue
            }

            let sourceCollections =
                source == .local
                ? local.collections
                : cloud.collections
            guard
                let winner = sourceCollections.first(where: {
                    normalized($0.name) == nameKey
                })
            else {
                conflictsByID[conflict.id] = conflict
                continue
            }

            let losingIDs = Set(
                values.map(\.id).filter { $0 != winner.id }
            )
            for losingID in losingIDs {
                merged.deletedEntities?.insert(
                    Self.deletionKey(.collection, losingID)
                )
            }
            for membership in merged.collectionMemberships
            where losingIDs.contains(membership.collectionID) {
                merged.deletedEntities?.insert(
                    Self.membershipDeletionKey(membership)
                )
            }
            merged.collectionMemberships.removeAll {
                losingIDs.contains($0.collectionID)
            }
            merged.collections.removeAll {
                losingIDs.contains($0.id)
            }
        }
    }

    private func resolveMealSlotCollisions(
        in merged: inout LibrarySnapshot,
        local: LibrarySnapshot,
        cloud: LibrarySnapshot,
        choicesByID: [String: LibraryMergeSource],
        conflictsByID: inout [String: LibraryMergeConflict]
    ) {
        let groups = Dictionary(
            grouping: merged.mealPlan,
            by: mealSlotKey
        )

        for (slotKey, values) in groups where values.count > 1 {
            let conflict = LibraryMergeConflict(
                entity: .meal,
                entityID: nil,
                scopeID: "meal-slot:\(slotKey)"
            )
            guard let source = choicesByID[conflict.id] else {
                conflictsByID[conflict.id] = conflict
                continue
            }

            let sourceMeals =
                source == .local
                ? local.mealPlan
                : cloud.mealPlan
            guard
                let winner = sourceMeals.first(where: {
                    mealSlotKey($0) == slotKey
                })
            else {
                conflictsByID[conflict.id] = conflict
                continue
            }

            let losingIDs = Set(
                values.map(\.id).filter { $0 != winner.id }
            )
            for losingID in losingIDs {
                merged.deletedEntities?.insert(
                    Self.deletionKey(.meal, losingID)
                )
            }
            merged.mealPlan.removeAll {
                losingIDs.contains($0.id)
            }
        }
    }

    private func mealSlotKey(_ entry: MealPlanEntry) -> String {
        let day = Calendar.current
            .startOfDay(for: entry.date)
            .timeIntervalSinceReferenceDate
        return "\(day):\(entry.slot.rawValue)"
    }

    private var snapshot: LibrarySnapshot {
        LibrarySnapshot(
            recipes: recipes,
            groceries: groceries,
            mealPlan: mealPlan,
            collections: collections,
            collectionMemberships: collectionMemberships,
            settings: settings,
            deletedEntities: deletedEntities
        )
    }

    private func commit(_ next: LibrarySnapshot) throws {
        if let loadError { throw RecipeStoreError.unreadableLibrary(loadError) }
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
        deletedEntities = snapshot.deletedEntities ?? []
        changeToken &+= 1
    }

    private func validate(_ snapshot: LibrarySnapshot) throws {
        guard snapshot.version == 1 || snapshot.version == 2 else {
            throw RecipeStoreError.unsupportedVersion(snapshot.version)
        }
        func unique(_ ids: [UUID]) -> Bool { Set(ids).count == ids.count }
        guard unique(snapshot.recipes.map(\.id)), unique(snapshot.groceries.map(\.id)),
            unique(snapshot.mealPlan.map(\.id)), unique(snapshot.collections.map(\.id))
        else {
            throw RecipeStoreError.invalidValue(RecipeLanguage.localized("The library contains duplicate identifiers."))
        }
        let recipeIDs = Set(snapshot.recipes.map(\.id))
        let collectionIDs = Set(snapshot.collections.map(\.id))
        let deletedEntities = snapshot.deletedEntities ?? []
        guard
            !snapshot.recipes.contains(where: {
                deletedEntities.contains(Self.deletionKey(.recipe, $0.id))
            }),
            !snapshot.groceries.contains(where: {
                deletedEntities.contains(Self.deletionKey(.grocery, $0.id))
            }),
            !snapshot.mealPlan.contains(where: {
                deletedEntities.contains(Self.deletionKey(.meal, $0.id))
            }),
            !snapshot.collections.contains(where: {
                deletedEntities.contains(Self.deletionKey(.collection, $0.id))
            }),
            !snapshot.collectionMemberships.contains(where: {
                deletedEntities.contains(Self.membershipDeletionKey($0))
            })
        else {
            throw RecipeStoreError.invalidValue(
                RecipeLanguage.localized("The library contains an item that is also marked as deleted."))
        }

        var collectionNameKeys: Set<String> = []
        for collection in snapshot.collections {
            let name = collection.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                collection.createdAt.timeIntervalSinceReferenceDate.isFinite,
                collection.updatedAt.timeIntervalSinceReferenceDate.isFinite,
                collectionNameKeys.insert(normalized(name)).inserted
            else {
                throw RecipeStoreError.invalidValue(
                    RecipeLanguage.localized("Collection names must be unique and cannot be empty.")
                )
            }
        }

        var membershipKeys: Set<String> = []
        for membership in snapshot.collectionMemberships {
            guard recipeIDs.contains(membership.recipeID),
                collectionIDs.contains(membership.collectionID),
                membershipKeys.insert(
                    "\(membership.recipeID.uuidString):\(membership.collectionID.uuidString)"
                ).inserted
            else {
                throw RecipeStoreError.invalidValue(
                    RecipeLanguage.localized("A collection contains an unavailable or duplicate recipe relationship.")
                )
            }
        }

        for recipe in snapshot.recipes {
            guard recipe.servings.map({ $0 > 0 }) ?? true,
                recipe.prepMinutes.map({ $0 >= 0 }) ?? true,
                recipe.cookMinutes.map({ $0 >= 0 }) ?? true,
                unique(recipe.ingredients.map(\.id)), unique(recipe.steps.map(\.id)),
                recipe.createdAt.timeIntervalSinceReferenceDate.isFinite,
                recipe.updatedAt.timeIntervalSinceReferenceDate.isFinite
            else {
                throw RecipeStoreError.invalidValue(
                    RecipeLanguage.localized("Check the recipe's servings, times and ingredient identifiers."))
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
                    step.timers.allSatisfy({ $0.durationSeconds > 0 })
                else {
                    throw RecipeStoreError.invalidValue(
                        RecipeLanguage.localized("Check the cooking step's ingredient links and timers.")
                    )
                }
            }
        }
        for item in snapshot.groceries {
            guard !normalized(item.name).isEmpty, Set(item.recipeIDs).isSubset(of: recipeIDs),
                unique(item.recipeIDs)
            else {
                throw RecipeStoreError.invalidValue(
                    RecipeLanguage.localized("Check the grocery item's name and recipe sources."))
            }
            _ = try IngredientAmount(
                originalText: item.amountText, value: item.quantity, unit: item.unit)
        }
        var occupiedSlots: Set<String> = []
        for entry in snapshot.mealPlan {
            guard recipeIDs.contains(entry.recipeID),
                entry.date.timeIntervalSinceReferenceDate.isFinite
            else {
                throw RecipeStoreError.invalidValue(
                    RecipeLanguage.localized("A meal plan refers to an unavailable recipe or date."))
            }
            let day = Calendar.current.startOfDay(for: entry.date).timeIntervalSinceReferenceDate
            guard occupiedSlots.insert("\(day):\(entry.slot.rawValue)").inserted else {
                throw RecipeStoreError.invalidValue(
                    RecipeLanguage.localized("A day contains more than one recipe in the same meal slot."))
            }
        }
    }

    private func validatedCollectionName(_ name: String) throws -> String {
        let cleaned =
            name
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw RecipeStoreError.invalidValue(RecipeLanguage.localized("Give the collection a name."))
        }
        guard cleaned.count <= 80 else {
            throw RecipeStoreError.invalidValue(RecipeLanguage.localized("Collection names can be up to 80 characters."))
        }
        guard normalized(cleaned) != "favorites" else {
            throw RecipeStoreError.invalidValue(RecipeLanguage.localized("Favorites is already built in."))
        }
        return cleaned
    }

    private static func deletionKey(_ entity: LibraryMergeEntity, _ id: UUID) -> String {
        "\(entity.rawValue):\(id.uuidString)"
    }

    private static func deletedID(_ key: String, entity: LibraryMergeEntity) -> UUID? {
        guard key.hasPrefix(entity.rawValue + ":") else { return nil }
        return UUID(uuidString: String(key.dropFirst(entity.rawValue.count + 1)))
    }

    private static func membershipDeletionKey(
        _ membership: RecipeCollectionMembership
    ) -> String {
        "membership:\(membership.collectionID.uuidString):\(membership.recipeID.uuidString)"
    }

    private static func membershipFromDeletionKey(
        _ key: String
    ) -> RecipeCollectionMembership? {
        let parts = key.split(separator: ":")
        guard parts.count == 3,
            parts[0] == "membership",
            let collectionID = UUID(uuidString: String(parts[1])),
            let recipeID = UUID(uuidString: String(parts[2]))
        else {
            return nil
        }
        return RecipeCollectionMembership(
            recipeID: recipeID,
            collectionID: collectionID
        )
    }

    private func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    private func unitKey(_ unit: String?) -> String {
        // Case can carry meaning, such as t (teaspoon) versus T (tablespoon).
        (unit ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func groceryItem(
        from ingredient: RecipeIngredient, recipeID: UUID,
        originalServings: Int, requestedServings: Int
    ) throws -> GroceryItem {
        let source = try IngredientAmount(
            originalText: ingredient.amountText,
            value: ingredient.quantity, unit: ingredient.unit)
        var quantity = source.value
        var text = source.originalText
        if quantity != nil, originalServings != requestedServings {
            let multiplied = try source.scaled(by: Decimal(requestedServings))
            if let numerator = multiplied.value {
                if let divided = try RecipeIngredient.exactQuotient(
                    numerator, by: Decimal(originalServings))
                {
                    quantity = divided
                } else {
                    // Keep an exact visible expression instead of inventing a rounded quantity.
                    quantity = nil
                    text =
                        "\(ingredient.displayAmount()) × \(requestedServings)/\(originalServings)"
                }
            }
        }
        if let quantity {
            text = RecipeIngredient.formatted(quantity, unit: ingredient.unit)
        }
        return GroceryItem(
            name: ingredient.name, amountText: text, quantity: quantity,
            unit: ingredient.unit, category: ingredient.category, recipeIDs: [recipeID])
    }
}
