// Developer: gengyun
// Purpose: Implements recipe editing for metadata, ingredients, steps, temperatures, and timers.

import PhotosUI
import RecipeCore
import SwiftUI

struct RecipeEditorView: View {
    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Recipe
    @State private var original: Recipe
    @State private var servingsText: String
    @State private var prepText: String
    @State private var cookText: String
    @State private var sourceText: String
    @State private var photo: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var showDiscard = false
    @State private var isLoadingPhoto = false
    private var isExisting: Bool { store.recipe(id: draft.id) != nil }

    init(recipe: Recipe? = nil) {
        var value = recipe ?? Recipe(title: "")
        if value.ingredients.isEmpty { value.ingredients = [RecipeIngredient(name: "")] }
        if value.steps.isEmpty { value.steps = [RecipeStep(instruction: "")] }
        _draft = State(initialValue: value)
        _original = State(initialValue: value)
        _servingsText = State(initialValue: value.servings.map(String.init) ?? "")
        _prepText = State(initialValue: value.prepMinutes.map(String.init) ?? "")
        _cookText = State(initialValue: value.cookMinutes.map(String.init) ?? "")
        _sourceText = State(initialValue: value.sourceURL ?? "")
    }

    // Keep empty optional editor fields absent from older recipe records.
    private func optionalStringBinding(
        _ path: WritableKeyPath<Recipe, String?>
    ) -> Binding<String> {
        Binding(
            get: { draft[keyPath: path] ?? "" },
            set: { input in
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                draft[keyPath: path] = trimmed.isEmpty ? nil : input
            }
        )
    }

    private func commaSeparatedBinding(
        _ path: WritableKeyPath<Recipe, [String]?>
    ) -> Binding<String> {
        Binding(
            get: { draft[keyPath: path]?.joined(separator: ", ") ?? "" },
            set: { input in
                let values = input.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                draft[keyPath: path] = values.isEmpty ? nil : values
            }
        )
    }

    var body: some View {
        let photoLabel = draft.coverData == nil ? "Add a photo" : "Change photo"
        NavigationStack {
            Form {
                Section {
                    RecipeImage(recipe: draft, height: 180).clipShape(
                        RoundedRectangle(cornerRadius: 18)
                    )
                    .listRowInsets(EdgeInsets())
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label {
                            Text(LocalizedStringKey(photoLabel))
                        } icon: {
                            Image(systemName: "photo")
                        }
                    }.disabled(isLoadingPhoto)
                    if isLoadingPhoto { ProgressView("Preparing photo…") }
                }
                Section("Recipe") {
                    TextField("Recipe name", text: $draft.title).accessibilityIdentifier(
                        "recipeName")
                    TextField("A short description", text: $draft.summary, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Category", selection: $draft.category) {
                        ForEach(RecipeCategory.allCases) {
                            Text(LocalizedStringKey($0.rawValue)).tag($0)
                        }
                    }
                    Picker("Difficulty", selection: $draft.difficulty) {
                        Text("Unknown").tag(nil as RecipeDifficulty?)
                        ForEach(RecipeDifficulty.allCases) { difficulty in
                            Text(LocalizedStringKey(difficulty.rawValue))
                                .tag(Optional(difficulty))
                        }
                    }
                    TextField("Cuisine (optional)", text: optionalStringBinding(\.cuisine))
                    TextField(
                        "Dietary tags (comma separated)",
                        text: commaSeparatedBinding(\.dietaryTags)
                    )
                    numberField("Servings", placeholder: "Unknown", text: $servingsText)
                    numberField("Prep time (minutes)", placeholder: "Optional", text: $prepText)
                    numberField("Cook time (minutes)", placeholder: "Optional", text: $cookText)
                }
                Section {
                    ForEach($draft.ingredients) { $ingredient in
                        IngredientEditorRow(ingredient: $ingredient) {
                            draft.removeIngredient(id: ingredient.id)
                        }
                    }
                    Button {
                        draft.ingredients.append(RecipeIngredient(name: ""))
                    } label: {
                        Label("Add ingredient", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Ingredients")
                }
                Section("Steps") {
                    ForEach($draft.steps) { $step in
                        StepEditorRow(step: $step, ingredients: draft.ingredients) {
                            draft.removeStep(id: step.id)
                        }
                    }
                    Button {
                        draft.steps.append(RecipeStep(instruction: ""))
                    } label: {
                        Label("Add step", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("addRecipeStep")
                }
                Section("Details") {
                    TextField(
                        "Equipment (comma separated)",
                        text: commaSeparatedBinding(\.equipment)
                    )
                    TextField("Yield (optional)", text: optionalStringBinding(\.yieldDescription))
                    TextField(
                        "Preparation tips", text: optionalStringBinding(\.preparationTips),
                        axis: .vertical
                    ).lineLimit(2...4)
                    TextField(
                        "Storage notes", text: optionalStringBinding(\.storageNotes),
                        axis: .vertical
                    ).lineLimit(2...4)
                }
                Section("Notes") {
                    TextField("Your notes and changes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...10)
                }
                Section("Source") {
                    if let value = original.sourceURL {
                        if let url = RecipeDocumentParser.validatedSourceURL(value) {
                            Link(destination: url) {
                                Label(
                                    original.sourceName ?? "Open original recipe",
                                    systemImage: "arrow.up.right.square")
                            }
                        }
                        Text(value).font(
                            RecipeTheme.text(13, weight: .regular, relativeTo: .footnote)
                        )
                        .foregroundStyle(.secondary).textSelection(.enabled)
                    } else {
                        TextField("Original link (optional)", text: $sourceText)
                            .keyboardType(.URL).textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if let text = original.sourceText, !text.isEmpty {
                        DisclosureGroup("Original recipe text") {
                            Text(text).font(
                                RecipeTheme.text(13, weight: .regular, relativeTo: .footnote)
                            )
                            .textSelection(.enabled)
                        }
                    }
                }
                if previewNeedsReview {
                    Section {
                        Label("Needs review", systemImage: "pencil.circle")
                            .font(RecipeTheme.text(
                                15, weight: .regular, relativeTo: .subheadline))
                            .foregroundStyle(.secondary)
                        if let importResult = draft.importRecord?.result,
                            draft.importRecord?.reviewedAt == nil
                        {
                            ForEach(RecipeImportReviewPlan.questions(from: importResult)) {
                                question in
                                Text(LocalizedStringKey(question.question))
                                    .font(RecipeTheme.text(13, relativeTo: .footnote))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listSectionSpacing(RecipeSpacing.medium)
            .contentMargins(.top, RecipeSpacing.pageTop, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(RecipeTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(LocalizedStringKey(isExisting ? "Edit recipe" : "New recipe"))
            .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if isDirty { showDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey(previewNeedsReview ? "Save draft" : "Save")) { save() }
                        .disabled(
                            draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || isLoadingPhoto
                        )
                        .accessibilityIdentifier("saveRecipe")
                }
            }
            .interactiveDismissDisabled(isDirty)
            .confirmationDialog(
                "Discard your changes?", isPresented: $showDiscard, titleVisibility: .visible
            ) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .alert(
                "Couldn't save your recipe",
                isPresented: Binding(
                    get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task(id: photo) {
                guard let photo else { return }
                isLoadingPhoto = true
                defer { isLoadingPhoto = false }
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self) else {
                        throw RecipeImportError.unreadableImage
                    }
                    try Task.checkCancellation()
                    draft.coverData = try RecipeImportService.normalizedPhoto(data)
                    draft.coverAsset = nil
                } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
            }
        }
    }

    private var isDirty: Bool {
        draft != original || servingsText != (original.servings.map(String.init) ?? "")
            || prepText != (original.prepMinutes.map(String.init) ?? "")
            || cookText != (original.cookMinutes.map(String.init) ?? "")
            || sourceText != (original.sourceURL ?? "")
    }

    private var previewNeedsReview: Bool {
        var preview = draft
        preview.ingredients = draft.ingredients.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || $0.quantity != nil || !($0.unit ?? "").isEmpty
        }
        preview.steps = draft.steps.filter(hasStepContent)
        return preview.needsReview
    }

    private func hasStepContent(_ step: RecipeStep) -> Bool {
        !step.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || step.temperature != nil
            || !step.timers.isEmpty
            || !step.linkedIngredientIDs.isEmpty
    }

    private func numberField(_ title: String, placeholder: String, text: Binding<String>)
        -> some View
    {
        HStack {
            Text(LocalizedStringKey(title))
            Spacer()
            TextField(RecipeLanguage.localized(placeholder), text: text).keyboardType(.numberPad)
                .multilineTextAlignment(.trailing).frame(maxWidth: 100)
                .accessibilityLabel(Text(LocalizedStringKey(title)))
        }
    }

    private func save() {
        do {
            var recipe = draft
            recipe.title = recipe.title.trimmingCharacters(in: .whitespacesAndNewlines)
            recipe.servings = try number(servingsText, name: RecipeLanguage.localized("Servings"), range: 1...100)
            recipe.prepMinutes = try number(prepText, name: RecipeLanguage.localized("Prep time"), range: 0...10_080)
            recipe.cookMinutes = try number(cookText, name: RecipeLanguage.localized("Cook time"), range: 0...10_080)
            recipe.ingredients = try draft.ingredients.compactMap { ingredient in
                let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let amount = ingredient.amountText.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty && amount.isEmpty && ingredient.quantity == nil
                    && (ingredient.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                {
                    return nil
                }
                guard !name.isEmpty else {
                    throw EditorError.invalid(
                        String(
                            localized: LocalizedStringResource(
                                "Give each ingredient a name, or remove the empty row.",
                                locale: RecipeLanguage.active))
                    )
                }
                if let previous = original.ingredients.first(where: { candidate in
                    candidate.id == ingredient.id
                }),
                    previous.amountText.trimmingCharacters(in: .whitespacesAndNewlines) == amount
                {
                    var item = ingredient
                    item.name = name
                    return item
                }
                var item = RecipeIngredient.from(
                    name: name, amountText: amount, category: ingredient.category)
                item.id = ingredient.id
                return item
            }
            let validIngredientIDs = Set(recipe.ingredients.map(\.id))
            recipe.steps = draft.steps.filter(hasStepContent).map { step in
                var cleaned = step
                cleaned.linkedIngredientIDs = cleaned.linkedIngredientIDs.filter(
                    validIngredientIDs.contains)
                cleaned.timers = cleaned.timers.filter { timer in
                    timer.durationSeconds > 0
                }
                if cleaned.temperature?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    == true
                {
                    cleaned.temperature = nil
                }
                return cleaned
            }
            // Empty editor rows are discarded above; their optional section/media links
            // must not remain in a saved or synced recipe.
            recipe.pruneDanglingReferences()
            if original.sourceURL == nil {
                let value = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard value.isEmpty || RecipeDocumentParser.validatedSourceURL(value) != nil else {
                    throw RecipeImportError.invalidLink
                }
                recipe.sourceURL = value.isEmpty ? nil : value
            }
            // Saving any imported recipe is an explicit local review,
            // including ones the worker initially classified as ready.
            // Later background completions must not replace manual edits.
            if recipe.importRecord != nil {
                recipe.importRecord?.reviewedAt = .now
            }
            try RecipePerformanceSignposts.measure("Recipe Write") {
                try store.upsert(recipe)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func number(_ text: String, name: String, range: ClosedRange<Int>) throws -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard let number = Int(value), range.contains(number) else {
            throw EditorError.invalid(
                String(
                    localized: LocalizedStringResource(
                        "\(name) must be a whole number between \(range.lowerBound) and \(range.upperBound), or left blank.",
                        locale: RecipeLanguage.active))
            )
        }
        return number
    }
}

private struct IngredientEditorRow: View {
    @Binding var ingredient: RecipeIngredient
    let remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
            HStack {
                TextField("Ingredient name", text: $ingredient.name).accessibilityIdentifier(
                    "ingredientName")
                Button(role: .destructive, action: remove) { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Remove ingredient \(ingredient.name)")
            }
            TextField("Amount, e.g. 2 tbsp or to taste", text: $ingredient.amountText)
                .font(RecipeTheme.text(15, weight: .regular, relativeTo: .subheadline))
                .accessibilityIdentifier("ingredientAmount")
            Picker("Shopping group", selection: $ingredient.category) {
                ForEach(GroceryCategory.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }.font(RecipeTheme.text(15, weight: .regular, relativeTo: .subheadline))
        }
        .padding(.vertical, 4)
    }
}

private struct StepEditorRow: View {
    @Binding var step: RecipeStep
    let ingredients: [RecipeIngredient]
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
            HStack {
                TextField("Step title (optional)", text: $step.title)
                Button(role: .destructive, action: remove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Remove step")
            }

            TextField("What should the cook do?", text: $step.instruction, axis: .vertical)
                .lineLimit(3...8)
                .accessibilityIdentifier("stepInstruction")

            TextField("Temperature or heat, e.g. 200°C or medium heat", text: temperatureText)
                .font(RecipeTheme.text(15, relativeTo: .subheadline))

            if !availableIngredients.isEmpty {
                DisclosureGroup("Ingredients used in this step") {
                    ForEach(availableIngredients) { ingredient in
                        Button {
                            toggleIngredient(ingredient.id)
                        } label: {
                            HStack {
                                Image(
                                    systemName: step.linkedIngredientIDs.contains(ingredient.id)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .foregroundStyle(
                                    step.linkedIngredientIDs.contains(ingredient.id)
                                        ? RecipeTheme.accentForeground
                                        : Color.secondary
                                )
                                Text(ingredient.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
                ForEach($step.timers) { $timer in
                    VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
                        HStack {
                            TextField("Timer label", text: $timer.label)
                            Button(role: .destructive) {
                                step.timers.removeAll { $0.id == timer.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("Remove timer")
                        }

                        Stepper(
                            value: $timer.durationSeconds,
                            in: 1...43_200,
                            step: 30
                        ) {
                            Text("Timer: \(durationLabel(timer.durationSeconds))")
                                .font(RecipeTheme.text(15, relativeTo: .subheadline))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(
                        RecipeTheme.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    step.timers.append(
                        RecipeStepTimer(
                            label: step.title.isEmpty ? "Step timer" : step.title,
                            durationSeconds: 300
                        )
                    )
                } label: {
                    Label("Add timer", systemImage: "timer")
                }
                .frame(minHeight: 44)
            }
        }
        .padding(.vertical, 4)
    }

    private var availableIngredients: [RecipeIngredient] {
        ingredients.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var temperatureText: Binding<String> {
        Binding(
            get: { step.temperature?.text ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                step.temperature = trimmed.isEmpty ? nil : CookingTemperature(text: value)
            }
        )
    }

    private func toggleIngredient(_ id: UUID) {
        if step.linkedIngredientIDs.contains(id) {
            step.linkedIngredientIDs.removeAll { $0 == id }
        } else {
            step.linkedIngredientIDs.append(id)
        }
    }

    private func durationLabel(_ seconds: Int) -> String {
        if seconds % 3_600 == 0 {
            return Duration.seconds(seconds).formatted(
                .units(width: .abbreviated, maximumUnitCount: 2).locale(RecipeLanguage.active)
            )
        }
        if seconds % 60 == 0 {
            return Duration.seconds(seconds).formatted(
                .units(width: .abbreviated, maximumUnitCount: 2).locale(RecipeLanguage.active)
            )
        }
        return Duration.seconds(seconds).formatted(
            .units(width: .abbreviated, maximumUnitCount: 2).locale(RecipeLanguage.active)
        )
    }
}

private enum EditorError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
}
