// Developer: gengyun
// Purpose: Implements RecipeDetailView for the Recipe iOS app.

import CryptoKit
import RecipeCore
import SwiftUI

struct RecipeDetailView: View {
    let recipeID: UUID
    var ownerSharing: RecipeOwnerSharingService = .shared
    @Environment(RecipeStore.self) private var store
    @Environment(RecipeAccessStore.self) private var access
    @Environment(UpgradeRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @State private var servings = 1
    @State private var didLoadServings = false
    @State private var didAdjustServings = false
    @State private var isEditing = false
    @State private var sharePresentation: SharePresentation?
    @State private var isDeletingRecipe = false
    @State private var isChoosingRecipeCandidates = false
    @State private var cookingPresentation: CookingPresentation?
    @State private var isChoosingIngredients = false
    @State private var isDeleting = false
    @State private var parameterInfo: RecipeParameterInfo?
    @State private var parameterCookingStepID: UUID?
    @State private var feedbackMessage: String?
    @State private var addedIngredientCount: Int?
    @State private var isPlanningMeal = false
    @State private var isManagingCollections = false
    @State private var isLoadingSourceArtifact = false
    @State private var isDeletingSourceArtifact = false
    @State private var confirmsSourceArtifactDeletion = false
    @State private var isChoosingEditIntent = false
    @State private var proposalToReview: RecipeEditReviewContext?
    @State private var editService: RecipeEditProposalService?
    @State private var undoState: RecipeEditUndoState?
    @State private var isChoosingTranslation = false
    @State private var translationCoordinator: RecipeTranslationCoordinator?

    private struct RecipeEditReviewContext: Identifiable {
        let id = UUID()
        let proposal: RecipeEditProposal
        let proposalID: String
        let operationID: String
        let wireChanges: [RecipeEditWireChange]
    }

    private struct RecipeEditUndoState {
        let before: Recipe
        let appliedRevision: Date
    }

    // Keep the requested step in the presentation payload so the first cover cannot read stale state.
    private struct CookingPresentation: Identifiable {
        let id = UUID()
        let startStepID: UUID?
    }

    private struct SharePresentation: Identifiable {
        let id = UUID()
        let state: RecipeShareConsentState
    }

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
        .toolbar {
            detailToolbar
        }
        .sheet(item: $sharePresentation) { presentation in
            RecipeShareConsentSheet(state: presentation.state)
        }
        .sheet(isPresented: $isEditing) {
            if let recipe = store.recipe(id: recipeID) {
                RecipeEditorView(recipe: recipe)
            }
        }
        .sheet(isPresented: $isChoosingEditIntent) {
            if let recipe = store.recipe(id: recipeID), let service = editService {
                RecipeEditIntentSheet(
                    recipe: recipe,
                    service: service,
                    onResult: handleEditResult
                )
            }
        }
        .sheet(isPresented: $isChoosingTranslation) {
            if let recipe = store.recipe(id: recipeID), let coordinator = translationCoordinator {
                RecipeTranslationSheet(recipe: recipe, coordinator: coordinator)
            }
        }
        .sheet(item: $proposalToReview) { context in
            RecipeEditProposalReviewSheet(proposal: context.proposal) { reviewed, asVariant in
                try await applyEdit(reviewed, context: context, asVariant: asVariant)
            }
        }
        .sheet(isPresented: $isChoosingRecipeCandidates) {
            if let recipe = store.recipe(id: recipeID) {
                RecipeCandidateSelectionView(sourceRecipe: recipe)
            }
        }
        .sheet(isPresented: $isPlanningMeal) {
            RecipeMealPlanSheet(recipeID: recipeID)
        }
        .sheet(isPresented: $isManagingCollections) {
            RecipeCollectionMembershipSheet(recipeID: recipeID)
        }
        .sheet(item: $parameterInfo, onDismiss: startParameterCooking) { info in
            RecipeParameterSheet(
                info: info,
                timerActionTitle: "Start Cooking from This Step"
            ) {
                parameterCookingStepID = info.stepID
            }
        }
        .sheet(isPresented: $isChoosingIngredients, onDismiss: showAddedFeedback) {
            RecipeIngredientsSelectionView(recipeID: recipeID, initialServings: servings) {
                addedIngredientCount = $0
            }
        }
        .fullScreenCover(item: $cookingPresentation) { presentation in
            CookingView(
                recipeID: recipeID,
                servings: didAdjustServings ? servings : nil,
                startStepID: presentation.startStepID
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
                Task {
                    await deleteSourceArtifact()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your recipe will stay saved.")
        }
        .alert("Recipe", isPresented: feedbackPresented) {
            Button("OK", role: .cancel) {
                feedbackMessage = nil
            }
        } message: {
            Text(feedbackMessage ?? "")
        }
        .onAppear {
            if !didLoadServings {
                servings = max(1, store.recipe(id: recipeID)?.servings ?? 1)
                didLoadServings = true
            }
        }
        .task {
            await resumePendingEditIfNeeded()
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
                if undoState != nil {
                    undoBanner
                }
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
                cookingPresentation = CookingPresentation(startStepID: nil)
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
            sourceSummary(recipe)
            recipeMetadata(recipe)
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
    private func sourceSummary(_ recipe: Recipe) -> some View {
        let sourceName = recipe.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = recipe.authorCredit?.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = originalSourceURL(recipe)
        let sourceLabel = sourceName?.isEmpty == false ? sourceName : url?.host

        if sourceLabel?.isEmpty == false || author?.isEmpty == false {
            VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
                if let sourceLabel, !sourceLabel.isEmpty {
                    if let url {
                        Link(destination: url) {
                            Label(sourceLabel, systemImage: "arrow.up.right.square")
                        }
                        .frame(minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("recipeOverviewSource")
                    } else {
                        Text(sourceLabel)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("recipeOverviewSource")
                    }
                }
                if let author, !author.isEmpty {
                    Text("Creator: \(author)")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("recipeOverviewAuthor")
                }
            }
            .font(RecipeTheme.text(15, relativeTo: .subheadline))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func originalSourceURL(_ recipe: Recipe) -> URL? {
        guard let original = recipe.sourceURL,
            let url = URL(string: original),
            ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
            url.host != nil
        else {
            return nil
        }
        return url
    }

    @ViewBuilder
    private func recipeCollections(_ recipe: Recipe) -> some View {
        let collectionIDs = store.collectionIDs(forRecipe: recipe.id)
        let assigned = store.collections.filter {
            collectionIDs.contains($0.id)
        }

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
        let hasTiming =
            (recipe.prepMinutes.map { $0 >= 0 } ?? false)
            || (recipe.cookMinutes.map { $0 >= 0 } ?? false)
            || (recipe.totalMinutes != nil
                && (recipe.prepMinutes == nil || recipe.cookMinutes == nil))

        Grid(
            alignment: .leading,
            horizontalSpacing: RecipeSpacing.medium,
            verticalSpacing: RecipeSpacing.xSmall
        ) {
            if hasTiming {
                GridRow {
                    if let prep = recipe.prepMinutes, prep >= 0 {
                        Button {
                            parameterInfo = .timing(recipe)
                        } label: {
                            Label("Prep \(prep) min", systemImage: "clock")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("recipeTimeInfo.prep")
                    }
                    if let cook = recipe.cookMinutes, cook >= 0 {
                        Button {
                            parameterInfo = .timing(recipe)
                        } label: {
                            Label("Cook \(cook) min", systemImage: "flame")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("recipeTimeInfo.cook")
                    }
                    if let total = recipe.totalMinutes,
                        recipe.prepMinutes == nil || recipe.cookMinutes == nil
                    {
                        Button {
                            parameterInfo = .timing(recipe)
                        } label: {
                            Label("Total \(total) min", systemImage: "clock")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("recipeTimeInfo.total")
                    }
                }
            }

            GridRow {
                if let originalServings = recipe.servings, originalServings > 0 {
                    Label("\(servings) servings", systemImage: "person.2")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                if let cuisine = recipe.cuisine, !cuisine.isEmpty {
                    Label(cuisine, systemImage: "fork.knife")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                } else {
                    Text(LocalizedStringKey(recipe.category.rawValue))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }

            if let difficulty = recipe.difficulty {
                GridRow {
                    Label(LocalizedStringKey(difficulty.rawValue), systemImage: "gauge.medium")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .gridCellColumns(2)
                }
            }
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
                                .font(
                                    RecipeTheme.text(
                                        15, weight: .semibold, relativeTo: .subheadline)
                                )
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
                                        originalServings: recipe.servings
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Show ingredient amount details")
                                .accessibilityIdentifier(
                                    "recipeIngredientInfo.\(ingredient.id.uuidString)")
                                if ingredient.id != group.ingredients.last?.id {
                                    Divider()
                                }
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
            guard !members.isEmpty else {
                continue
            }
            used.formUnion(members.map(\.id))
            groups.append(
                DetailIngredientGroup(
                    id: section.id.uuidString, title: section.title, ingredients: members))
        }
        let remaining = recipe.ingredients.filter {
            !used.contains($0.id)
        }
        if !remaining.isEmpty {
            groups.append(
                DetailIngredientGroup(
                    id: "remaining",
                    title: groups.isEmpty
                        ? nil
                        : String(
                            localized: LocalizedStringResource(
                                "Other Ingredients", locale: RecipeLanguage.active
                            )
                        ),
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
                            Text(
                                "Carbohydrates: \(NSDecimalNumber(decimal: carbohydrates).stringValue) g"
                            )
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

                        RecipeStepPhotosView(recipe: recipe, stepID: step.id)

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
                                    .accessibilityIdentifier(
                                        "recipeStepIngredientInfo.\(ingredient.id.uuidString)")
                                }
                            }
                            .padding(12)
                            .background(
                                RecipeTheme.accent.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 14))
                        }

                        if step.temperature != nil || !step.timers.isEmpty {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 10) {
                                    stepSignals(step)
                                }
                                VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
                                    stepSignals(step)
                                }
                            }
                        }

                        Button {
                            RecipeInteractionFeedback.action()
                            cookingPresentation = CookingPresentation(startStepID: step.id)
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

    private func startParameterCooking() {
        guard let stepID = parameterCookingStepID else {
            return
        }
        parameterCookingStepID = nil
        // Present only after the parameter sheet has finished dismissing.
        cookingPresentation = CookingPresentation(startStepID: stepID)
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
                parameterInfo = .timer(timer, stepID: step.id)
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
                    if let url = originalSourceURL(recipe) {
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
        defer {
            isLoadingSourceArtifact = false
        }

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
        defer {
            isDeletingSourceArtifact = false
        }

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
            else {
                return
            }
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
                Button("Edit Recipe", systemImage: "pencil") {
                    isEditing = true
                }
                .accessibilityIdentifier("recipeEdit")
                Menu {
                    if canAdjustRecipe {
                        Button("Adjust Recipe", systemImage: "wand.and.stars") {
                            presentAdjustRecipe()
                        }
                        .accessibilityIdentifier("recipeAdjustRecipe")
                    }
                    Button("Translate Recipe", systemImage: "globe") {
                        presentTranslateRecipe()
                    }
                    .accessibilityIdentifier("recipeTranslate")
                    Button("Share", systemImage: "square.and.arrow.up") {
                        sharePresentation = SharePresentation(
                            state: ownerSharing.consentState(recipeID: recipeID, store: store)
                        )
                    }
                    .accessibilityIdentifier("recipeShare")
                    Button("Add to Meal Plan", systemImage: "calendar.badge.plus") {
                        isPlanningMeal = true
                    }
                    Button("Collections", systemImage: "folder.badge.plus") {
                        isManagingCollections = true
                    }
                    Button("Delete Recipe", systemImage: "trash", role: .destructive) {
                        isDeleting = true
                    }
                    .disabled(isDeletingRecipe)
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

    // MARK: - AI recipe adjustment (DEV-76)

    /// The Adjust Recipe entry is subordinate to the frozen release stage and the
    /// `ai_edit` capability: dormant in the free first release, visible only when the
    /// commercial access snapshot reports the capability as usable or upgradeable.
    private var canAdjustRecipe: Bool {
        access.isEnabled && (access.canUse(.aiEdit) || router.requiresUpgrade(.aiEdit))
    }

    private func presentAdjustRecipe() {
        guard ensureEditService() else {
            feedbackMessage = RecipeEditProposalServiceError.invalidConfiguration.localizedDescription
            return
        }
        if router.requiresUpgrade(.aiEdit) {
            router.showUpgrade(capability: .aiEdit, pendingID: UUID().uuidString.lowercased())
        } else {
            isChoosingEditIntent = true
        }
    }

    @discardableResult
    private func ensureEditService() -> Bool {
        if editService == nil {
            editService = try? RecipeEditProposalService(bundle: .main)
        }
        return editService != nil
    }

    // MARK: - Recipe translation (DEV-439)

    /// The Translate Recipe entry stays ungated in the free first release; the backend is
    /// closed-by-default and metered, so an ineligible request surfaces a translated error
    /// from the review sheet instead of a client-side paywall.
    private func presentTranslateRecipe() {
        guard ensureTranslationCoordinator() else {
            feedbackMessage = RecipeTranslationCoordinatorError.invalidConfiguration
                .localizedDescription
            return
        }
        isChoosingTranslation = true
    }

    @discardableResult
    private func ensureTranslationCoordinator() -> Bool {
        if translationCoordinator == nil {
            translationCoordinator = try? RecipeTranslationCoordinator(bundle: .main)
        }
        return translationCoordinator != nil
    }

    private func handleEditResult(_ result: RecipeEditProposalRequestResult) {
        if let proposal = result.proposal {
            proposalToReview = RecipeEditReviewContext(
                proposal: proposal,
                proposalID: result.proposalID,
                operationID: result.operationID,
                wireChanges: result.wireChanges
            )
        } else {
            feedbackMessage = RecipeEditProposalServiceError.needsManualEdit.localizedDescription
            isEditing = true
        }
    }

    /// Persists a recovery intent, approves on the server (usage finalize), applies
    /// the validated receipt to the correct local target, then ACKs only after the
    /// local durable write succeeds. The provider is never re-invoked on replay.
    private func applyEdit(
        _ reviewed: RecipeEditProposal,
        context: RecipeEditReviewContext,
        asVariant: Bool
    ) async throws -> Recipe {
        guard let service = editService else {
            throw RecipeEditProposalServiceError.invalidConfiguration
        }
        guard let current = store.recipe(id: recipeID) else {
            throw RecipeEditProposalServiceError.invalidResponse
        }
        guard let ownerID = currentOwnerID() else {
            throw RecipeEditProposalServiceError.notSignedIn
        }

        let mode: RecipeEditApplyMode = asVariant ? .variant : .apply
        let variantID = asVariant
            ? RecipeEditProposalService.stableVariantID(operationID: context.operationID)
            : nil
        let reviewedChanges = try RecipeEditProposalService.reviewedWireChanges(
            reviewed: reviewed, wireChanges: context.wireChanges
        )

        // Persist the recovery intent before the server approves/finalizes so a crash
        // between approval and the local write can be resumed without re-invoking the
        // provider.
        let pendingStore = RecipeEditPendingCommitStore(
            ownerID: ownerID.uuidString.lowercased()
        )
        try pendingStore.save(
            RecipeEditPendingCommit(
                operationID: context.operationID,
                proposalID: context.proposalID,
                mode: mode,
                variantID: variantID?.uuidString.lowercased(),
                sourceRecipeID: recipeID.uuidString.lowercased(),
                basedOnUpdate: reviewed.basedOnUpdate,
                changes: reviewedChanges,
                reasons: reviewed.reasons,
                warnings: reviewed.warnings
            )
        )

        // Server approval (usage finalize) with an explicit apply/variant target.
        let receipt = try await service.approve(
            proposalID: context.proposalID,
            reviewed: reviewed,
            wireChanges: context.wireChanges,
            recipe: current,
            mode: mode,
            variantID: variantID
        )

        // Record the approved receipt (target) so a later recovery can write and ACK
        // directly without replaying the approval.
        try pendingStore.save(
            RecipeEditPendingCommit(
                operationID: context.operationID,
                proposalID: context.proposalID,
                mode: mode,
                variantID: variantID?.uuidString.lowercased(),
                sourceRecipeID: recipeID.uuidString.lowercased(),
                basedOnUpdate: reviewed.basedOnUpdate,
                changes: reviewedChanges,
                reasons: reviewed.reasons,
                warnings: reviewed.warnings,
                targetID: receipt.targetID
            )
        )

        // Apply the validated receipt to the correct local target.
        let saved: Recipe
        if asVariant {
            guard let targetID = UUID(uuidString: receipt.targetID) else {
                throw RecipeEditProposalServiceError.invalidResponse
            }
            var variant = try reviewed.approvedRecipe(from: current, at: .now, asVariant: true)
            variant.id = targetID
            try store.upsert(variant)
            saved = variant
            feedbackMessage = String(
                localized: LocalizedStringResource(
                    "Saved a new private recipe.", locale: RecipeLanguage.active
                )
            )
        } else {
            saved = try store.applyApprovedRecipeEdit(reviewed, asVariant: false)
            undoState = RecipeEditUndoState(before: current, appliedRevision: saved.updatedAt)
        }

        // ACK only after the local durable write succeeded. A failed ACK keeps the
        // pending intent so a later recovery can re-ack idempotently.
        do {
            _ = try await service.ack(
                proposalID: context.proposalID, operationID: context.operationID
            )
            pendingStore.clear()
        } catch {
            // The local write is durable; leave the pending intent for recovery.
        }

        return saved
    }

    private func currentOwnerID() -> UUID? {
        if case .signedIn(let userID, _) = RecipeAuthService.shared.state {
            return userID
        }
        return nil
    }

    /// Resumes a pending approve → write → ACK intent on detail re-entry (e.g. after a
    /// crash between approval and the local write). Re-applies the exact reviewed
    /// changes to the correct target without re-invoking the provider, and clears the
    /// intent only after the server ACKs. Fails closed on owner switch, a deleted
    /// recipe, a stale revision, or an existing manual edit.
    private func resumePendingEditIfNeeded() async {
        guard ensureEditService(), let service = editService,
            let ownerID = currentOwnerID()
        else {
            return
        }
        let pendingStore = RecipeEditPendingCommitStore(
            ownerID: ownerID.uuidString.lowercased()
        )
        guard let pending = pendingStore.load() else {
            return
        }
        // Only the source recipe's detail view recovers its own intent.
        guard pending.sourceRecipeID == recipeID.uuidString.lowercased() else {
            return
        }
        // Tombstone guard: the source recipe was deleted; nothing to recover.
        guard let current = store.recipe(id: recipeID) else {
            pendingStore.clear()
            return
        }
        // Revision / existing-manual-edit guard: never overwrite a recipe that
        // changed after the proposal was generated.
        guard current.updatedAt == pending.basedOnUpdate else {
            pendingStore.clear()
            return
        }
        guard let proposal = RecipeEditProposalService.proposal(from: pending) else {
            pendingStore.clear()
            return
        }
        do {
            // Recover the approved receipt (stored, or via the owner-scoped
            // approve/replay route) without re-invoking the provider.
            let targetID: String
            if let stored = pending.targetID {
                targetID = stored
            } else {
                let receipt = try await service.approve(
                    proposalID: pending.proposalID,
                    reviewed: proposal,
                    wireChanges: pending.changes,
                    recipe: current,
                    mode: pending.mode,
                    variantID: pending.variantID.flatMap(UUID.init(uuidString:))
                )
                targetID = receipt.targetID
            }
            // Local durable write before ACK.
            switch pending.mode {
            case .variant:
                if let variantID = UUID(uuidString: targetID),
                    store.recipe(id: variantID) == nil
                {
                    var variant = try proposal.approvedRecipe(
                        from: current, at: .now, asVariant: true
                    )
                    variant.id = variantID
                    try store.upsert(variant)
                }
            case .apply:
                try store.applyApprovedRecipeEdit(proposal, asVariant: false)
            }
            // ACK then clear only after the server confirms.
            _ = try await service.ack(
                proposalID: pending.proposalID, operationID: pending.operationID
            )
            pendingStore.clear()
        } catch {
            // Transient transport failure or a server-side stale rejection: keep the
            // intent for a later attempt; a stale/deleted source is already cleared by
            // the guards above.
        }
    }

    /// One-session undo only when the stored recipe is still the revision this view
    /// just applied. Variants and later edits are never undone.
    private func undoEdit() {
        guard let undoState,
            let current = store.recipe(id: recipeID),
            current.updatedAt == undoState.appliedRevision
        else {
            self.undoState = nil
            return
        }
        do {
            try store.upsert(undoState.before)
        } catch {
            feedbackMessage = error.localizedDescription
        }
        self.undoState = nil
    }

    private var undoBanner: some View {
        HStack {
            Text("Changes applied")
                .font(RecipeTheme.text(15, weight: .semibold, relativeTo: .subheadline))
            Spacer()
            Button("Undo") {
                undoEdit()
            }
            .font(RecipeTheme.text(15, weight: .semibold, relativeTo: .subheadline))
            .accessibilityIdentifier("undoRecipeEdit")
        }
        .padding(RecipeSpacing.medium)
        .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var servingsSelection: Binding<Int> {
        Binding(
            get: {
                servings
            },
            set: {
                servings = $0
                didAdjustServings = true
            })
    }

    private var feedbackPresented: Binding<Bool> {
        Binding(
            get: {
                feedbackMessage != nil
            },
            set: {
                if !$0 {
                    feedbackMessage = nil
                }
            }
        )
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
        guard !isDeletingRecipe else {
            return
        }
        isDeletingRecipe = true
        Task { @MainActor in
            defer {
                isDeletingRecipe = false
            }
            do {
                if ownerSharing.isConfiguredForOwnerSharing {
                    try await ownerSharing.deleteRecipe(recipeID: recipeID, store: store)
                } else {
                    // This build has never enabled publication. Preserve its private collection flow.
                    // Missing configuration itself is not evidence about remote public-copy state.
                    try store.deleteRecipe(id: recipeID)
                }
                CookingView.discardSession(recipeID: recipeID)
                dismiss()
            } catch is CancellationError {
                // Cancellation preserves the recipe and does not claim a successful deletion.
            } catch {
                guard ownerSharing.isConfiguredForOwnerSharing else {
                    feedbackMessage = error.localizedDescription
                    return
                }
                feedbackMessage = String(
                    localized: LocalizedStringResource(
                        "Could not stop sharing. Your recipe is still saved. Check your connection and try again.",
                        locale: RecipeLanguage.active
                    )
                )
            }
        }
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
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onAppear {
            guard !didLoad, let recipe = store.recipe(id: recipeID) else {
                return
            }
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
                ) {
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
            Button("Add \(selection.count) ingredient") {
                add(recipe)
            }
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
            let knownServings =
                recipe.servings.map {
                    $0 > 0
                } ?? false
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
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert(
                "Collections",
                isPresented: Binding(
                    get: {
                        errorMessage != nil
                    },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
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
                    ForEach(MealSlot.allCases) {
                        Text(LocalizedStringKey($0.rawValue)).tag($0)
                    }
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
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
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
    var stepID: UUID?
    var timerID: UUID?

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

    static func timing(_ recipe: Recipe) -> RecipeParameterInfo {
        var lines: [String] = []
        if let prep = recipe.prepMinutes, prep >= 0 {
            let title = String(
                localized: LocalizedStringResource(
                    "Prep time (minutes)", locale: RecipeLanguage.active))
            lines.append("\(title): \(prep.formatted())")
        }
        if let cook = recipe.cookMinutes, cook >= 0 {
            let title = String(
                localized: LocalizedStringResource(
                    "Cook time (minutes)", locale: RecipeLanguage.active))
            lines.append("\(title): \(cook.formatted())")
        }
        return RecipeParameterInfo(
            title: String(
                localized: LocalizedStringResource("Cooking Time", locale: RecipeLanguage.active)),
            lines: lines
        )
    }

    static func timer(_ timer: RecipeStepTimer, stepID: UUID) -> RecipeParameterInfo {
        let amount = Duration.seconds(timer.durationSeconds).formatted(
            .units(width: .wide, maximumUnitCount: 2))
        return RecipeParameterInfo(
            title: timer.label.isEmpty ? "Step timer" : timer.label,
            lines: ["Duration: \(amount)"],
            stepID: stepID,
            timerID: timer.id
        )
    }
}

struct RecipeParameterSheet: View {
    let info: RecipeParameterInfo
    var timerActionTitle: LocalizedStringKey = "Start Timer"
    var onTimerAction: (() -> Void)?
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
                if info.timerID != nil, let onTimerAction {
                    Button {
                        onTimerAction()
                        dismiss()
                    } label: {
                        Label(timerActionTitle, systemImage: "play.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("parameterTimerAction")
                }
                Spacer(minLength: 0)
            }
            .padding(RecipeSpacing.pageInset)
            .background(RecipeTheme.canvas)
            .navigationTitle(info.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
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
            .environment(
                \.openURL,
                OpenURLAction { url in
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
                        guard
                            let timer = step.timers.first(where: {
                                $0.id == timerID
                            })
                        else {
                            return .discarded
                        }
                        selection = .timer(timer, stepID: step.id)
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
    @Environment(RecipeCommerceComposition.self) private var commerce
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<String>()
    @State private var errorMessage: String?
    @State private var isSaving = false

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
                                Image(
                                    systemName: selected.contains(candidate.candidateID)
                                        ? "checkmark.circle.fill" : "circle"
                                )
                                .foregroundStyle(RecipeTheme.accentForeground)
                                .font(.system(size: 22))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(candidate.title ?? "Untitled Recipe")
                                        .font(
                                            RecipeTheme.text(
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
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save selected") {
                        isSaving = true
                        Task {
                            defer { isSaving = false }
                            do {
                                try await saveSelected()
                                dismiss()
                            } catch { errorMessage = error.localizedDescription }
                        }
                    }
                    .disabled(selected.isEmpty || isSaving)
                    .accessibilityIdentifier("saveSelectedCandidateRecipes")
                }
            }
            .alert(
                "Could not save recipes",
                isPresented: Binding(
                    get: {
                        errorMessage != nil
                    },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func saveSelected() async throws {
        guard let sourceRecord = sourceRecipe.importRecord else {
            return
        }
        let chosen = candidates.filter { selected.contains($0.candidateID) }
        guard !chosen.isEmpty else {
            return
        }

        // Media-import sources (VTT/audio/video) route through the media bundle port;
        // the durable mediaMimeType marker is set by the backend, never guessed here.
        if sourceRecord.mediaMimeType != nil {
            try await saveMediaSelected(sourceRecord: sourceRecord, chosen: chosen)
            return
        }

        // Free first release keeps the existing unmetered save byte-equivalent.
        guard RecipeMonetization.isEnabled else {
            try saveUnmetered(sourceRecord: sourceRecord, chosen: chosen)
            return
        }
        // Commercial settle requires a live bridge and a bound owner. A missing
        // bridge/owner must fail closed (no save, no ACK) so quota can never be
        // bypassed by silently falling back to the unmetered write.
        let startContext = commerce.importUsageContext
        guard let importUsage = commerce.importUsage else {
            throw RecipeImportCandidateSaveError.bridgeUnavailable
        }
        guard let ownerID = startContext.ownerID else {
            throw RecipeImportCandidateSaveError.signedOut
        }
        // The authoritative share receipt identity must be durable for the bridge to
        // associate each reservation with the same source. A legacy record without it
        // is never settled under a fabricated id.
        guard let receiptID = sourceRecord.receiptID else {
            throw RecipeImportCandidateSaveError.missingReceipt
        }

        // Phase 1: reserve every selected candidate before any finalize, so a partial
        // reserve failure can release only the still-unfinalized reservations.
        var reserved: [ReservedCandidate] = []
        for candidate in chosen {
            let outcome: RecipeImportUsageReserveOutcome
            do {
                outcome = try await importUsage.reserve(
                    ownerID: ownerID,
                    jobID: sourceRecord.jobID,
                    candidateID: candidate.candidateID,
                    receiptID: receiptID
                )
            } catch {
                await releaseUnfinalized(reserved, ownerID: ownerID, importUsage: importUsage)
                throw error
            }
            switch outcome {
            case .awaitingUpgrade:
                await releaseUnfinalized(reserved, ownerID: ownerID, importUsage: importUsage)
                throw RecipeImportCandidateSaveError.upgradeRequired
            case .reserved(let reservation):
                reserved.append(
                    ReservedCandidate(
                        candidate: candidate,
                        operation: RecipeImportUsageOperation(
                            operationID: RecipeImportUsageOperation.stableOperationID(
                                ownerID: ownerID,
                                jobID: sourceRecord.jobID,
                                candidateID: candidate.candidateID
                            ),
                            ownerID: ownerID,
                            jobID: sourceRecord.jobID,
                            candidateID: candidate.candidateID,
                            receiptID: receiptID,
                            state: .reserved,
                            reservedUntil: reservation.reservedUntil
                        )
                    )
                )
            }
        }

        // Phase 2: finalize -> hash match -> durable save -> ACK, per candidate.
        for item in reserved {
            try await settleReserved(
                item,
                sourceRecord: sourceRecord,
                ownerID: ownerID,
                startContext: startContext,
                importUsage: importUsage
            )
        }
    }

    private func saveMediaSelected(
        sourceRecord: RecipeImportRecord,
        chosen: [RecipeImportJobResponse.Candidate]
    ) async throws {
        // Free first release: media metering is closed by default, so keep the
        // existing unmetered save (the media bundle port is unavailable).
        guard RecipeMonetization.isEnabled else {
            try saveUnmetered(sourceRecord: sourceRecord, chosen: chosen)
            return
        }
        let startContext = commerce.importUsageContext
        guard let mediaPort = commerce.mediaBundlePort else {
            throw RecipeImportCandidateSaveError.bridgeUnavailable
        }
        guard let importUsage = commerce.importUsage else {
            throw RecipeImportCandidateSaveError.bridgeUnavailable
        }
        guard let ownerID = startContext.ownerID else {
            throw RecipeImportCandidateSaveError.signedOut
        }
        guard let receiptID = sourceRecord.receiptID else {
            throw RecipeImportCandidateSaveError.missingReceipt
        }

        // Atomic media bundle reserve persists each candidate's durable intent before
        // the RPC and returns the stored `.reserved` operations.
        let outcome = try await mediaPort.reserveBundle(
            ownerID: ownerID,
            jobID: sourceRecord.jobID,
            candidateIDs: chosen.map(\.candidateID),
            receiptID: receiptID,
            currentOwner: { self.currentOwnerContext() }
        )
        switch outcome {
        case .awaitingUpgrade:
            throw RecipeImportCandidateSaveError.upgradeRequired
        case .reserved(_, let operations):
            var pending = operations
            do {
                for candidate in chosen {
                    guard let index = pending.firstIndex(where: {
                        $0.candidateID == candidate.candidateID
                    }) else {
                        throw RecipeImportCandidateSaveError.invalidResponse
                    }
                    let operation = pending.remove(at: index)
                    try await settleReserved(
                        ReservedCandidate(candidate: candidate, operation: operation),
                        sourceRecord: sourceRecord,
                        ownerID: ownerID,
                        startContext: startContext,
                        importUsage: importUsage
                    )
                }
                // Settle the reserved media_import unit after every candidate settles.
                _ = try await mediaPort.finalizeMedia(
                    ownerID: ownerID,
                    jobID: sourceRecord.jobID,
                    currentOwner: { self.currentOwnerContext() }
                )
            } catch {
                // Partial failure: release only the still-unfinalized candidate
                // reservations, then the media unit; finalized/failed operations stay
                // in the recovery store.
                for operation in pending {
                    try? await importUsage.cancel(ownerID: ownerID, operation: operation)
                }
                try? await mediaPort.releaseMedia(ownerID: ownerID, jobID: sourceRecord.jobID)
                throw error
            }
        }
    }

    private func currentOwnerContext() -> (ownerID: UUID?, generation: Int) {
        let context = commerce.importUsageContext
        return (context.ownerID, context.generation)
    }

    private func settleReserved(
        _ item: ReservedCandidate,
        sourceRecord: RecipeImportRecord,
        ownerID: UUID,
        startContext: RecipeCommerceComposition.ImportUsageContext,
        importUsage: RecipeImportUsageBridge
    ) async throws {
        let response = try await importUsage.finalize(
            ownerID: ownerID, operation: item.operation
        )
        // Owner/session must be unchanged before any local write or ACK.
        try requireContext(startContext)

        // Raw payload hash match: a missing or mismatched hash fails closed so an
        // unverified candidate is never persisted, and the finalized operation stays
        // in the recovery store.
        guard let candidateHash = item.candidate.payloadHash else {
            throw RecipeImportCandidateSaveError.missingPayloadHash
        }
        guard candidateHash == response.payloadHash else {
            throw RecipeImportCandidateSaveError.payloadHashMismatch
        }
        guard let recipeID = UUID(uuidString: response.recipeID) else {
            throw RecipeImportCandidateSaveError.invalidResponse
        }

        let recipe = Self.buildCandidateRecipe(
            item.candidate,
            sourceRecipe: sourceRecipe,
            sourceRecord: sourceRecord,
            recipeID: recipeID
        )
        // Never overwrite a locally edited recipe with a replayed settle result.
        try requireContext(startContext)
        if store.recipe(id: recipeID) == nil {
            try store.upsert(recipe)
        }
        try requireContext(startContext)
        try await importUsage.acknowledge(ownerID: ownerID, operation: item.operation)
    }

    private func requireContext(
        _ start: RecipeCommerceComposition.ImportUsageContext
    ) throws {
        guard commerce.importUsageContext == start else {
            throw RecipeImportCandidateSaveError.ownerChanged
        }
    }

    private func releaseUnfinalized(
        _ reserved: [ReservedCandidate],
        ownerID: UUID,
        importUsage: RecipeImportUsageBridge
    ) async {
        for item in reserved {
            try? await importUsage.cancel(ownerID: ownerID, operation: item.operation)
        }
    }

    private func saveUnmetered(
        sourceRecord: RecipeImportRecord,
        chosen: [RecipeImportJobResponse.Candidate]
    ) throws {
        for candidate in chosen {
            let targetID = Self.stableChildID(
                sourceID: sourceRecipe.id, candidateID: candidate.candidateID)
            // Repeated saves do not duplicate a dish or overwrite user edits.
            if store.recipe(id: targetID) != nil {
                continue
            }
            let recipe = Self.buildCandidateRecipe(
                candidate,
                sourceRecipe: sourceRecipe,
                sourceRecord: sourceRecord,
                recipeID: targetID
            )
            try store.upsert(recipe)
        }
    }

    private static func buildCandidateRecipe(
        _ candidate: RecipeImportJobResponse.Candidate,
        sourceRecipe: Recipe,
        sourceRecord: RecipeImportRecord,
        recipeID: UUID
    ) -> Recipe {
        let title = candidate.title ?? "Untitled Recipe"
        let content =
            title
            + "\n\nIngredients\n" + candidate.ingredients.joined(separator: "\n")
            + "\n\nInstructions\n" + candidate.steps.joined(separator: "\n")
        var recipe = RecipeDocumentParser.recipe(fromText: content, title: title)
        recipe.id = recipeID
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
            recipeID: recipeID,
            status: candidate.reviewFields.isEmpty ? "ready" : "needs_review",
            source: sourceRecord.result.source,
            fields: fields,
            evidence: evidence,
            reviewFields: candidate.reviewFields
        )
        recipe.importRecord = RecipeImportRecord(
            jobID: sourceRecord.jobID,
            result: result,
            selectedCandidateID: candidate.candidateID,
            clientRequestID: sourceRecord.clientRequestID,
            receiptID: sourceRecord.receiptID
        )
        return recipe
    }

    private struct ReservedCandidate {
        let candidate: RecipeImportJobResponse.Candidate
        let operation: RecipeImportUsageOperation
    }

    private static func stableChildID(sourceID: UUID, candidateID: String) -> UUID {
        let key = Data("\(sourceID.uuidString):\(candidateID)".utf8)
        let digest = Array(SHA256.hash(data: key))
        return UUID(
            uuid: (
                digest[0], digest[1], digest[2], digest[3],
                digest[4], digest[5], digest[6], digest[7],
                digest[8], digest[9], digest[10], digest[11],
                digest[12], digest[13], digest[14], digest[15]
            ))
    }
}

private enum RecipeImportCandidateSaveError: LocalizedError {
    case missingReceipt
    case ownerChanged
    case bridgeUnavailable
    case signedOut
    case missingPayloadHash
    case payloadHashMismatch
    case upgradeRequired
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingReceipt:
            return RecipeLanguage.localized("This source cannot be settled. Try sharing it again.")
        case .ownerChanged:
            return RecipeLanguage.localized("The signed-in account changed. Your selection was kept.")
        case .bridgeUnavailable:
            return RecipeLanguage.localized("The import quota service is unavailable. Your selection was kept.")
        case .signedOut:
            return RecipeLanguage.localized("Sign in to save these recipes. Your selection was kept.")
        case .missingPayloadHash:
            return RecipeLanguage.localized("The selected recipe is incomplete. Choose another source.")
        case .payloadHashMismatch:
            return RecipeLanguage.localized("The saved result did not match the source. Nothing was changed.")
        case .upgradeRequired:
            return RecipeLanguage.localized("Saving more recipes requires Premium.")
        case .invalidResponse:
            return RecipeLanguage.localized("The service returned an invalid response.")
        }
    }
}


/// Review an untrusted AI edit proposal before mutating private recipe data. The
/// provider only emits the three value-replacement change paths; this sheet never
/// persists until the user explicitly applies a reviewed (and optionally edited) proposal.
private struct RecipeEditProposalReviewSheet: View {
    let proposal: RecipeEditProposal
    let apply: (RecipeEditProposal, Bool) async throws -> Recipe

    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var isApplying = false
    // Store only user edits. Do not eagerly copy unvalidated provider changes.
    @State private var proposedTexts: [Int: String] = [:]

    // Only allow edits to the three already approved RecipeEditChange cases.
    // Rebuild the validated proposal instead of directly saving edited text.
    private var reviewedProposal: RecipeEditProposal {
        let changes: [RecipeEditChange] = proposal.changes.enumerated().map { index, change in
            switch change {
            case .ingredientName(let id, let original, let proposed):
                return .ingredientName(
                    id: id, original: original,
                    proposed: proposedTexts[index] ?? proposed
                )
            case .ingredientAmount(let id, let original, let proposed):
                return .ingredientAmount(
                    id: id, original: original,
                    proposed: proposedTexts[index] ?? proposed
                )
            case .stepInstruction(let id, let original, let proposed):
                return .stepInstruction(
                    id: id, original: original,
                    proposed: proposedTexts[index] ?? proposed
                )
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

    // Validate the original untrusted proposal before constructing any rows or
    // editable replacements. Core owns the change/text/explanation budgets.
    private var sourcePreview: RecipeEditPreview? {
        guard let current = store.recipe(id: proposal.recipeID) else {
            return nil
        }
        return try? proposal.preview(on: current)
    }

    // Invalid user edits must leave the initially valid fields editable.
    // The Store checks the latest revision again when committing.
    private var preview: RecipeEditPreview? {
        guard sourcePreview != nil,
            let current = store.recipe(id: proposal.recipeID)
        else {
            return nil
        }
        return try? reviewedProposal.preview(on: current)
    }

    private var reviewRows: [RecipeEditReviewRow] {
        guard sourcePreview != nil else {
            return []
        }
        return proposal.changes.enumerated().map { index, change in
            let field: String
            let before: String
            let proposed: String
            switch change {
            case .ingredientName(_, let original, let replacement):
                field = "Ingredient name"
                before = original
                proposed = replacement
            case .ingredientAmount(_, let original, let replacement):
                field = "Ingredient amount"
                before = original
                proposed = replacement
            case .stepInstruction(_, let original, let replacement):
                field = "Step instruction"
                before = original
                proposed = replacement
            }
            return RecipeEditReviewRow(
                id: index, field: field, before: before, proposed: proposed
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RecipeSpacing.medium) {
                    if isStale {
                        Text("This recipe changed. Get a new suggestion before saving.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("staleRecipeProposal")
                    } else if sourcePreview != nil {
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
                                    text: Binding(
                                        get: { proposedTexts[row.id] ?? row.proposed },
                                        set: { proposedTexts[row.id] = $0 }
                                    ),
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
                        Text("Check the proposed text. It cannot be empty or too long.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("invalidRecipeProposal")
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
                        .disabled(preview == nil || isApplying)
                        .accessibilityIdentifier("applyRecipeProposal")
                    Button("Save as new recipe") { save(asVariant: true) }
                        .buttonStyle(RecipeDetailActionButtonStyle(variant: .secondary))
                        .disabled(preview == nil || isApplying)
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
        guard preview != nil, !isApplying else {
            return
        }
        isApplying = true
        Task {
            defer { isApplying = false }
            do {
                _ = try await apply(reviewedProposal, asVariant)
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
}

/// Captures the adjust intent and an optional free-text supplement before dispatch.
private struct RecipeEditIntentSheet: View {
    let recipe: Recipe
    let service: RecipeEditProposalService
    let onResult: (RecipeEditProposalRequestResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var intent: RecipeEditIntent = .substitute
    @State private var supplement = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    // Stable per-intent operation id: a retry of the same edit request replays the
    // already-persisted proposal instead of re-invoking the provider. Changing the
    // intent or the notes mints a fresh id so separate requests stay distinct.
    @State private var operationID = UUID()

    private var canGenerate: Bool {
        !isGenerating && !recipe.ingredients.isEmpty && !recipe.steps.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Adjustment", selection: $intent) {
                        ForEach(RecipeEditIntent.allCases) { intent in
                            Text(Self.title(intent)).tag(intent)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Adjustment")
                } footer: {
                    Text(Self.detail(intent))
                }
                Section {
                    TextField("Notes (optional)", text: $supplement, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Notes (optional)")
                } footer: {
                    Text(
                        "Describe the change you want, for example which ingredient to substitute or what diet to follow."
                    )
                }
            }
            .navigationTitle("Adjust Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") { generate() }
                        .disabled(!canGenerate)
                }
            }
            .alert(
                "Couldn't generate suggestions",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
            .onChange(of: intent) { _, _ in
                operationID = UUID()
            }
            .onChange(of: supplement) { _, _ in
                operationID = UUID()
            }
        }
    }

    private func generate() {
        guard canGenerate else {
            return
        }
        isGenerating = true
        Task {
            defer { isGenerating = false }
            do {
                let trimmed = supplement.trimmingCharacters(in: .whitespacesAndNewlines)
                let result = try await service.createProposal(
                    recipe: recipe,
                    intent: intent,
                    supplement: trimmed.isEmpty ? nil : trimmed,
                    operationID: operationID
                )
                dismiss()
                onResult(result)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func title(_ intent: RecipeEditIntent) -> String {
        switch intent {
        case .substitute:
            return RecipeLanguage.localized("Substitute ingredients")
        case .simplify:
            return RecipeLanguage.localized("Simplify steps")
        case .dietary:
            return RecipeLanguage.localized("Dietary adjustments")
        }
    }

    private static func detail(_ intent: RecipeEditIntent) -> String {
        switch intent {
        case .substitute:
            return RecipeLanguage.localized("Swap an ingredient for an alternative.")
        case .simplify:
            return RecipeLanguage.localized("Reduce steps or techniques.")
        case .dietary:
            return RecipeLanguage.localized("Adapt the recipe for a diet or allergy.")
        }
    }
}

private struct RecipeEditReviewRow: Identifiable {
    let id: Int
    let field: String
    let before: String
    let proposed: String
}
