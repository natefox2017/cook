// Developer: gengyun
// Purpose: Implements RecipeDetailView for the Recipe iOS app.

import SwiftUI
import RecipeCore

struct RecipeDetailView: View {
    let recipeID: UUID
    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var servings = 1
    @State private var didLoadServings = false
    @State private var didAdjustServings = false
    @State private var isEditing = false
    @State private var isCooking = false
    @State private var cookingStartStepID: UUID?
    @State private var isChoosingIngredients = false
    @State private var isDeleting = false
    @State private var feedbackMessage: String?
    @State private var addedIngredientCount: Int?
    @State private var isPlanningMeal = false
    @State private var isManagingCollections = false

    var body: some View {
        Group {
            if let recipe = store.recipe(id: recipeID) {
                recipeContent(recipe)
            } else {
                EmptyStateView(title: "Recipe unavailable", message: "This recipe is no longer in your library.", systemImage: "book.closed")
            }
        }
        .background(RecipeTheme.canvas)
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle("Recipe").navigationBarTitleDisplayMode(.inline)
        .toolbar { detailToolbar }
        .sheet(isPresented: $isEditing) {
            if let recipe = store.recipe(id: recipeID) { RecipeEditorView(recipe: recipe) }
        }
        .sheet(isPresented: $isPlanningMeal) { RecipeMealPlanSheet(recipeID: recipeID) }
        .sheet(isPresented: $isManagingCollections) {
            RecipeCollectionMembershipSheet(recipeID: recipeID)
        }
        .sheet(isPresented: $isChoosingIngredients, onDismiss: showAddedFeedback) {
            RecipeIngredientsSelectionView(recipeID: recipeID, initialServings: servings) { addedIngredientCount = $0 }
        }
        .fullScreenCover(isPresented: $isCooking) {
            CookingView(
                recipeID: recipeID,
                servings: didAdjustServings ? servings : nil,
                startStepID: cookingStartStepID
            ) { currentServings in
                servings = currentServings
                didAdjustServings = false
            }
        }
        .confirmationDialog("Delete this recipe?", isPresented: $isDeleting, titleVisibility: .visible) {
            Button("Delete Recipe", role: .destructive, action: deleteRecipe)
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes the recipe from your library and meal plan.") }
        .alert("Recipe", isPresented: feedbackPresented) {
            Button("OK", role: .cancel) { feedbackMessage = nil }
        } message: { Text(feedbackMessage ?? "") }
        .onAppear {
            if !didLoadServings {
                servings = max(1, store.recipe(id: recipeID)?.servings ?? 1)
                didLoadServings = true
            }
        }
        .onChange(of: store.recipe(id: recipeID)?.servings) { old, new in
            if !didAdjustServings || servings == (old ?? 1) {
                servings = max(1, new ?? 1)
                didAdjustServings = false
            }
        }
    }

    private func recipeContent(_ recipe: Recipe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                RecipeImage(recipe: recipe, height: 270)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                overview(recipe)
                ingredients(recipe)
                steps(recipe)
                if !recipe.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Kitchen Notes")
                        Text(recipe.notes).textSelection(.enabled)
                    }
                }
                source(recipe)
            }
            .padding(20)
        }
        .accessibilityIdentifier("recipeDetailScroll")
        .safeAreaInset(edge: .bottom) {
            Button {
                cookingStartStepID = nil
                isCooking = true
            } label: {
                Label("Start Cooking", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(recipe.steps.isEmpty)
            .accessibilityIdentifier("startCooking")
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }

    private func overview(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recipe.title.isEmpty ? "Untitled Recipe" : recipe.title)
                .font(RecipeTheme.title(34))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { recipeMetadata(recipe) }
                VStack(alignment: .leading, spacing: 8) { recipeMetadata(recipe) }
            }
            .font(RecipeTheme.text(15, weight: .regular, relativeTo: .subheadline))
            .foregroundStyle(.secondary)
            if !recipe.summary.isEmpty {
                Text(recipe.summary)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            recipeCollections(recipe)
            if recipe.needsReview {
                Button { isEditing = true } label: {
                    Label("Needs Review · Add missing recipe details", systemImage: "pencil.line")
                        .font(RecipeTheme.text(15, weight: .regular, relativeTo: .subheadline))
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func recipeCollections(_ recipe: Recipe) -> some View {
        let collectionIDs = store.collectionIDs(forRecipe: recipe.id)
        let assigned = store.collections.filter { collectionIDs.contains($0.id) }

        if !assigned.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(assigned) { collection in
                        Label(collection.name, systemImage: "folder")
                            .font(RecipeTheme.text(12, weight: .semibold, relativeTo: .caption))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(RecipeTheme.accent.opacity(0.08), in: Capsule())
                            .foregroundStyle(RecipeTheme.accentForeground)
                    }
                }
            }
            .accessibilityLabel("Collections")
        }
    }

    @ViewBuilder
    private func recipeMetadata(_ recipe: Recipe) -> some View {
        if let minutes = recipe.totalMinutes { Label("\(minutes) min", systemImage: "clock") }
        if let originalServings = recipe.servings, originalServings > 0 {
            Label("\(originalServings) \(originalServings == 1 ? "serving" : "servings")", systemImage: "person.2")
        }
        Text(recipe.category.rawValue)
    }

    private func ingredients(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Ingredients")
            if let originalServings = recipe.servings, originalServings > 0 {
                Stepper("\(servings) \(servings == 1 ? "serving" : "servings")", value: servingsSelection, in: 1...max(100, max(originalServings, servings)))
                    .accessibilityIdentifier("recipeServingsStepper")
                if servings != originalServings {
                    Text("Numeric amounts adjust with servings. Amounts such as “to taste” stay as written.")
                        .font(RecipeTheme.text(12, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Original amounts · servings not specified")
                    .font(RecipeTheme.text(15, weight: .regular, relativeTo: .subheadline)).foregroundStyle(.secondary)
            }
            if recipe.ingredients.isEmpty {
                Text("No ingredients yet. Edit this recipe to add them.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(recipe.ingredients) { ingredient in
                        RecipeIngredientLine(ingredient: ingredient, servings: servings, originalServings: recipe.servings)
                        if ingredient.id != recipe.ingredients.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 16)
                .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 20))
                Button { isChoosingIngredients = true } label: {
                    Label("Add to Groceries", systemImage: "cart.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("addToGroceries")
            }
        }
    }

    private func steps(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("Steps")
            if recipe.steps.isEmpty {
                Text("No steps yet. Edit this recipe before you start cooking.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, step in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(index + 1)")
                                .font(RecipeTheme.text(17, weight: .semibold, relativeTo: .headline))
                                .foregroundStyle(RecipeTheme.accentForeground)
                                .frame(minWidth: 32, minHeight: 32)
                                .background(RecipeTheme.accent.opacity(0.1), in: Circle())

                            VStack(alignment: .leading, spacing: 6) {
                                if !step.title.isEmpty {
                                    Text(step.title)
                                        .font(RecipeTheme.text(17, weight: .semibold, relativeTo: .headline))
                                }
                                Text(step.instruction)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }

                        let linkedIngredients = recipe.ingredients.filter { step.linkedIngredientIDs.contains($0.id) }
                        if !linkedIngredients.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("For this step", systemImage: "carrot")
                                    .font(RecipeTheme.text(13, weight: .semibold, relativeTo: .footnote))
                                    .foregroundStyle(RecipeTheme.accentForeground)
                                ForEach(linkedIngredients) { ingredient in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(ingredient.name)
                                        Spacer(minLength: 8)
                                        Text(ingredient.displayAmount(servings: servings, originalServings: recipe.servings))
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(RecipeTheme.text(14, relativeTo: .subheadline))
                                }
                            }
                            .padding(12)
                            .background(RecipeTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        }

                        if step.temperature != nil || !step.timers.isEmpty {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 10) { stepSignals(step) }
                                VStack(alignment: .leading, spacing: 8) { stepSignals(step) }
                            }
                        }

                        Button {
                            cookingStartStepID = step.id
                            isCooking = true
                        } label: {
                            Label("Cook from Step \(index + 1)", systemImage: "play")
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("cookFromStep.\(index + 1)")
                    }
                    .padding(16)
                    .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 20))
                }
            }
        }
    }

    @ViewBuilder
    private func stepSignals(_ step: RecipeStep) -> some View {
        if let temperature = step.temperature, !temperature.text.isEmpty {
            Label(temperature.text, systemImage: "thermometer.medium")
                .font(RecipeTheme.text(13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(RecipeTheme.accentForeground)
        }
        ForEach(step.timers) { timer in
            let duration = timerDurationLabel(timer.durationSeconds)
            Label(
                timer.label.isEmpty ? duration : "\(timer.label) · \(duration)",
                systemImage: "timer"
            )
            .font(RecipeTheme.text(13, weight: .semibold, relativeTo: .footnote))
            .foregroundStyle(RecipeTheme.accentForeground)
        }
    }

    @ViewBuilder
    private func source(_ recipe: Recipe) -> some View {
        if recipe.sourceName != nil || recipe.sourceURL != nil || recipe.sourceText != nil {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Source")
                if let name = recipe.sourceName, !name.isEmpty { Text(name).font(RecipeTheme.text(15, weight: .regular, relativeTo: .subheadline)).foregroundStyle(.secondary) }
                if let original = recipe.sourceURL, !original.isEmpty {
                    if let url = URL(string: original), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
                        Link(destination: url) { Label("Open Original Recipe", systemImage: "arrow.up.right.square") }
                            .frame(minHeight: 44, alignment: .leading)
                    } else {
                        Text(original).font(RecipeTheme.text(13, weight: .regular, relativeTo: .footnote)).textSelection(.enabled)
                    }
                }
                if let text = recipe.sourceText, !text.isEmpty {
                    DisclosureGroup("Original Text") { Text(text).font(RecipeTheme.text(15, weight: .regular, relativeTo: .subheadline)).textSelection(.enabled).padding(.top, 8) }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let recipe = store.recipe(id: recipeID) {
                Button {
                    do { try store.toggleFavorite(id: recipeID) }
                    catch { feedbackMessage = error.localizedDescription }
                } label: { Image(systemName: recipe.isFavorite ? "heart.fill" : "heart") }
                .accessibilityLabel(recipe.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                Menu {
                    Button("Add to Meal Plan", systemImage: "calendar.badge.plus") {
                        isPlanningMeal = true
                    }
                    Button("Collections", systemImage: "folder.badge.plus") {
                        isManagingCollections = true
                    }
                    Button("Edit Recipe", systemImage: "pencil") { isEditing = true }
                    Button("Delete Recipe", systemImage: "trash", role: .destructive) { isDeleting = true }
                } label: { Label("Recipe Options", systemImage: "ellipsis") }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(RecipeTheme.title(24)).accessibilityAddTraits(.isHeader)
    }

    private var servingsSelection: Binding<Int> {
        Binding(get: { servings }, set: { servings = $0; didAdjustServings = true })
    }

    private var feedbackPresented: Binding<Bool> {
        Binding(get: { feedbackMessage != nil }, set: { if !$0 { feedbackMessage = nil } })
    }

    private func showAddedFeedback() {
        if let count = addedIngredientCount {
            feedbackMessage = "\(count) \(count == 1 ? "ingredient" : "ingredients") added to Groceries."
            addedIngredientCount = nil
        }
    }

    private func deleteRecipe() {
        do {
            try store.deleteRecipe(id: recipeID)
            CookingView.discardSession(recipeID: recipeID)
            dismiss()
        }
        catch { feedbackMessage = error.localizedDescription }
    }

    private func timerDurationLabel(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) min timer" : "\(seconds / 60)m \(seconds % 60)s timer"
    }
}

private struct RecipeIngredientLine: View {
    let ingredient: RecipeIngredient
    let servings: Int?
    let originalServings: Int?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(ingredient.name)
                Spacer(minLength: 8)
                amount
            }
            VStack(alignment: .leading, spacing: 4) { Text(ingredient.name); amount }
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }

    private var amount: some View {
        Text(ingredient.displayAmount(servings: servings, originalServings: originalServings))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct RecipeIngredientsSelectionView: View {
    let recipeID: UUID
    let initialServings: Int
    let onAdded: (Int) -> Void
    @AppStorage("recipe.grocery.consolidate") private var consolidate = true
    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var servings = 1
    @State private var selection = Set<UUID>()
    @State private var didLoad = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let recipe = store.recipe(id: recipeID) {
                    selectionList(recipe)
                } else {
                    EmptyStateView(title: "Recipe unavailable", message: "This recipe is no longer in your library.", systemImage: "book.closed")
                }
            }
            .navigationTitle("Add to Groceries").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert("Unable to Add Ingredients", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .onAppear {
            guard !didLoad, let recipe = store.recipe(id: recipeID) else { return }
            servings = max(1, initialServings)
            selection = Set(recipe.ingredients.map(\.id))
            didLoad = true
        }
    }

    private func selectionList(_ recipe: Recipe) -> some View {
        List {
            Section {
                if let original = recipe.servings, original > 0 {
                    Stepper("\(servings) \(servings == 1 ? "serving" : "servings")", value: $servings, in: 1...max(100, max(original, initialServings)))
                } else {
                    Text("Original amounts · servings not specified").foregroundStyle(.secondary)
                }
            } header: { Text("Portions") }
            Section {
                Button(selection.count == recipe.ingredients.count ? "Deselect All" : "Select All") {
                    selection = selection.count == recipe.ingredients.count ? [] : Set(recipe.ingredients.map(\.id))
                }
                ForEach(recipe.ingredients) { ingredient in
                    Button { toggle(ingredient.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selection.contains(ingredient.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selection.contains(ingredient.id) ? RecipeTheme.accentForeground : Color.secondary)
                                .font(.system(size: 20))
                            RecipeIngredientLine(ingredient: ingredient, servings: servings, originalServings: recipe.servings)
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(ingredient.name), \(ingredient.displayAmount(servings: servings, originalServings: recipe.servings))")
                    .accessibilityValue(selection.contains(ingredient.id) ? "Selected" : "Not selected")
                    .accessibilityHint("Double-tap to change selection")
                }
            } header: { Text("Choose ingredients") } footer: {
                Text(
                    consolidate
                        ? "Compatible amounts combine safely. Unclear amounts stay as written."
                        : "Each selected ingredient becomes a separate item. Existing items are unchanged."
                )
            }
        }
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .safeAreaInset(edge: .bottom) {
            Button("Add \(selection.count) \(selection.count == 1 ? "Ingredient" : "Ingredients")") { add(recipe) }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(selection.isEmpty)
                .accessibilityIdentifier("confirmAddIngredientsButton")
                .padding(20)
                .background(.regularMaterial)
        }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func add(_ recipe: Recipe) {
        do {
            let knownServings = recipe.servings.map { $0 > 0 } ?? false
            try store.addToGroceries(
                recipeID: recipeID,
                servings: knownServings ? servings : nil,
                ingredientIDs: selection,
                consolidateCompatibleIngredients: consolidate
            )
            onAdded(selection.count)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct RecipeCollectionMembershipSheet: View {
    let recipeID: UUID

    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        TextField("New collection", text: $newName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(createCollection)

                        Button("Add", action: createCollection)
                            .disabled(
                                newName.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty
                            )
                    }
                }

                Section {
                    if store.collections.isEmpty {
                        Text("Create a collection to organize this recipe.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.collections) { collection in
                            let isMember = store
                                .collectionIDs(forRecipe: recipeID)
                                .contains(collection.id)

                            Button {
                                toggle(collection.id, isMember: isMember)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(
                                        systemName: isMember
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                    )
                                    .foregroundStyle(
                                        isMember
                                            ? RecipeTheme.accentForeground
                                            : Color.secondary
                                    )

                                    Text(collection.name)
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    Text(
                                        "\(store.recipes(inCollection: collection.id).count)"
                                    )
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(
                                isMember ? "In collection" : "Not in collection"
                            )
                        }
                    }
                } header: {
                    Text("Collections")
                } footer: {
                    Text("A recipe can belong to more than one collection.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(RecipeTheme.canvas)
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
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
    }

    private func createCollection() {
        do {
            let collection = try store.createCollection(name: newName)
            try store.setRecipe(
                recipeID,
                inCollection: collection.id,
                isMember: true
            )
            newName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggle(_ collectionID: UUID, isMember: Bool) {
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

private struct RecipeMealPlanSheet: View {
    let recipeID: UUID
    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var slot = MealSlot.dinner
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Meal", selection: $slot) {
                    ForEach(MealSlot.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            .navigationTitle("Add to Meal Plan").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        do {
                            try store.upsertMeal(MealPlanEntry(recipeID: recipeID, date: date, slot: slot))
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Couldn’t update meal plan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Please try again.") }
        }
    }
}
