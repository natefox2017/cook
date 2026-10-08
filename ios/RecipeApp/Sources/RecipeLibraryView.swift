// Developer: gengyun
// Purpose: Provides the legacy RecipeApp recipe library and recipe cards.

import SwiftUI

struct RecipeLibraryView: View {
    @Environment(AppStore.self) private var store

    @Binding var showingAdd: Bool
    @State private var query = ""
    @State private var favoritesOnly = false

    private var filteredRecipes: [Recipe] {
        store.recipes.filter { recipe in
            let matchesFavorite = !favoritesOnly || recipe.isFavorite
            let matchesQuery =
                query.isEmpty
                || recipe.title.localizedCaseInsensitiveContains(query)
                || recipe.ingredients.contains {
                    $0.name.localizedCaseInsensitiveContains(query)
                }
                || recipe.steps.contains {
                    $0.text.localizedCaseInsensitiveContains(query)
                }

            return matchesFavorite && matchesQuery
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 18
            ) {
                ForEach(filteredRecipes) { recipe in
                    NavigationLink(value: recipe.id) {
                        RecipeCard(recipe: recipe)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(RecipeTheme.paper)
        .navigationTitle("My Recipes")
        .searchable(
            text: $query,
            prompt: "Search recipes or ingredients"
        )
        .navigationDestination(for: UUID.self) { id in
            if store.recipes.contains(where: { $0.id == id }) {
                RecipeDetailView(recipeID: id)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    favoritesOnly.toggle()
                } label: {
                    Image(
                        systemName: favoritesOnly
                            ? "heart.fill"
                            : "heart"
                    )
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .overlay {
            if filteredRecipes.isEmpty {
                ContentUnavailableView(
                    "No recipes",
                    systemImage: "fork.knife",
                    description: Text(
                        query.isEmpty
                            ? "Add your first recipe."
                            : "Try another search."
                    )
                )
            }
        }
    }
}

private struct RecipeCard: View {
    @Environment(AppStore.self) private var store

    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.green.opacity(0.12))
                    .aspectRatio(1.25, contentMode: .fit)

                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 42))
                    .foregroundStyle(RecipeTheme.green)
            }

            HStack(alignment: .top) {
                Text(recipe.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)

                Spacer()

                Button {
                    store.toggleFavorite(recipe.id)
                } label: {
                    Image(
                        systemName: recipe.isFavorite
                            ? "heart.fill"
                            : "heart"
                    )
                }
                .buttonStyle(.plain)
            }

            Text(
                recipe.minutes > 0
                    ? "(recipe.minutes) min · (recipe.servings) servings"
                    : "Needs review"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
