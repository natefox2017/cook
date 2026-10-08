// Developer: gengyun
// Purpose: Provides the legacy RecipeApp recipe detail screen and actions.

import SwiftUI

struct RecipeDetailView: View {
    @Environment(AppStore.self) private var store

    let recipeID: UUID

    @State private var isEditing = false
    @State private var isCooking = false
    @State private var servings = 2

    private var recipe: Recipe? {
        store.recipes.first { $0.id == recipeID }
    }

    var body: some View {
        Group {
            if let recipe {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        hero
                        Text(recipe.title)
                            .font(RecipeTheme.title())

                        HStack {
                            Label(
                                recipe.minutes > 0
                                    ? "(recipe.minutes) min"
                                    : "Time unknown",
                                systemImage: "clock"
                            )
                            Spacer()
                            Stepper(
                                "(servings) servings",
                                value: $servings,
                                in: 1...12
                            )
                        }
                        .font(.subheadline)

                        if recipe.needsReview {
                            Label(
                                "This import needs a quick review.",
                                systemImage: "exclamationmark.circle"
                            )
                            .foregroundStyle(.orange)
                        }

                        sourceLink(recipe)
                        ingredients(recipe)
                        steps(recipe)

                        Button("Start Cooking") {
                            isCooking = true
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(recipe.steps.isEmpty)

                        Button("Add ingredients to groceries") {
                            store.addGroceries(
                                from: recipe,
                                servings: servings
                            )
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .disabled(recipe.ingredients.isEmpty)
                    }
                    .padding()
                }
                .background(RecipeTheme.paper)
                .navigationTitle("Recipe")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button {
                        store.toggleFavorite(recipe.id)
                    } label: {
                        Image(
                            systemName: recipe.isFavorite
                                ? "heart.fill"
                                : "heart"
                        )
                    }

                    Button("Edit") {
                        isEditing = true
                    }
                }
                .sheet(isPresented: $isEditing) {
                    NavigationStack {
                        RecipeEditorView(recipe: recipe)
                    }
                }
                .fullScreenCover(isPresented: $isCooking) {
                    CookingModeView(recipe: recipe)
                }
                .onAppear {
                    servings = max(recipe.servings, 1)
                }
            } else {
                ContentUnavailableView(
                    "Recipe unavailable",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
    }

    private var hero: some View {
        RoundedRectangle(cornerRadius: 26)
            .fill(.green.opacity(0.12))
            .frame(height: 250)
            .overlay {
                Image(systemName: "fork.knife")
                    .font(.system(size: 64))
                    .foregroundStyle(RecipeTheme.green)
            }
    }

    @ViewBuilder
    private func sourceLink(_ recipe: Recipe) -> some View {
        if
            let sourceURL = recipe.sourceURL,
            let url = URL(string: sourceURL)
        {
            Link("Open original source", destination: url)
        }
    }

    private func ingredients(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ingredients")
                .font(.title2.bold())

            ForEach(recipe.ingredients) { ingredient in
                HStack {
                    Text(ingredient.name)
                    Spacer()
                    Text(ingredient.amount)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func steps(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Steps")
                .font(.title2.bold())

            ForEach(Array(recipe.steps.enumerated()), id: .element.id) { index, step in
                HStack(alignment: .top) {
                    Text("(index + 1)")
                        .font(.headline)
                        .frame(width: 28, height: 28)
                        .background(
                            .green.opacity(0.12),
                            in: Circle()
                        )

                    Text(step.text)
                }
            }
        }
    }
}
