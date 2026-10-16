// Developer: gengyun
// Purpose: Presents a reviewable recipe translation: choose a content language, review the
//          machine translation next to the original, edit it, cancel, or save it as a variant.

import RecipeCore
import SwiftUI

struct RecipeTranslationSheet: View {
    let recipe: Recipe
    let coordinator: RecipeTranslationCoordinator

    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var target: RecipeTranslationTarget
    @State private var proposal: RecipeTranslationProposal?
    @State private var isTranslating = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var editedTitle = ""
    @State private var editedSummary = ""
    @State private var editedNames: [UUID: String] = [:]
    @State private var editedAmounts: [UUID: String] = [:]
    @State private var editedInstructions: [UUID: String] = [:]
    @State private var editedStepTitles: [UUID: String] = [:]

    init(recipe: Recipe, coordinator: RecipeTranslationCoordinator) {
        self.recipe = recipe
        self.coordinator = coordinator
        _target = State(initialValue: RecipeTranslationSheet.defaultTarget())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RecipeSpacing.medium) {
                    languageSection
                    if let errorMessage {
                        Section {
                            VStack(alignment: .leading, spacing: RecipeSpacing.small) {
                                Label(errorMessage, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.secondary)
                                Button("Try Again") {
                                    Task { await requestTranslation() }
                                }
                                .disabled(isTranslating)
                            }
                        }
                    }
                    if proposal != nil {
                        reviewSections
                    }
                }
                .recipePageContentInsets()
            }
            .background(RecipeTheme.canvas)
            .navigationTitle("Translate Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save as Variant") { save() }
                        .disabled(proposal == nil || isTranslating || isSaving)
                }
            }
        }
        .task(id: target) {
            await requestTranslation()
        }
    }

    private var languageSection: some View {
        Section("Language") {
            Picker("Language", selection: $target) {
                ForEach(RecipeTranslationTarget.allCases, id: \.self) { locale in
                    Text(locale.nativeName).tag(locale)
                }
            }
            .disabled(isTranslating)
        }
    }

    @ViewBuilder
    private var reviewSections: some View {
        if let proposal {
            if !proposal.title.isEmpty {
                reviewField("Title", original: recipe.title, text: $editedTitle)
            }
            if !proposal.summary.isEmpty {
                reviewField("Summary", original: recipe.summary, text: $editedSummary)
            }
            if !proposal.ingredientNames.isEmpty {
                ForEach(proposal.ingredientNames, id: \.id) { change in
                    reviewField("Ingredient", original: change.original, text: nameBinding(change))
                }
            }
            if !proposal.ingredientAmounts.isEmpty {
                ForEach(proposal.ingredientAmounts, id: \.id) { change in
                    reviewField("Amount", original: change.original, text: amountBinding(change))
                }
            }
            if !proposal.stepInstructions.isEmpty {
                ForEach(Array(proposal.stepInstructions.enumerated()), id: \.element.id) {
                    index, change in
                    reviewField(
                        "Step \(index + 1)", original: change.original,
                        text: instructionBinding(change)
                    )
                }
            }
            if !proposal.stepTitles.isEmpty {
                ForEach(proposal.stepTitles, id: \.id) { change in
                    reviewField(
                        "Step title", original: change.original,
                        text: stepTitleBinding(change)
                    )
                }
            }
        }
    }

    private func reviewField(
        _ label: String, original: String, text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: RecipeSpacing.small) {
            Text(label)
                .font(RecipeTheme.heading(.card))
            Text("Original")
                .font(RecipeTheme.text(13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(.secondary)
            Text(original)
                .strikethrough()
                .accessibilityIdentifier("translationOriginal.\(label)")
            Text("Translation")
                .font(RecipeTheme.text(13, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(.secondary)
            TextField("Translation", text: text, axis: .vertical)
                .lineLimit(2...8)
                .font(RecipeTheme.text(17, weight: .semibold, relativeTo: .body))
                .accessibilityIdentifier("translationProposed.\(label)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RecipeSpacing.medium)
        .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Editing bindings

    private func nameBinding(_ change: RecipeTranslationFieldChange) -> Binding<String> {
        Binding(
            get: { editedNames[change.id] ?? change.translated },
            set: { editedNames[change.id] = $0 }
        )
    }

    private func amountBinding(_ change: RecipeTranslationFieldChange) -> Binding<String> {
        Binding(
            get: { editedAmounts[change.id] ?? change.translated },
            set: { editedAmounts[change.id] = $0 }
        )
    }

    private func instructionBinding(_ change: RecipeTranslationFieldChange) -> Binding<String> {
        Binding(
            get: { editedInstructions[change.id] ?? change.translated },
            set: { editedInstructions[change.id] = $0 }
        )
    }

    private func stepTitleBinding(_ change: RecipeTranslationFieldChange) -> Binding<String> {
        Binding(
            get: { editedStepTitles[change.id] ?? change.translated },
            set: { editedStepTitles[change.id] = $0 }
        )
    }

    // MARK: - Actions

    @MainActor
    private func requestTranslation() async {
        isTranslating = true
        errorMessage = nil
        do {
            let result = try await coordinator.translate(recipe: recipe, target: target)
            proposal = result
            applyProposal(result)
        } catch {
            proposal = nil
            errorMessage = Self.message(for: error)
        }
        isTranslating = false
    }

    private func applyProposal(_ proposal: RecipeTranslationProposal) {
        editedTitle = proposal.title
        editedSummary = proposal.summary
        editedNames = Dictionary(
            uniqueKeysWithValues: proposal.ingredientNames.map { ($0.id, $0.translated) })
        editedAmounts = Dictionary(
            uniqueKeysWithValues: proposal.ingredientAmounts.map { ($0.id, $0.translated) })
        editedInstructions = Dictionary(
            uniqueKeysWithValues: proposal.stepInstructions.map { ($0.id, $0.translated) })
        editedStepTitles = Dictionary(
            uniqueKeysWithValues: proposal.stepTitles.map { ($0.id, $0.translated) })
    }

    private func editedProposal(from proposal: RecipeTranslationProposal) -> RecipeTranslationProposal {
        RecipeTranslationProposal(
            recipeID: proposal.recipeID,
            basedOnUpdate: proposal.basedOnUpdate,
            targetLocale: proposal.targetLocale,
            title: editedTitle,
            summary: editedSummary,
            ingredientNames: proposal.ingredientNames.map {
                RecipeTranslationFieldChange(
                    id: $0.id, original: $0.original,
                    translated: editedNames[$0.id] ?? $0.translated
                )
            },
            ingredientAmounts: proposal.ingredientAmounts.map {
                RecipeTranslationFieldChange(
                    id: $0.id, original: $0.original,
                    translated: editedAmounts[$0.id] ?? $0.translated
                )
            },
            stepInstructions: proposal.stepInstructions.map {
                RecipeTranslationFieldChange(
                    id: $0.id, original: $0.original,
                    translated: editedInstructions[$0.id] ?? $0.translated
                )
            },
            stepTitles: proposal.stepTitles.map {
                RecipeTranslationFieldChange(
                    id: $0.id, original: $0.original,
                    translated: editedStepTitles[$0.id] ?? $0.translated
                )
            },
            sourceURL: proposal.sourceURL,
            sourceName: proposal.sourceName
        )
    }

    @MainActor
    private func save() {
        guard let proposal, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            guard let current = store.recipe(id: recipe.id) else {
                errorMessage = RecipeLanguage.localized(
                    "This recipe is no longer in your library.")
                return
            }
            let edited = editedProposal(from: proposal)
            _ = try edited.preview(on: current)
            _ = try coordinator.save(proposal: edited, original: current, in: store)
            dismiss()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    // MARK: - Errors

    private static func message(for error: Error) -> String {
        if let proposal = error as? RecipeTranslationProposalError {
            switch proposal {
            case .staleRecipe:
                return RecipeLanguage.localized(
                    "This recipe changed. Get a new translation before saving.")
            case .numericValueChanged:
                return RecipeLanguage.localized(
                    "Numbers in a translation must stay unchanged.")
            default:
                return RecipeLanguage.localized(
                    "The translation could not be saved. Review it and try again.")
            }
        }
        if let client = error as? RecipeTranslationClientError {
            switch client {
            case .quotaExceeded:
                return RecipeLanguage.localized("This month's translation limit has been reached.")
            case .upgradeRequired:
                return RecipeLanguage.localized("Translations are available to Premium subscribers.")
            case .staleRevision:
                return RecipeLanguage.localized("This recipe changed. Reopen it and try again.")
            case .authenticationFailed, .ownerChanged:
                return RecipeLanguage.localized("Sign in to translate this recipe.")
            case .unavailable:
                return RecipeLanguage.localized("Translation is unavailable right now.")
            default:
                return RecipeLanguage.localized(
                    "The translation service returned an unexpected result. Try again.")
            }
        }
        return RecipeLanguage.localized("Translation failed. Try again.")
    }

    private static func defaultTarget() -> RecipeTranslationTarget {
        let raw = UserDefaults.standard.string(forKey: RecipeLanguage.preferenceKey)
        return RecipeTranslationTarget.defaultTarget(
            localeIdentifier: (raw?.isEmpty == false) ? raw : nil)
    }
}

private extension RecipeTranslationTarget {
    var nativeName: String {
        switch self {
        case .english:
            "English"
        case .simplifiedChinese:
            "简体中文"
        case .traditionalChinese:
            "繁體中文"
        case .japanese:
            "日本語"
        }
    }
}
