import SwiftUI
import CookCore

struct RecipesView: View {
    @Environment(CookStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var searchText = ""
    @State private var filter: RecipeLibraryFilter = .all
    @State private var selectedCollectionID: UUID?
    @State private var sort: RecipeLibrarySort = .recent
    @State private var isAdding = false
    @State private var errorMessage: String?
    @FocusState private var isSearchFocused: Bool

    private var visibleRecipes: [Recipe] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.recipes.filter { recipe in
            let matchesScope: Bool
            if let selectedCollectionID {
                matchesScope = store.collectionIDs(forRecipe: recipe.id).contains(selectedCollectionID)
            } else {
                matchesScope = filter.includes(recipe)
            }
            return matchesScope && (
                query.isEmpty || searchableText(recipe).localizedStandardContains(query)
            )
        }.sorted { lhs, rhs in
            switch sort {
            case .recent:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            case .alphabetical:
                let order = lhs.title.localizedStandardCompare(rhs.title)
                if order != .orderedSame { return order == .orderedAscending }
            case .quickest:
                let left = lhs.totalMinutes ?? Int.max
                let right = rhs.totalMinutes ?? Int.max
                if left != right { return left < right }
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top),
              count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CookSpacing.large) {
                searchField
                Text("Your saved recipes, all in one place.")
                    .font(CookTheme.text(15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                if !store.recipes.isEmpty {
                    filterBar
                    resultsHeader
                }
                libraryContent
            }
            .padding(.horizontal, CookSpacing.pageInset)
            .padding(.top, CookSpacing.xSmall)
            .padding(.bottom, CookSpacing.large)
        }
        .accessibilityIdentifier("recipeLibraryScroll")
        .background(CookTheme.canvas)
        .navigationTitle("My Recipes").navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Recipe", systemImage: "plus") { isAdding = true }
                    .accessibilityIdentifier("addRecipeButton")
            }
        }
        .navigationDestination(for: UUID.self) { RecipeDetailView(recipeID: $0) }
        .sheet(isPresented: $isAdding) { AddRecipeView() }
        .alert("Unable to Update Recipe", isPresented: errorPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .onChange(of: store.collections.map(\.id)) { _, collectionIDs in
            if let selectedCollectionID, !collectionIDs.contains(selectedCollectionID) {
                self.selectedCollectionID = nil
                filter = .all
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: CookSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search recipes, ingredients, steps", text: $searchText)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("recipeSearchField")
            if !searchText.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") {
                    searchText = ""
                    isSearchFocused = true
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
            }
        }
        .font(CookTheme.text(15, weight: .regular, relativeTo: .subheadline))
        .padding(.horizontal, CookSpacing.medium)
        .frame(minHeight: 44)
        .background(Color.primary.opacity(0.05), in: Capsule())
    }

    @ViewBuilder
    private var libraryContent: some View {
        if store.recipes.isEmpty {
            VStack(spacing: 12) {
                EmptyStateView(
                    title: "Make room for your favorites",
                    message: "Save a recipe from a link, photo, or your own kitchen notes.",
                    systemImage: "book.closed",
                    actionTitle: "Add Your First Recipe",
                    action: { isAdding = true }
                )
                Button("Try sample recipes") {
                    do { try store.loadSampleRecipes() }
                    catch { errorMessage = error.localizedDescription }
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("loadSampleRecipes")
                Text("Explore a few sample recipes. You can edit or delete them at any time.")
                    .font(CookTheme.text(13, weight: .regular, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(.top, CookSpacing.large)
        } else if visibleRecipes.isEmpty {
            EmptyStateView(
                title: searchText.isEmpty ? emptyScopeTitle : "No recipes found",
                message: searchText.isEmpty ? emptyScopeMessage : "Try another dish or ingredient, or clear your filters.",
                systemImage: selectedCollectionID == nil ? "magnifyingglass" : "folder",
                actionTitle: "Show All Recipes",
                action: {
                    searchText = ""
                    selectedCollectionID = nil
                    filter = .all
                }
            )
            .padding(.top, CookSpacing.large)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: CookSpacing.large) {
                ForEach(visibleRecipes) { recipe in
                    RecipeLibraryCard(recipe: recipe) {
                        do { try store.toggleFavorite(id: recipe.id) }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RecipeLibraryFilter.allCases) { item in
                    let isSelected = selectedCollectionID == nil && filter == item
                    Button {
                        selectedCollectionID = nil
                        filter = item
                    } label: {
                        Text(item.title)
                            .font(CookTheme.text(
                                15,
                                weight: isSelected ? .semibold : .regular,
                                relativeTo: .subheadline
                            ))
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .background(
                                isSelected ? CookTheme.accent : CookTheme.card,
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? CookTheme.canvas : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }

                ForEach(store.collections) { collection in
                    let isSelected = selectedCollectionID == collection.id
                    Button {
                        filter = .all
                        selectedCollectionID = collection.id
                    } label: {
                        Label(collection.name, systemImage: "folder")
                            .font(CookTheme.text(
                                15,
                                weight: isSelected ? .semibold : .regular,
                                relativeTo: .subheadline
                            ))
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .background(
                                isSelected ? CookTheme.accent : CookTheme.card,
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? CookTheme.canvas : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private var emptyScopeTitle: String {
        if let selectedCollectionID,
           let collection = store.collection(id: selectedCollectionID) {
            return "\(collection.name) is empty"
        }
        return filter.emptyTitle
    }

    private var emptyScopeMessage: String {
        if selectedCollectionID != nil {
            return "Add recipes from a recipe page or from Collections."
        }
        return filter.emptyMessage
    }

    private var resultsHeader: some View {
        HStack {
            Text("\(visibleRecipes.count) \(visibleRecipes.count == 1 ? "Recipe" : "Recipes")")
                .font(CookTheme.text(15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("recipeCount")
            Spacer()
            Menu {
                Picker("Sort recipes", selection: $sort) {
                    ForEach(RecipeLibrarySort.allCases) { item in Text(item.rawValue).tag(item) }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
                    .font(CookTheme.text(15, weight: .regular, relativeTo: .subheadline))
                    .frame(minHeight: 44)
            }
            .accessibilityValue(sort.rawValue)
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func searchableText(_ recipe: Recipe) -> String {
        ([recipe.title, recipe.summary, recipe.notes]
         + recipe.ingredients.map(\.name)
         + recipe.steps.map { "\($0.title) \($0.instruction)" }).joined(separator: "\n")
    }
}

private struct RecipeLibraryCard: View {
    let recipe: Recipe
    let toggleFavorite: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: recipe.id) {
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geometry in
                        RecipeImage(recipe: recipe, height: geometry.size.height)
                    }
                    .aspectRatio(1.4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    Text(recipe.title.isEmpty ? "Untitled Recipe" : recipe.title)
                        .font(CookTheme.title(20))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        if let minutes = recipe.totalMinutes {
                            Label("\(minutes) min", systemImage: "clock")
                        } else {
                            Text(recipe.category.rawValue)
                        }
                    }
                    .font(CookTheme.text(12, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    if recipe.needsReview {
                        Label("Needs Review", systemImage: "pencil.line")
                            .font(CookTheme.text(12, weight: .semibold, relativeTo: .caption))
                            .foregroundStyle(CookTheme.accentForeground)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recipe.\(recipe.id.uuidString)")
            Button(action: toggleFavorite) {
                Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 20))
                    .foregroundStyle(CookTheme.accentForeground)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel(recipe.isFavorite ? "Remove \(recipe.title) from favorites" : "Favorite \(recipe.title)")
            .accessibilityValue(recipe.isFavorite ? "Favorite" : "Not favorite")
        }
    }
}

private enum RecipeLibraryFilter: Hashable, Identifiable, CaseIterable {
    case all, meals, breakfast, desserts, drinks, sides, favorites, needsReview
    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .meals: "Meals"
        case .breakfast: "Breakfast"
        case .desserts: "Desserts"
        case .drinks: "Drinks"
        case .sides: "Sides"
        case .favorites: "Favorites"
        case .needsReview: "Needs Review"
        }
    }

    var emptyTitle: String {
        switch self {
        case .favorites: "Your favorites start here"
        case .needsReview: "Everything looks ready"
        default: "No recipes in this category"
        }
    }

    var emptyMessage: String {
        switch self {
        case .favorites: "Tap the heart on a recipe to keep your go-to dishes together."
        case .needsReview: "Recipes with missing ingredients or steps will appear here."
        default: "Choose another category or add a recipe to your collection."
        }
    }

    func includes(_ recipe: Recipe) -> Bool {
        switch self {
        case .all: true
        case .meals: recipe.category == .meals
        case .breakfast: recipe.category == .breakfast
        case .desserts: recipe.category == .desserts
        case .drinks: recipe.category == .drinks
        case .sides: recipe.category == .sides
        case .favorites: recipe.isFavorite
        case .needsReview: recipe.needsReview
        }
    }
}

private enum RecipeLibrarySort: String, CaseIterable, Identifiable {
    case recent = "Recently Saved"
    case alphabetical = "Name, A–Z"
    case quickest = "Cooking Time"
    var id: String { rawValue }
}
