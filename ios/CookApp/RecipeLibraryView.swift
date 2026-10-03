import SwiftUI

struct RecipeLibraryView: View {
    @Environment(CookStore.self) private var store
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var newestFirst = true
    @State private var adding = false
    @State private var failure: String?
    @ScaledMetric(relativeTo: .body) private var minimumCardWidth = 150.0

    private var recipes: [RecipeRecord] {
        store.snapshot.recipes.filter {
            (!favoritesOnly || $0.favorite) &&
            (query.isEmpty || $0.searchableText.localizedCaseInsensitiveContains(query))
        }.sorted { newestFirst ? $0.createdAt > $1.createdAt : $0.title.localizedCompare($1.title) == .orderedAscending }
    }
    private var reviewCount: Int { store.snapshot.recipes.filter { !$0.reviewFields.isEmpty }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Cook").font(CookTheme.heading()).accessibilityAddTraits(.isHeader)
                HStack {
                    Text("My Recipes").font(CookTheme.heading(.title))
                    Spacer()
                    if reviewCount > 0 {
                        NavigationLink {
                            ReviewCollectionView()
                        } label: {
                            Text("\(reviewCount) to review").font(.callout)
                        }
                    }
                }
                if let loadError = store.loadError {
                    ContentUnavailableView {
                        Label("Your collection couldn't be opened", systemImage: "exclamationmark.icloud")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Try again") { store.reload() }.cookAction()
                    }
                } else if store.snapshot.recipes.isEmpty && store.snapshot.captures.isEmpty {
                    ContentUnavailableView {
                        Label("Your cookbook starts here", systemImage: "book.closed")
                    } description: {
                        Text("Save a recipe link in Cook, or add a recipe of your own.")
                    } actions: {
                        Button("Add a recipe") { adding = true }.cookAction()
                    }
                } else {
                    if !store.snapshot.recipes.isEmpty {
                        Picker("Show recipes", selection: $favoritesOnly) {
                            Text("All").tag(false)
                            Text("Favorites").tag(true)
                        }.pickerStyle(.segmented)
                        HStack {
                            Text("\(recipes.count) recipes").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Menu {
                                Button("Recently saved") { newestFirst = true }
                                Button("Name") { newestFirst = false }
                            } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                        }
                        if recipes.isEmpty {
                            ContentUnavailableView.search(text: query)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumCardWidth), spacing: 16)], spacing: 24) {
                                ForEach(recipes) { recipe in
                                    VStack(alignment: .leading, spacing: 8) {
                                        NavigationLink {
                                            RecipeDetailView(recipeID: recipe.id)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 8) {
                                                RecipeCover(data: recipe.coverData).clipShape(RoundedRectangle(cornerRadius: 18))
                                                Text(recipe.title).font(CookTheme.heading(.headline)).foregroundStyle(.primary)
                                                if !recipe.sourceSummary.isEmpty {
                                                    Text(recipe.sourceSummary).font(.caption).foregroundStyle(.secondary)
                                                }
                                                if !recipe.reviewFields.isEmpty {
                                                    Text("Needs a quick review").font(.caption).foregroundStyle(CookTheme.green)
                                                }
                                            }
                                        }.buttonStyle(.plain)
                                        Button {
                                            do { try store.toggleFavorite(recipe.id) } catch { failure = error.localizedDescription }
                                        } label: {
                                            Label(recipe.favorite ? String(localized: "Favorited") : String(localized: "Favorite"),
                                                  systemImage: recipe.favorite ? "heart.fill" : "heart")
                                                .font(.caption)
                                        }.cookAction(prominent: false)
                                    }
                                }
                            }
                        }
                    }
                    if !store.snapshot.captures.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Saved sources").font(CookTheme.heading(.title2))
                            Text("Saved on this device. Automatic processing isn't connected yet.")
                                .font(.callout).foregroundStyle(.secondary)
                            ForEach(store.snapshot.captures) { capture in
                                NavigationLink {
                                    SavedSourceView(capture: capture)
                                } label: {
                                    HStack(alignment: .top) {
                                        Image(systemName: capture.kind == .url ? "link" : "doc")
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(capture.kind == .url ? URL(string: capture.value)?.host ?? capture.value : capture.value)
                                                .lineLimit(2)
                                            Text("Saved locally").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption)
                                    }
                                    .padding(.vertical, 10)
                                }.buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                }
                if let failure { InlineFailure(message: failure) }
            }.padding(20)
        }
        .background(CookTheme.paper)
        .searchable(text: $query, prompt: "Search your recipes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { adding = true }
                    .disabled(!store.loaded)
            }
        }
        .sheet(isPresented: $adding) { NavigationStack { AddRecipeView() } }
    }
}

struct ReviewCollectionView: View {
    @Environment(CookStore.self) private var store
    var body: some View {
        List {
            ForEach(store.snapshot.recipes.filter { !$0.reviewFields.isEmpty }) { recipe in
                NavigationLink(recipe.title) { ReviewRecipeView(recipeID: recipe.id) }
            }
        }.navigationTitle("To review")
    }
}
