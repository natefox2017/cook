import Foundation
import Observation

@MainActor @Observable
final class CookStore {
    private(set) var snapshot = LocalSnapshot()
    private(set) var loadError: String?
    private(set) var loaded = false
    private let directory: URL
    private let fileManager: FileManager
    private var snapshotURL: URL { directory.appendingPathComponent("collection.json") }

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cook", isDirectory: true)
        reload()
    }

    func reload() {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: snapshotURL.path) {
                let candidate = try JSONDecoder().decode(LocalSnapshot.self, from: Data(contentsOf: snapshotURL))
                guard candidate.version == 1 else { throw LocalStoreError.unsupportedVersion }
                snapshot = candidate
            }
            loadError = nil
            loaded = true
        } catch {
            loadError = error.localizedDescription
            loaded = false
        }
    }

    private func commit(_ candidate: LocalSnapshot) throws {
        // Never overwrite unreadable or newer user data with an empty collection.
        guard loaded else { throw LocalStoreError.unsupportedVersion }
        let data = try JSONEncoder().encode(candidate)
        try data.write(to: snapshotURL, options: [.atomic])
        snapshot = candidate
    }

    func save(_ recipe: RecipeRecord) throws {
        var next = snapshot
        if let index = next.recipes.firstIndex(where: { $0.id == recipe.id }) { next.recipes[index] = recipe }
        else { next.recipes.insert(recipe, at: 0) }
        try commit(next)
    }

    func toggleFavorite(_ id: UUID) throws {
        var next = snapshot
        guard let index = next.recipes.firstIndex(where: { $0.id == id }) else { return }
        next.recipes[index].favorite.toggle()
        try commit(next)
    }

    func toggleGrocery(_ id: UUID) throws {
        var next = snapshot
        guard let index = next.groceries.firstIndex(where: { $0.id == id }) else { return }
        next.groceries[index].checked.toggle()
        try commit(next)
    }

    func updateGrocery(_ item: GroceryRecord) throws {
        var next = snapshot
        guard let index = next.groceries.firstIndex(where: { $0.id == item.id }) else { return }
        next.groceries[index] = item
        try commit(next)
    }

    func addGroceries(from recipe: RecipeRecord, servings: Int) throws {
        var next = snapshot
        for ingredient in recipe.ingredients {
            let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let display = ingredient.displayedAmount(for: servings, originalServings: recipe.servings)
            let scaled = ingredient.amount.isEmpty ? nil : Quantity.parse(ingredient.amount).flatMap { quantity in
                guard let original = recipe.servings, original > 0 else { return quantity }
                return Quantity.multiply(quantity, by: Decimal(servings) / Decimal(original))
            }
            // Only combine explicit amounts with the exact same unit. No cross-unit guessing.
            let key = name.lowercased()
            if let scaled,
               let index = next.groceries.firstIndex(where: {
                   !$0.checked && $0.name.lowercased() == key &&
                   $0.unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ==
                   ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() &&
                   Quantity.parse($0.amount) != nil
               }),
               let existing = Quantity.parse(next.groceries[index].amount),
               let total = Quantity.add(existing, scaled) {
                next.groceries[index].amount = Quantity.format(total)
                if !next.groceries[index].sourceRecipeIDs.contains(recipe.id) {
                    next.groceries[index].sourceRecipeIDs.append(recipe.id)
                }
            } else {
                next.groceries.append(GroceryRecord(name: name,
                    amount: scaled.map(Quantity.format) ?? display,
                    unit: scaled == nil ? "" : ingredient.unit,
                    sourceRecipeIDs: [recipe.id]))
            }
        }
        try commit(next)
    }

    func captureURL(_ raw: String) throws -> LocalCapture {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { throw LocalStoreError.invalidURL }
        if let existing = snapshot.captures.first(where: { $0.kind == .url && $0.value == url.absoluteString }) {
            return existing
        }
        let capture = LocalCapture(kind: .url, value: url.absoluteString)
        var next = snapshot
        next.captures.insert(capture, at: 0)
        try commit(next)
        return capture
    }

    func captureText(_ raw: String) throws -> LocalCapture {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw LocalStoreError.emptyInput }
        let capture = LocalCapture(kind: .text, value: value)
        var next = snapshot
        next.captures.insert(capture, at: 0)
        try commit(next)
        return capture
    }

    func captureAttachment(_ data: Data, kind: LocalCapture.Kind, extension suffix: String) throws -> LocalCapture {
        guard !data.isEmpty else { throw LocalStoreError.emptyInput }
        guard data.count <= 20 * 1024 * 1024 else { throw LocalStoreError.oversizedAttachment }
        let captureID = UUID()
        let filename = captureID.uuidString + "." + suffix
        let location = directory.appendingPathComponent(filename)
        try data.write(to: location, options: [.atomic])
        do {
            let capture = LocalCapture(id: captureID, kind: kind, value: kind == .image ? String(localized: "Recipe photo") : String(localized: "Recipe document"),
                                       attachmentName: filename)
            var next = snapshot
            next.captures.insert(capture, at: 0)
            try commit(next)
            return capture
        } catch {
            try? fileManager.removeItem(at: location)
            throw error
        }
    }

    func resolve(_ field: ReviewField, in recipe: RecipeRecord, keep: Bool) throws {
        var updated = recipe
        if !keep { updated.ingredients.removeAll { $0.id == field.ingredientID } }
        updated.reviewFields.removeAll { $0.id == field.id }
        try save(updated)
    }
}
