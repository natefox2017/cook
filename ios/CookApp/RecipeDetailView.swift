import SwiftUI

struct RecipeDetailView: View {
    @Environment(CookStore.self) private var store
    var recipeID: UUID
    @State private var editing = false
    @State private var cooking = false
    @State private var portions = false
    @State private var failure: String?
    private var recipe: RecipeRecord? { store.snapshot.recipes.first { $0.id == recipeID } }

    var body: some View {
        if let recipe {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    RecipeCover(data: recipe.coverData, height: 260).clipShape(RoundedRectangle(cornerRadius: 24))
                    Text(recipe.title).font(CookTheme.heading())
                    if let servings = recipe.servings {
                        Label("\(servings) servings", systemImage: "fork.knife").foregroundStyle(.secondary)
                    }
                    if let url = recipe.sourceURL {
                        VStack(alignment: .leading, spacing: 6) {
                            if !recipe.sourceSummary.isEmpty { Text(recipe.sourceSummary).font(.subheadline).foregroundStyle(.secondary) }
                            Link(destination: url) { Label("Open original source", systemImage: "arrow.up.right.square") }
                            if !recipe.sourceTitle.isEmpty { Text(recipe.sourceTitle).font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                    if !recipe.reviewFields.isEmpty {
                        NavigationLink("Review \(recipe.reviewFields.count) uncertain fields") {
                            ReviewRecipeView(recipeID: recipeID)
                        }.cookAction(prominent: false)
                    }
                    Text("Ingredients").font(CookTheme.heading(.title2))
                    ForEach(recipe.ingredients) { ingredient in
                        HStack(alignment: .top) {
                            Text(ingredient.name)
                            Spacer()
                            Text(ingredient.displayedAmount(for: recipe.servings ?? 1, originalServings: recipe.servings))
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                    Text("Steps").font(CookTheme.heading(.title2))
                    if recipe.steps.isEmpty {
                        Text("Add the steps before you start cooking.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 16) {
                            Text("\(index + 1)").font(.headline).foregroundStyle(CookTheme.green)
                            Text(step.instruction)
                        }
                    }
                    Button("Start cooking", systemImage: "arrow.right") { cooking = true }
                        .cookAction().disabled(recipe.steps.isEmpty)
                    Button("Add to groceries", systemImage: "cart.badge.plus") { portions = true }
                        .cookAction(prominent: false).disabled(recipe.ingredients.isEmpty)
                    if let failure { InlineFailure(message: failure) }
                }.padding(20)
            }
            .background(CookTheme.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(recipe.favorite ? String(localized: "Remove favorite") : String(localized: "Favorite"), systemImage: recipe.favorite ? "heart.fill" : "heart") {
                        do { try store.toggleFavorite(recipeID) } catch { failure = error.localizedDescription }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } }
            }
            .sheet(isPresented: $editing) { NavigationStack { RecipeEditorView(recipe: recipe) } }
            .sheet(isPresented: $portions) { NavigationStack { ServingsView(recipe: recipe) } }
            .fullScreenCover(isPresented: $cooking) { NavigationStack { CookingView(recipe: recipe) } }
        } else {
            ContentUnavailableView("Recipe not found", systemImage: "book.closed")
        }
    }
}

struct ServingsView: View {
    @Environment(CookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var recipe: RecipeRecord
    @State private var servings = 2
    @State private var failure: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Adjust servings").font(CookTheme.heading())
                if let original = recipe.servings {
                    Text("Original recipe: \(original) servings").foregroundStyle(.secondary)
                    Stepper("\(servings) servings", value: $servings, in: 1...24)
                } else {
                    Text("The original serving size is unknown. Ingredients will be added as written.")
                        .foregroundStyle(.secondary)
                }
                ForEach(recipe.ingredients) { ingredient in
                    HStack(alignment: .top) {
                        Text(ingredient.name)
                        Spacer()
                        Text(ingredient.displayedAmount(for: servings, originalServings: recipe.servings))
                    }
                    Divider()
                }
                Text("Only explicit quantities are scaled. “To taste” stays “to taste”. Your original recipe is unchanged.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Add to groceries", systemImage: "cart.badge.plus") {
                    do { try store.addGroceries(from: recipe, servings: servings); dismiss() }
                    catch { failure = error.localizedDescription }
                }.cookAction().accessibilityIdentifier("servings.addToGroceries")
                if let original = recipe.servings {
                    Button("Reset to original servings") { servings = original }.cookAction(prominent: false)
                }
                if let failure { InlineFailure(message: failure) }
            }.padding(24)
        }
        .background(CookTheme.paper)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear { servings = recipe.servings ?? 1 }
    }
}

struct ReviewRecipeView: View {
    @Environment(CookStore.self) private var store
    var recipeID: UUID
    @State private var choices: [UUID: Bool] = [:]
    @State private var failure: String?
    private var recipe: RecipeRecord? { store.snapshot.recipes.first { $0.id == recipeID } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("A quick review").font(CookTheme.heading())
                if let recipe {
                    Text(recipe.title).font(CookTheme.heading(.title2))
                    if recipe.reviewFields.isEmpty {
                        Label("All uncertain fields have been reviewed.", systemImage: "checkmark.circle")
                    }
                    ForEach(recipe.reviewFields) { field in
                        VStack(alignment: .leading, spacing: 16) {
                            Text(field.question).font(.headline)
                            Text(field.evidence).font(.callout).foregroundStyle(.secondary)
                            Button {
                                choices[field.id] = true
                            } label: {
                                Label("Keep this ingredient", systemImage: choices[field.id] == true ? "largecircle.fill.circle" : "circle")
                            }.buttonStyle(.plain)
                            Button {
                                choices[field.id] = false
                            } label: {
                                Label("Leave it out", systemImage: choices[field.id] == false ? "largecircle.fill.circle" : "circle")
                            }.buttonStyle(.plain)
                            Button("Save choice") {
                                guard let keep = choices[field.id] else { return }
                                do { try store.resolve(field, in: recipe, keep: keep) } catch { failure = error.localizedDescription }
                            }.cookAction().disabled(choices[field.id] == nil)
                        }
                        Divider()
                    }
                    if let url = recipe.sourceURL {
                        Link("Check the original source", destination: url)
                    }
                    if let failure { InlineFailure(message: failure) }
                }
            }.padding(24)
        }
        .background(CookTheme.paper)
        .navigationTitle("To review").navigationBarTitleDisplayMode(.inline)
    }
}
