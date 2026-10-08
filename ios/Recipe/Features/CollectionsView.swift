// Developer: gengyun
// Purpose: Implements CollectionsView for the Recipe iOS app.

import RecipeCore
import SwiftUI

struct CollectionsView: View {
    @Environment(RecipeStore.self) private var store
    @AppStorage("recipe.collections") private var legacyEncoded = ""
    @State private var newName = ""
    @State private var editingCollection: RecipeCollection?
    @State private var pendingDelete: RecipeCollection?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    TextField("New collection", text: $newName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(addCollection)

                    Button("Add", action: addCollection)
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section {
                NavigationLink {
                    FavoriteRecipesView()
                } label: {
                    CollectionRow(
                        name: "Favorites",
                        systemImage: "heart.fill",
                        count: store.recipes.filter(\.isFavorite).count
                    )
                }

                ForEach(store.collections) { collection in
                    NavigationLink {
                        CollectionDetailView(collectionID: collection.id)
                    } label: {
                        CollectionRow(
                            name: collection.name,
                            systemImage: "folder",
                            count: store.recipes(inCollection: collection.id).count
                        )
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            pendingDelete = collection
                        }
                        Button("Rename") {
                            editingCollection = collection
                        }
                        .tint(.secondary)
                    }
                    .contextMenu {
                        Button("Rename") {
                            editingCollection = collection
                        }
                        Button("Delete", role: .destructive) {
                            pendingDelete = collection
                        }
                    }
                }
            } header: {
                Text("Collections")
            } footer: {
                Text("A recipe can belong to more than one collection. Favorites stays separate.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .navigationTitle("Collections")
        .navigationBarTitleDisplayMode(.inline)
        .task { migrateLegacyCollectionsIfNeeded() }
        .sheet(item: $editingCollection) { collection in
            RenameCollectionSheet(collection: collection)
        }
        .confirmationDialog(
            "Delete collection?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Collection", role: .destructive) {
                deletePendingCollection()
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("Recipes stay in your library. Only this collection and its memberships are removed.")
        }
        .alert(
            "Collections",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func addCollection() {
        do {
            try store.createCollection(name: newName)
            newName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePendingCollection() {
        guard let collection = pendingDelete else { return }
        do {
            try store.deleteCollection(id: collection.id)
            pendingDelete = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func migrateLegacyCollectionsIfNeeded() {
        let names =
            legacyEncoded
            .split(separator: "|")
            .map(String.init)

        guard !names.isEmpty else { return }

        do {
            _ = try store.importLegacyCollectionNames(names)
            // Clear only after the store accepted the migration. If persistence
            // fails, the legacy value remains so the migration can retry.
            legacyEncoded = ""
        } catch {
            errorMessage = String(
                localized:
                    "Your older collection names are still safe. Migration can be retried. \(error.localizedDescription)"
            )
        }
    }
}

private struct CollectionRow: View {
    let name: String
    let systemImage: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(RecipeTheme.accentForeground)
                .frame(width: 28)
            Text(name)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(minHeight: 44)
    }
}

private struct FavoriteRecipesView: View {
    @Environment(RecipeStore.self) private var store

    var body: some View {
        List {
            if store.recipes.contains(where: \.isFavorite) {
                ForEach(store.recipes.filter(\.isFavorite)) { recipe in
                    NavigationLink {
                        RecipeDetailView(recipeID: recipe.id)
                    } label: {
                        CollectionRecipeRow(recipe: recipe)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No favorites yet",
                    systemImage: "heart",
                    description: Text("Tap the heart on a recipe to keep your go-to dishes here.")
                )
            }
        }
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CollectionDetailView: View {
    let collectionID: UUID

    @Environment(RecipeStore.self) private var store
    @State private var searchText = ""
    @State private var isManagingRecipes = false
    @State private var errorMessage: String?

    private var collection: RecipeCollection? {
        store.collection(id: collectionID)
    }

    private var visibleRecipes: [Recipe] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.recipes(inCollection: collectionID)
            .filter { recipe in
                query.isEmpty
                    || ([recipe.title, recipe.summary, recipe.notes]
                        + recipe.ingredients.map(\.name))
                .joined(separator: "\n")
                .localizedStandardContains(query)
            }
            .sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    var body: some View {
        Group {
            if let collection {
                List {
                    if visibleRecipes.isEmpty {
                        ContentUnavailableView(
                            searchText.isEmpty ? "No recipes yet" : "No recipes found",
                            systemImage: "folder",
                            description: Text(
                                searchText.isEmpty
                                    ? "Add recipes from this collection or from any recipe page."
                                    : "Try another search."
                            )
                        )
                    } else {
                        ForEach(visibleRecipes) { recipe in
                            NavigationLink {
                                RecipeDetailView(recipeID: recipe.id)
                            } label: {
                                CollectionRecipeRow(recipe: recipe)
                            }
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    remove(recipe.id)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(RecipeTheme.canvas)
                .navigationTitle(collection.name)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, prompt: "Search this collection")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Manage Recipes", systemImage: "plus") {
                            isManagingRecipes = true
                        }
                    }
                }
                .sheet(isPresented: $isManagingRecipes) {
                    CollectionRecipePickerSheet(collectionID: collectionID)
                }
            } else {
                ContentUnavailableView(
                    "Collection unavailable",
                    systemImage: "folder.badge.questionmark",
                    description: Text("This collection may have been deleted.")
                )
            }
        }
        .alert(
            "Collection",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func remove(_ recipeID: UUID) {
        do {
            try store.setRecipe(recipeID, inCollection: collectionID, isMember: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CollectionRecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            RecipeImage(recipe: recipe, height: 56)
                .frame(width: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title.isEmpty ? String(localized: "Untitled Recipe") : recipe.title)
                    .font(RecipeTheme.text(16, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(.primary)
                if let minutes = recipe.totalMinutes {
                    Text("\(minutes) min")
                        .font(RecipeTheme.text(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minHeight: 64)
    }
}

private struct CollectionRecipePickerSheet: View {
    let collectionID: UUID

    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var errorMessage: String?

    private var collection: RecipeCollection? {
        store.collection(id: collectionID)
    }

    private var visibleRecipes: [Recipe] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.recipes
            .filter { recipe in
                query.isEmpty || recipe.title.localizedStandardContains(query)
            }
            .sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visibleRecipes) { recipe in
                    let isMember = store.collectionIDs(forRecipe: recipe.id).contains(collectionID)
                    Button {
                        toggle(recipe.id, isMember: isMember)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isMember ? RecipeTheme.accentForeground : Color.secondary)
                            Text(recipe.title.isEmpty ? String(localized: "Untitled Recipe") : recipe.title)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(isMember ? "In collection" : "Not in collection")
                }
            }
            .scrollContentBackground(.hidden)
            .background(RecipeTheme.canvas)
            .navigationTitle(collection?.name ?? "Collection")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search recipes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Collection",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func toggle(_ recipeID: UUID, isMember: Bool) {
        do {
            try store.setRecipe(
                recipeID,
                inCollection: collectionID,
                isMember: !isMember
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RenameCollectionSheet: View {
    let collection: RecipeCollection

    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var errorMessage: String?

    init(collection: RecipeCollection) {
        self.collection = collection
        _name = State(initialValue: collection.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Collection name", text: $name)
                    .textInputAutocapitalization(.words)
            }
            .navigationTitle("Rename Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(
                "Collection",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        do {
            try store.renameCollection(id: collection.id, name: name)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
