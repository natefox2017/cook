// Developer: gengyun
// Purpose: Implements RecipeDetailView for the Recipe iOS app.

import CryptoKit
import RecipeCore
import SwiftUI

struct RecipeDetailView: View {
    let recipeID: UUID
    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @State private var servings = 1
    @State private var didLoadServings = false
    @State private var didAdjustServings = false
    @State private var isEditing = false
    @State private var isChoosingRecipeCandidates = false
    @State private var isCooking = false
    @State private var cookingStartStepID: UUID?
    @State private var isChoosingIngredients = false
    @State private var isDeleting = false
    @State private var parameterInfo: RecipeParameterInfo?
    @State private var proposalToReview: RecipeEditProposal?
    @State private var feedbackMessage: String?
    @State private var addedIngredientCount: Int?
    @State private var isPlanningMeal = false
    @State private var isManagingCollections = false
    @State private var isLoadingSourceArtifact = false
    @State private var isDeletingSourceArtifact = false
    @State private var confirmsSourceArtifactDeletion = false

    var body: some View {
        Group {
            if let recipe = store.recipe(id: recipeID) {
                recipeContent(recipe)
            } else {
                EmptyStateView(
                    title: "Recipe unavailable",
                    message: "This recipe is no longer in your library.", systemImage: "book.closed"
                )
            }
        }
        .background(RecipeTheme.canvas)
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle("Recipe")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
        .toolbar { detailToolbar }
        .sheet(isPresented: $isEditing) {
            if let recipe = store.recipe(id: recipeID) { RecipeEditorView(recipe: recipe) }
        }
        .sheet(isPresented: $isChoosingRecipeCandidates) {
            if let recipe = store.recipe(id: recipeID) {
                RecipeCandidateSelectionView(sourceRecipe: recipe)
            }
        }
        .sheet(isPresented: $isPlanningMeal) { RecipeMealPlanSheet(recipeID: recipeID) }
        .sheet(isPresented: $isManagingCollections) {
            RecipeCollectionMembershipSheet(recipeID: recipeID)
        }
        .sheet(item: $parameterInfo) { info in
            RecipeParameterSheet(info: info)
        }
        .sheet(isPresented: Binding(
            get: { proposalToReview != nil },
            set: { if !$0 { proposalToReview = nil } }
        )) {
            if let proposal = proposalToReview {
                RecipeEditProposalReviewSheet(proposal: proposal) { saved in
                    if saved.id != recipeID {
                        feedbackMessage = String(
                            localized: LocalizedStringResource(
                                "Saved a new private recipe.",
                                locale: RecipeLanguage.active
                            )
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $isChoosingIngredients, onDismiss: showAddedFeedback) {
            RecipeIngredientsSelectionView(recipeID: recipeID, initialServings: servings) {
                addedIngredientCount = $0
            }
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
        .confirmationDialog(
            "Delete this recipe?", isPresented: $isDeleting, titleVisibility: .visible
        ) {
            Button("Delete Recipe", role: .destructive, action: deleteRecipe)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the recipe from your library and meal plan.")
        }
        .confirmationDialog(
            "Delete original attachment?",
            isPresented: $confirmsSourceArtifactDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete Original Attachment", role: .destructive) {
                Task { await deleteSourceArtifact() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your recipe will stay saved.")
        }
        .alert("Recipe", isPresented: feedbackPresented) {
            Button("OK", role: .cancel) { feedbackMessage = nil }
        } message: {
            Text(feedbackMessage ?? "")
        }
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
            VStack(alignment: .leading, spacing: RecipeSpacing.large) {
                RecipeImage(recipe: recipe, height: 270)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                overview(recipe)
                ingredients(recipe)
                steps(recipe)
                if !recipe.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
                        sectionTitle("Kitchen Notes")
                        Text(recipe.notes).textSelection(.enabled)
                    }
                }
                additionalDetails(recipe)
                source(recipe)
            }
            .recipePageContentInsets()
        }
        .accessibilityIdentifier("recipeDetailScroll")
        .safeAreaInset(edge: .bottom) {
            Button {
                RecipeInteractionFeedback.action()
                cookingStartStepID = nil
                isCooking = true
            } label: {
                Label("Start Cooking", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RecipeDetailActionButtonStyle(variant: .primary))
            .disabled(recipe.steps.isEmpty)
            .accessibilityIdentifier("startCooking")
            .padding(.horizontal, RecipeSpacing.pageInset)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }

    private func overview(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: RecipeSpacing.small) {
            Text(
                recipe.title.isEmpty
                    ? String(
                        localized: LocalizedStringResource(
                            "Untitled Recipe", locale: RecipeLanguage.active)) : recipe.title
            )
            .font(RecipeTheme.heading(.hero))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { recipeMetadata(recipe) }
                VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
                    recipeMetadata(recipe)
                }
            }
            .font(RecipeTheme.text(15, weight: .regular, relativeTo: .subheadline))
            .foregroundStyle(.secondary)
            if !recipe.summary.isEmpty {
                Text(recipe.summary)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            recipeCollections(recipe)
            if let candidates = recipe.importRecord?.result.candidateRecipes,
                !candidates.isEmpty
            {
                Button {
                    isChoosingRecipeCandidates = true
                } label: {
                    Label(
                        "Select dishes from this source (\(candidates.count))",
                        systemImage: "square.stack.3d.up"
                    )
                    .font(RecipeTheme.text(15, weight: .semibold, relativeTo: .subheadline))
                    .frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("recipeMultiCandidateSelect")
            } else if recipe.needsReview {
                Button {
                    isEditing = true
                } label: {
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
        if let prep = recipe.prepMinutes, prep >= 0 {
            Label("Prep \(prep) min", systemImage: "clock")
        }
        if let cook = recipe.cookMinutes, cook >= 0 {
            Label("Cook \(cook) min", systemImage: "flame")
        }
        if let total = recipe.totalMinutes, recipe.prepMinutes == nil || recipe.cookMinutes == nil {
            Label("Total \(total) min", systemImage: "clock")
        }
        if let originalServings = recipe.servings, originalServings > 0 {
            Label("\(servings) servings", systemImage: "person.2")
        }
        if let difficulty = recipe.difficulty {
            Label(LocalizedStringKey(difficulty.rawValue), systemImage: "gauge.medium")
        }
        if let cuisine = recipe.cuisine, !cuisine.isEmpty {
            Label(cuisine, systemImage: "fork.knife")
        } else {
            Text(LocalizedStringKey(recipe.category.rawValue))
        }
    }

    private func ingredients(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: RecipeSpacing.medium) {
            sectionTitle("Ingredients")
            if let originalServings = recipe.servings, originalServings > 0 {
                Stepper(
                    "\(servings) servings", value: servingsSelection,
                    in: 1...max(100, max(originalServings, servings))
                )
                .accessibilityIdentifier("recipeServingsStepper")
            } else {
                Text("Original amounts · servings not specified")
                    .font(RecipeTheme.text(15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
            }
            if recipe.ingredients.isEmpty {
                Text("No ingredients yet. Edit this recipe to add them.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ingredientGroups(for: recipe)) { group in
                    VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
                        if let title = group.title {
                            Text(title)
                                .font(RecipeTheme.text(
                                    15, weight: .semibold, relativeTo: .subheadline))
                                .foregroundStyle(RecipeTheme.accentForeground)
                        }
                        VStack(spacing: 0) {
                            ForEach(group.ingredients) { ingredient in
                                Button {
                                    parameterInfo = .ingredient(
                                        ingredient, servings: servings,
                                        originalServings: recipe.servings)
                                } label: {
                                    RecipeIngredientLine(
                                        ingredient: ingredient, servings: servings,
                                        originalServings: recipe.servings)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Show ingredient amount details")
                                .accessibilityIdentifier(
                                    "recipeIngredientInfo.\(ingredient.id.uuidString)")
                                if ingredient.id != group.ingredients.last?.id { Divider() }
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
                Button {
                    RecipeInteractionFeedback.action()
                    isChoosingIngredients = true
                } label: {
                    Label("Add to Groceries", systemImage: "cart.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(RecipeDetailActionButtonStyle(variant: .secondary))
                .accessibilityIdentifier("addToGroceries")
            }
        }
    }


    private func ingredientGroups(for recipe: Recipe) -> [DetailIngredientGroup] {
        var groups: [DetailIngredientGroup] = []
        var used: Set<UUID> = []
        for section in recipe.ingredientSections ?? [] {
            let ids = Set(section.ingredientIDs)
            let members = recipe.ingredients.filter {
                ids.contains($0.id) && !used.contains($0.id)
            }
            guard !members.isEmpty else { continue }
            used.formUnion(members.map(\.id))
            groups.append(DetailIngredientGroup(
                id: section.id.uuidString, title: section.title, ingredients: members))
        }
        let remaining = recipe.ingredients.filter { !used.contains($0.id) }
        if !remaining.isEmpty {
            groups.append(DetailIngredientGroup(
                id: "remaining", title: groups.isEmpty ? nil : "Other Ingredients",
                ingredients: remaining))
        }
        return groups
    }

    @ViewBuilder
    private func additionalDetails(_ recipe: Recipe) -> some View {
        let hasEquipment = !(recipe.equipment ?? []).isEmpty
        let hasTips = !(recipe.preparationTips ?? "").isEmpty
        let hasStorage = !(recipe.storageNotes ?? "").isEmpty
        let hasYield = !(recipe.yieldDescription ?? "").isEmpty
        let hasAuthor = !(recipe.authorCredit ?? "").isEmpty
        let nutrition = recipe.nutrition
        // Invalid/unknown nutrition is still preserved privately, never shown as fact.
        let hasNutrition = nutrition?.hasDisplayablePerServingValues == true
        if hasEquipment || hasTips || hasStorage || hasYield || hasAuthor || hasNutrition {
            VStack(alignment: .leading, spacing: RecipeSpacing.small) {
                sectionTitle("More details")
                if let equipment = recipe.equipment, !equipment.isEmpty {
                    Label(equipment.joined(separator: ", "), systemImage: "frying.pan")
                }
                if let yield = recipe.yieldDescription, !yield.isEmpty {
                    Text("Yield: \(yield)")
                }
                if let tips = recipe.preparationTips, !tips.isEmpty {
                    Text(tips)
                }
                if let storage = recipe.storageNotes, !storage.isEmpty {
                    Text(storage)
                }
                if let author = recipe.authorCredit, !author.isEmpty {
                    Text("Creator: \(author)")
                }
                if hasNutrition, let nutrition {
                    DisclosureGroup("Nutrition per serving") {
                        if let calories = nutrition.caloriesKcal {
                            Text("Calories: \(NSDecimalNumber(decimal: calories).stringValue) kcal")
                        }
                        if let protein = nutrition.proteinGrams {
                            Text("Protein: \(NSDecimalNumber(decimal: protein).stringValue) g")
                        }
                        if let carbohydrates = nutrition.carbohydratesGrams {
                            Text("Carbohydrates: \(NSDecimalNumber(decimal: carbohydrates).stringValue) g")
                        }
                        if let fat = nutrition.fatGrams {
                            Text("Fat: \(NSDecimalNumber(decimal: fat).stringValue) g")
                        }
                        Text("Source: \(nutrition.source)")
                            .font(RecipeTheme.text(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(RecipeTheme.text(15, relativeTo: .subheadline))
        }
    }

    private func steps(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: RecipeSpacing.medium) {
            sectionTitle("Steps")
            if recipe.steps.isEmpty {
                Text("No steps yet. Edit this recipe before you start cooking.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, step in
                    VStack(alignment: .leading, spacing: RecipeSpacing.small) {
                        HStack(alignment: .top, spacing: 14) {
                            Text(index + 1, format: .number)
                                .font(
                                    RecipeTheme.text(17, weight: .semibold, relativeTo: .headline)
                                )
                                .foregroundStyle(RecipeTheme.accentForeground)
                                .frame(minWidth: 32, minHeight: 32)
                                .background(RecipeTheme.accent.opacity(0.1), in: Circle())

                            VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
                                if !step.title.isEmpty {
                                    Text(step.title)
                                        .font(
                                            RecipeTheme.text(
                                                17, weight: .semibold, relativeTo: .headline))
                                }
                                RecipeInteractiveInstructionText(
                                    step: step, recipe: recipe,
                                    servings: servings,
                                    accessibilityID: "recipeStepInstruction.\(step.id.uuidString)",
                                    selection: $parameterInfo
                                )
                            }
                        }

                        let linkedIngredients = recipe.ingredients.filter {
                            step.linkedIngredientIDs.contains($0.id)
                        }
                        if !linkedIngredients.isEmpty {
                            VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
                                Label("For this step", systemImage: "carrot")
                                    .font(
                                        RecipeTheme.text(
                                            13, weight: .semibold, relativeTo: .footnote)
                                    )
                                    .foregroundStyle(RecipeTheme.accentForeground)
                                ForEach(linkedIngredients) { ingredient in
                                    Button {
                                        parameterInfo = .ingredient(
                                            ingredient, servings: servings,
                                            originalServings: recipe.servings)
                                    } label: {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(ingredient.name)
                                            Spacer(minLength: 8)
                                            Text(
                                                ingredient.displayAmount(
                                                    servings: servings,
                                                    originalServings: recipe.servings)
                                            ).foregroundStyle(.secondary)
                                            Image(systemName: "info.circle")
                                                .accessibilityHidden(true)
                                        }
                                        .font(RecipeTheme.text(14, relativeTo: .subheadline))
                                        .frame(minHeight: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Show ingredient amount details")
                                    .accessibilityIdentifier("recipeStepIngredientInfo.\(ingredient.id.uuidString)")
                                }
                            }
                            .padding(12)
                            .background(
                                RecipeTheme.accent.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 14))
                        }

                        if step.temperature != nil || !step.timers.isEmpty {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 10) { stepSignals(step) }
                                VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
                                    stepSignals(step)
                                }
                            }
                        }

                        Button {
                            RecipeInteractionFeedback.action()
                            cookingStartStepID = step.id
                            isCooking = true
                        } label: {
                            Label("Cook from Step \(index + 1)", systemImage: "play")
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(RecipeDetailActionButtonStyle(variant: .secondary))
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
            Button {
                parameterInfo = .temperature(temperature)
            } label: {
                Label(temperature.text, systemImage: "thermometer.medium")
                    .font(RecipeTheme.text(13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(RecipeTheme.accentForeground)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Show temperature conversion")
            .accessibilityIdentifier("recipeStepTemperatureInfo")
        }
        ForEach(step.timers) { timer in
            let duration = timerDurationLabel(timer.durationSeconds)
            Button {
                parameterInfo = .timer(timer)
            } label: {
                Label(
                    timer.label.isEmpty ? duration : "\(timer.label) · \(duration)",
                    systemImage: "timer"
                )
                .font(RecipeTheme.text(13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(RecipeTheme.accentForeground)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Show timer details")
            .accessibilityIdentifier("recipeStepTimerInfo")
        }
    }

    @ViewBuilder
    private func source(_ recipe: Recipe) -> some View {
        let artifactID =
            recipe.importRecord?.sourceArtifactDeletedAt == nil
            ? recipe.importRecord?.result.source.sourceArtifactID
            : nil
        let sourceType = recipe.importRecord?.result.source.inputType
        if recipe.sourceName != nil
            || recipe.sourceURL != nil
            || recipe.sourceText != nil
            || artifactID != nil
        {
            VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
                sectionTitle("Source")
                if let name = recipe.sourceName, !name.isEmpty {
                    Text(name)
                        .font(RecipeTheme.text(15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                }
                if let original = recipe.sourceURL, !original.isEmpty {
                    if let url = URL(string: original),
                        ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                        url.host != nil
                    {
                        Link(destination: url) {
                            Label("Open Original Recipe", systemImage: "arrow.up.right.square")
                        }
                        .frame(minHeight: 44, alignment: .leading)
                    } else {
                        Text(original)
                            .font(RecipeTheme.text(13, weight: .regular, relativeTo: .footnote))
                            .textSelection(.enabled)
                    }
                }
                if let text = recipe.sourceText, !text.isEmpty {
                    DisclosureGroup("Original Text") {
                        Text(text)
                            .font(RecipeTheme.text(15, weight: .regular, relativeTo: .subheadline))
                            .textSelection(.enabled)
                            .padding(.top, RecipeSpacing.xSmall)
                    }
                }
                if let artifactID,
                    sourceType == "image" || sourceType == "file"
                {
                    Button {
                        Task {
                            await openSourceArtifact(artifactID)
                        }
                    } label: {
                        if isLoadingSourceArtifact {
                            ProgressView("Loading Attachment")
                                .frame(minHeight: 44, alignment: .leading)
                        } else {
                            Label(
                                sourceType == "image"
                                    ? "View Shared Image"
                                    : "View Shared Document",
                                systemImage: sourceType == "image" ? "photo" : "doc"
                            )
                            .frame(minHeight: 44, alignment: .leading)
                        }
                    }
                    .disabled(isLoadingSourceArtifact || isDeletingSourceArtifact)

                    Button("Delete Original Attachment", systemImage: "trash", role: .destructive) {
                        confirmsSourceArtifactDeletion = true
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .disabled(isLoadingSourceArtifact || isDeletingSourceArtifact)
                    .accessibilityIdentifier("source.deleteAttachment")
                }
            }
        }
    }

    @MainActor
    private func openSourceArtifact(_ artifactID: UUID) async {
        guard case .signedIn(let ownerID, _) = RecipeAuthService.shared.state
        else {
            feedbackMessage = String(
                localized: LocalizedStringResource(
                    "Sign in required", locale: RecipeLanguage.active))
            return
        }

        isLoadingSourceArtifact = true
        defer { isLoadingSourceArtifact = false }

        do {
            let url = try await RecipeImportArtifactService().downloadURL(
                artifactID: artifactID,
                ownerID: ownerID
            )
            guard case .signedIn(let currentOwnerID, _) = RecipeAuthService.shared.state,
                currentOwnerID == ownerID
            else {
                feedbackMessage = String(
                    localized: LocalizedStringResource(
                        "Your signed-in account changed. The saved source was kept for the correct account.",
                        locale: RecipeLanguage.active))
                return
            }
            openURL(url)
        } catch {
            feedbackMessage = String(
                localized: LocalizedStringResource(
                    "The shared source is unavailable. It may have expired.",
                    locale: RecipeLanguage.active))
        }
    }

    @MainActor
    private func deleteSourceArtifact() async {
        guard
            let artifactID = store.recipe(id: recipeID)?
                .importRecord?.result.source.sourceArtifactID,
            case .signedIn(let ownerID, _) = RecipeAuthService.shared.state
        else {
            feedbackMessage = String(
                localized: LocalizedStringResource(
                    "Sign in required", locale: RecipeLanguage.active
                ))
            return
        }

        isDeletingSourceArtifact = true
        defer { isDeletingSourceArtifact = false }

        do {
            // The API resolves artifact ownership from the JWT; never pass an
            // arbitrary storage path or delete the recipe itself.
            try await RecipeImportArtifactService().delete(
                artifactID: artifactID,
                ownerID: ownerID
            )
            guard case .signedIn(let currentOwnerID, _) = RecipeAuthService.shared.state,
                currentOwnerID == ownerID
            else {
                throw RecipeShareImportWorkflowError.accountChanged
            }
            guard var recipe = store.recipe(id: recipeID),
                recipe.importRecord?.result.source.sourceArtifactID == artifactID
            else { return }
            recipe.importRecord?.sourceArtifactDeletedAt = .now
            try store.upsert(recipe)
            feedbackMessage = String(
                localized: LocalizedStringResource(
                    "Attachment deleted. Your recipe was kept.",
                    locale: RecipeLanguage.active
                ))
        } catch {
            feedbackMessage = error.localizedDescription
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let recipe = store.recipe(id: recipeID) {
                Button {
                    RecipePerformanceSignposts.measure("Favorite Write") {
                        do {
                            try store.toggleFavorite(id: recipeID)
                            RecipeInteractionFeedback.favorite(
                                isFavorite: !recipe.isFavorite
                            )
                        } catch {
                            feedbackMessage = error.localizedDescription
                        }
                    }
                } label: {
                    RecipeFavoriteArtwork(isFavorite: recipe.isFavorite)
                }
                .accessibilityLabel(
                    LocalizedStringKey(
                        recipe.isFavorite ? "Remove from Favorites" : "Add to Favorites"
                    )
                )
                .accessibilityValue(
                    recipe.isFavorite
                        ? LocalizedStringKey("Favorite")
                        : LocalizedStringKey("Not favorite")
                )
                .accessibilityIdentifier("recipeFavoriteToggle")
                Menu {
                    Button("Add to Meal Plan", systemImage: "calendar.badge.plus") {
                        isPlanningMeal = true
                    }
                    Button("Collections", systemImage: "folder.badge.plus") {
                        isManagingCollections = true
                    }
                    Button("Edit Recipe", systemImage: "pencil") {
                        isEditing = true
                    }
                    #if DEBUG
                        // Never expose a synthetic AI action to real users.
                        if RecipeUITestNamespace.isUITesting,
                            ProcessInfo.processInfo.arguments.contains(
                                "--uitesting-ai-edit-preview"
                            ),
                            let ingredient = recipe.ingredients.first,
                            !ingredient.name.isEmpty
                        {
                            Button("Review changes", systemImage: "checklist") {
                                let stale = ProcessInfo.processInfo.arguments.contains(
                                    "--uitesting-ai-edit-stale"
                                )
                                proposalToReview = RecipeEditProposal(
                                    recipeID: recipe.id,
                                    basedOnUpdate: stale ? .distantPast : recipe.updatedAt,
                                    changes: [
                                        .ingredientName(
                                            id: ingredient.id,
                                            original: ingredient.name,
                                            proposed: "QA Changed " + ingredient.name
                                        )
                                    ],
                                    reasons: ["Synthetic QA preview; no AI provider is called."],
                                    warnings: ["Confirm ingredient suitability before cooking."]
                                )
                            }
                            .accessibilityIdentifier("qaReviewRecipeProposal")
                        }
                    #endif
                    Button("Delete Recipe", systemImage: "trash", role: .destructive) {
                        isDeleting = true
                    }
                } label: {
                    Label("Recipe Options", systemImage: "ellipsis")
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(RecipeTheme.heading(.section))
            .accessibilityAddTraits(.isHeader)
    }

    private var servingsSelection: Binding<Int> {
        Binding(
            get: { servings },
            set: {
                servings = $0
                didAdjustServings = true
            })
    }

    private var feedbackPresented: Binding<Bool> {
        Binding(get: { feedbackMessage != nil }, set: { if !$0 { feedbackMessage = nil } })
    }

    private func showAddedFeedback() {
        if let count = addedIngredientCount {
            feedbackMessage = String(
                localized: LocalizedStringResource(
                    "\(count) ingredients added to Groceries.", locale: RecipeLanguage.active))
            addedIngredientCount = nil
        }
    }

    private func deleteRecipe() {
        do {
            try store.deleteRecipe(id: recipeID)
            CookingView.discardSession(recipeID: recipeID)
            dismiss()
        } catch { feedbackMessage = error.localizedDescription }
    }

    private func timerDurationLabel(_ seconds: Int) -> String {
        let duration = Duration.seconds(seconds).formatted(
            .units(width: .abbreviated, maximumUnitCount: 2).locale(locale)
        )
        return String(
            localized: LocalizedStringResource("\(duration) timer", locale: locale)
        )
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
            VStack(alignment: .leading, spacing: RecipeSpacing.xxSmall) {
                Text(ingredient.name)
                amount
            }
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
    @AppStorage(RecipeUITestNamespace.preferenceKey("recipe.grocery.consolidate"))
    private var consolidate = true
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
                    EmptyStateView(
                        title: "Recipe unavailable",
                        message: "This recipe is no longer in your library.",
                        systemImage: "book.closed")
                }
            }
            .navigationTitle("Add to Groceries")
            .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert(
                "Unable to Add Ingredients",
                isPresented: Binding(
                    get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
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
                    Stepper(
                        "\(servings) servings",
                        value: $servings,
                        in: 1...max(100, max(original, initialServings))
                    )
                } else {
                    Text("Original amounts · servings not specified").foregroundStyle(.secondary)
                }
            } header: {
                Text("Portions")
            }
            Section {
                Button(
                    LocalizedStringKey(
                        selection.count == recipe.ingredients.count ? "Deselect All" : "Select All"
                    )
                )
                {
                    selection =
                        selection.count == recipe.ingredients.count
                        ? [] : Set(recipe.ingredients.map(\.id))
                }
                ForEach(recipe.ingredients) { ingredient in
                    Button {
                        toggle(ingredient.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(
                                systemName: selection.contains(ingredient.id)
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .foregroundStyle(
                                selection.contains(ingredient.id)
                                    ? RecipeTheme.accentForeground : Color.secondary
                            )
                            .font(.system(size: 20))
                            RecipeIngredientLine(
                                ingredient: ingredient, servings: servings,
                                originalServings: recipe.servings
                            )
                            .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        LocalizedStringKey(
                            "\(ingredient.name), \(ingredient.displayAmount(servings: servings, originalServings: recipe.servings))"
                        )
                    )
                    .accessibilityValue(
                        selection.contains(ingredient.id)
                            ? LocalizedStringKey("Selected")
                            : LocalizedStringKey("Not selected")
                    )
                    .accessibilityHint("Double-tap to change selection")
                }
            } header: {
                Text("Choose ingredients")
            } footer: {
                Text(
                    LocalizedStringKey(
                        consolidate
                            ? "Compatible amounts combine safely. Unclear amounts stay as written."
                            : "Each selected ingredient becomes a separate item. Existing items are unchanged."
                    )
                )
            }
        }
        .contentMargins(.top, RecipeSpacing.pageTop, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .safeAreaInset(edge: .bottom) {
            Button("Add \(selection.count) ingredient") { add(recipe) }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(selection.isEmpty)
                .accessibilityIdentifier("confirmAddIngredientsButton")
                .padding(RecipeSpacing.pageInset)
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
                            let isMember =
                                store
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
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(
                                isMember
                                    ? LocalizedStringKey("In collection")
                                    : LocalizedStringKey("Not in collection")
                            )
                        }
                    }
                } header: {
                    Text("Collections")
                }
            }
            .contentMargins(.top, RecipeSpacing.pageTop, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(RecipeTheme.canvas)
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
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
                    ForEach(MealSlot.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
            }
            .navigationTitle("Add to Meal Plan")
            .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        do {
                            try store.upsertMeal(
                                MealPlanEntry(recipeID: recipeID, date: date, slot: slot))
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert(
                "Couldn’t update meal plan",
                isPresented: Binding(
                    get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }
}


/// Reuses original recipe fields; unavailable measurements remain unknown.
struct RecipeParameterInfo: Identifiable {
    let id = UUID()
    let title: String
    let lines: [String]

    static func ingredient(
        _ ingredient: RecipeIngredient, servings: Int?, originalServings: Int?
    ) -> RecipeParameterInfo {
        let amount = ingredient.displayAmount(
            servings: servings, originalServings: originalServings)
        var lines = [
            amount.isEmpty ? "Amount not specified" : "Current amount: \(amount)"
        ]
        if !ingredient.amountText.isEmpty, ingredient.amountText != amount {
            lines.append("Source amount: \(ingredient.amountText)")
        }
        if ingredient.quantity == nil {
            lines.append("Keep the original quantity when an exact value is unknown.")
        }
        return RecipeParameterInfo(title: ingredient.name, lines: lines)
    }

    static func temperature(_ temperature: CookingTemperature) -> RecipeParameterInfo {
        var lines = [temperature.text]
        if let alternate = RecipeTemperatureConversion.alternateUnit(for: temperature.text) {
            lines.append("Converted: \(alternate)")
        }
        return RecipeParameterInfo(title: "Temperature", lines: lines)
    }

    static func timer(_ timer: RecipeStepTimer) -> RecipeParameterInfo {
        let amount = Duration.seconds(timer.durationSeconds).formatted(
            .units(width: .wide, maximumUnitCount: 2))
        return RecipeParameterInfo(
            title: timer.label.isEmpty ? "Step timer" : timer.label,
            lines: ["Duration: \(amount)", "Start Cooking from this step to use the timer."]
        )
    }
}

struct RecipeParameterSheet: View {
    let info: RecipeParameterInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: RecipeSpacing.medium) {
                ForEach(Array(info.lines.enumerated()), id: \.offset) { item in
                    Text(item.element)
                        .font(RecipeTheme.text(16, relativeTo: .body))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(RecipeSpacing.pageInset)
            .background(RecipeTheme.canvas)
            .navigationTitle(info.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(260), .medium])
        .presentationDragIndicator(.visible)
    }
}

/// Used by both Recipe Detail and Cooking; native links never change step state.
struct RecipeInteractiveInstructionText: View {
    let step: RecipeStep
    let recipe: Recipe
    let servings: Int?
    let accessibilityID: String
    let lineSpacing: CGFloat
    @Binding var selection: RecipeParameterInfo?

    init(
        step: RecipeStep, recipe: Recipe, servings: Int?,
        accessibilityID: String, lineSpacing: CGFloat = 0,
        selection: Binding<RecipeParameterInfo?>
    ) {
        self.step = step
        self.recipe = recipe
        self.servings = servings
        self.accessibilityID = accessibilityID
        self.lineSpacing = lineSpacing
        _selection = selection
    }

    var body: some View {
        let spans = RecipeInstructionParameterSpans.spans(
            for: step, ingredients: recipe.ingredients
        )
        var text = AttributedString()
        var targets: [Int: RecipeInstructionParameter] = [:]
        for (index, span) in spans.enumerated() {
            var fragment = AttributedString(span.text)
            if let parameter = span.parameter,
                let url = URL(string: "recipe-parameter://item/\(index)")
            {
                fragment.link = url
                targets[index] = parameter
            }
            text.append(fragment)
        }

        return Text(text)
            .lineSpacing(lineSpacing)
            .tint(RecipeTheme.accentForeground)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityIdentifier(accessibilityID)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "recipe-parameter", url.host == "item",
                    let index = Int(url.lastPathComponent),
                    let parameter = targets[index]
                else {
                    return .systemAction
                }

                switch parameter {
                case .ingredient(let ingredientID):
                    guard step.linkedIngredientIDs.contains(ingredientID),
                        let ingredient = recipe.ingredients.first(where: {
                            $0.id == ingredientID
                        })
                    else {
                        return .discarded
                    }
                    selection = .ingredient(
                        ingredient, servings: servings,
                        originalServings: recipe.servings
                    )
                case .temperature:
                    guard let temperature = step.temperature else {
                        return .discarded
                    }
                    selection = .temperature(temperature)
                case .timer(let timerID):
                    guard let timer = step.timers.first(where: {
                        $0.id == timerID
                    }) else {
                        return .discarded
                    }
                    selection = .timer(timer)
                }
                return .handled
            })
    }
}

private struct DetailIngredientGroup: Identifiable {
    let id: String
    let title: String?
    let ingredients: [RecipeIngredient]
}


/// Explicit multi-dish picker. A source can remain in the private library for
/// future review; no dish is saved automatically or merged into a false recipe.
private struct RecipeCandidateSelectionView: View {
    let sourceRecipe: Recipe
    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<String>()
    @State private var errorMessage: String?

    private var candidates: [RecipeImportJobResponse.Candidate] {
        Array((sourceRecipe.importRecord?.result.candidateRecipes ?? []).prefix(8))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates, id: \.candidateID) { candidate in
                        Button {
                            if !selected.insert(candidate.candidateID).inserted {
                                selected.remove(candidate.candidateID)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: selected.contains(candidate.candidateID)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(RecipeTheme.accentForeground)
                                    .font(.system(size: 22))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(candidate.title ?? "Untitled Recipe")
                                        .font(RecipeTheme.text(
                                            16, weight: .semibold, relativeTo: .body))
                                    Text(
                                        "\(candidate.ingredients.count) ingredients · \(candidate.steps.count) steps"
                                    )
                                    .font(RecipeTheme.text(13, relativeTo: .footnote))
                                    .foregroundStyle(.secondary)
                                    if !candidate.reviewFields.isEmpty {
                                        Text("Needs review after saving")
                                            .font(RecipeTheme.text(12, relativeTo: .caption))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "recipeCandidate.\(candidate.candidateID)")
                    }
                } header: {
                    Text("Choose recipes to save")
                } footer: {
                    Text("Only selected dishes are added to your private recipes.")
                }
            }
            .navigationTitle("Select recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save selected") {
                        do { try saveSelected(); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    }
                    .disabled(selected.isEmpty)
                    .accessibilityIdentifier("saveSelectedCandidateRecipes")
                }
            }
            .alert(
                "Could not save recipes",
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

    private func saveSelected() throws {
        guard let sourceRecord = sourceRecipe.importRecord else { return }
        for candidate in candidates where selected.contains(candidate.candidateID) {
            let targetID = Self.stableChildID(
                sourceID: sourceRecipe.id, candidateID: candidate.candidateID)
            // Repeated saves do not duplicate a dish or overwrite user edits.
            if store.recipe(id: targetID) != nil { continue }
            let title = candidate.title ?? "Untitled Recipe"
            let content = title
                + "\n\nIngredients\n" + candidate.ingredients.joined(separator: "\n")
                + "\n\nInstructions\n" + candidate.steps.joined(separator: "\n")
            var recipe = RecipeDocumentParser.recipe(fromText: content, title: title)
            recipe.id = targetID
            recipe.sourceURL = sourceRecipe.sourceURL
            recipe.sourceName = sourceRecipe.sourceName
            recipe.sourceText = sourceRecipe.sourceText

            var fields: [String: RecipeImportJobResponse.Field] = [:]
            let evidenceIDs = candidate.evidenceIDs
            fields["title"] = .init(rawValue: title, evidenceIDs: evidenceIDs)
            for (index, raw) in candidate.ingredients.enumerated() {
                let field = RecipeImportJobResponse.Field(
                    rawValue: raw, evidenceIDs: evidenceIDs)
                fields["ingredients[\(index)].raw_text"] = field
                fields["ingredients[\(index)].amount"] = field
            }
            for (index, instruction) in candidate.steps.enumerated() {
                fields["steps[\(index)].instruction"] = .init(
                    rawValue: instruction, evidenceIDs: evidenceIDs)
            }
            let evidence = sourceRecord.result.evidence.filter {
                evidenceIDs.contains($0.id)
            }
            let result = RecipeImportJobResponse.Result(
                recipeID: targetID,
                status: candidate.reviewFields.isEmpty ? "ready" : "needs_review",
                source: sourceRecord.result.source,
                fields: fields,
                evidence: evidence,
                reviewFields: candidate.reviewFields
            )
            recipe.importRecord = RecipeImportRecord(
                jobID: sourceRecord.jobID,
                result: result,
                selectedCandidateID: candidate.candidateID)
            try store.upsert(recipe)
        }
    }

    private static func stableChildID(sourceID: UUID, candidateID: String) -> UUID {
        let key = Data("\(sourceID.uuidString):\(candidateID)".utf8)
        let digest = Array(SHA256.hash(data: key))
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }
}

    
/// Review an untrusted proposal without mutating private recipe data until consent.
/// This view intentionally has no production entry point until an authenticated
/// proposal provider has passed its separate contract and deployment checks.
struct RecipeEditProposalReviewSheet: View {
    let proposal: RecipeEditProposal
    let onSaved: (Recipe) -> Void

    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var proposedTexts: [String]

    init(
        proposal: RecipeEditProposal,
        onSaved: @escaping (Recipe) -> Void = { _ in }
    ) {
        self.proposal = proposal
        self.onSaved = onSaved
        _proposedTexts = State(initialValue: proposal.changes.map { change in
            switch change {
            case .ingredientName(_, _, let proposed),
                .ingredientAmount(_, _, let proposed),
                .stepInstruction(_, _, let proposed):
                return proposed
            }
        })
    }

    // Only allow edits to the three already approved RecipeEditChange cases.
    // Rebuild the validated proposal instead of directly saving edited text.
    private var reviewedProposal: RecipeEditProposal {
        let changes: [RecipeEditChange] = proposal.changes.enumerated().map { index, change in
            let text = proposedTexts.indices.contains(index) ? proposedTexts[index] : ""
            switch change {
            case .ingredientName(let id, let original, _):
                return .ingredientName(id: id, original: original, proposed: text)
            case .ingredientAmount(let id, let original, _):
                return .ingredientAmount(id: id, original: original, proposed: text)
            case .stepInstruction(let id, let original, _):
                return .stepInstruction(id: id, original: original, proposed: text)
            }
        }
        return RecipeEditProposal(
            recipeID: proposal.recipeID,
            basedOnUpdate: proposal.basedOnUpdate,
            changes: changes,
            reasons: proposal.reasons,
            warnings: proposal.warnings
        )
    }

    private var isStale: Bool {
        guard let current = store.recipe(id: proposal.recipeID) else {
            return true
        }
        return current.updatedAt != proposal.basedOnUpdate
    }

    // Always derive the preview from the live Store. This is display-only;
    // applyApprovedRecipeEdit performs the revision check again at commit time.
    private var preview: RecipeEditPreview? {
        guard let current = store.recipe(id: proposal.recipeID) else {
            return nil
        }
        return try? reviewedProposal.preview(on: current)
    }

    private var reviewRows: [RecipeEditReviewRow] {
        proposal.changes.enumerated().map { index, change in
            let field: String
            let before: String
            switch change {
            case .ingredientName(_, let original, _):
                field = "Ingredient name"
                before = original
            case .ingredientAmount(_, let original, _):
                field = "Ingredient amount"
                before = original
            case .stepInstruction(_, let original, _):
                field = "Step instruction"
                before = original
            }
            return RecipeEditReviewRow(
                id: index, field: field, before: before
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RecipeSpacing.medium) {
                    if !isStale {
                        Text("Review every proposed change before saving.")
                            .foregroundStyle(.secondary)
                        ForEach(reviewRows) { row in
                            VStack(alignment: .leading, spacing: RecipeSpacing.small) {
                                Text(LocalizedStringKey(row.field))
                                    .font(RecipeTheme.heading(.card))
                                Text("Original")
                                    .font(RecipeTheme.text(
                                        13, weight: .semibold, relativeTo: .footnote
                                    ))
                                    .foregroundStyle(.secondary)
                                Text(row.before)
                                    .strikethrough()
                                    .accessibilityIdentifier("reviewProposalBefore.\(row.id)")
                                Text("Proposed")
                                    .font(RecipeTheme.text(
                                        13, weight: .semibold, relativeTo: .footnote
                                    ))
                                    .foregroundStyle(.secondary)
                                TextField(
                                    "Proposed",
                                    text: $proposedTexts[row.id],
                                    axis: .vertical
                                )
                                .lineLimit(2...6)
                                .font(RecipeTheme.text(
                                    17, weight: .semibold, relativeTo: .body
                                ))
                                .accessibilityIdentifier("reviewProposalAfter.\(row.id)")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(RecipeSpacing.medium)
                            .background(
                                RecipeTheme.card,
                                in: RoundedRectangle(cornerRadius: 18)
                            )
                        }

                        if !proposal.reasons.isEmpty {
                            explanation(
                                title: "Why this was suggested",
                                lines: proposal.reasons
                            )
                        }
                        if !proposal.warnings.isEmpty {
                            explanation(
                                title: "Check before saving",
                                lines: proposal.warnings
                            )
                        }
                        if preview == nil {
                            Text("Check the proposed text. It cannot be empty or too long.")
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("invalidRecipeProposal")
                        }
                    } else {
                        Text("This recipe changed. Get a new suggestion before saving.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("staleRecipeProposal")
                    }
                }
                .recipePageContentInsets()
            }
            .background(RecipeTheme.canvas)
            .navigationTitle("Review changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: RecipeSpacing.small) {
                    Button("Apply to recipe") { save(asVariant: false) }
                        .buttonStyle(RecipeDetailActionButtonStyle(variant: .primary))
                        .disabled(preview == nil)
                        .accessibilityIdentifier("applyRecipeProposal")
                    Button("Save as new recipe") { save(asVariant: true) }
                        .buttonStyle(RecipeDetailActionButtonStyle(variant: .secondary))
                        .disabled(preview == nil)
                        .accessibilityIdentifier("saveRecipeProposalVariant")
                    Button("Discard changes") { dismiss() }
                        .accessibilityIdentifier("discardRecipeProposal")
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, RecipeSpacing.pageInset)
                .padding(.vertical, RecipeSpacing.small)
                .background(.regularMaterial)
            }
            .alert(
                "Couldn't save changes",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private func explanation(title: LocalizedStringKey, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: RecipeSpacing.small) {
            Text(title)
                .font(RecipeTheme.heading(.card))
            ForEach(Array(lines.enumerated()), id: \.offset) { item in
                Text(item.element)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save(asVariant: Bool) {
        // Never persist a proposal that is already stale on screen.
        guard preview != nil else {
            return
        }
        do {
            let saved = try store.applyApprovedRecipeEdit(
                reviewedProposal, asVariant: asVariant
            )
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = String(
                localized: LocalizedStringResource(
                    "The recipe changed or could not be saved. Review it and try again.",
                    locale: RecipeLanguage.active
                )
            )
        }
    }
}

private struct RecipeEditReviewRow: Identifiable {
    let id: Int
    let field: String
    let before: String
}
