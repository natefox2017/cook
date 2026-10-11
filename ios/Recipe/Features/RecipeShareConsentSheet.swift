// Developer: gengyun
// Purpose: Presents explicit public-sharing consent for the current App owner and an approved sharing endpoint.

import RecipeCore
import SwiftUI
import UIKit

struct RecipeShareConsentSheet: View {
    let state: RecipeShareConsentState
    @State private var confirmsRevoke = false
    @State private var presentsShare = false
    @State private var posterPublication: RecipeShareConsentState.PosterPublication?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    scopePicker
                    if state.scope == .fullInstructions {
                        Toggle(
                            text("I have permission to share these instructions."),
                            isOn: Binding(
                                get: {
                                    state.rightsConfirmed
                                },
                                set: {
                                    state.select(scope: state.scope, rightsConfirmed: $0)
                                }
                            ))
                    }
                }
                .disabled(state.isBusy)

                if let preview = state.preview {
                    Section {
                        Text(preview.title)
                            .font(RecipeTheme.heading(.section))
                        if !preview.summary.isEmpty {
                            Text(preview.summary)
                        }
                        if let source = preview.sourceURL {
                            Text(source).foregroundStyle(.secondary)
                        }
                        if let servings = preview.servings {
                            LabeledContent(text("Servings"), value: String(servings))
                        }
                        if let minutes = preview.prepMinutes {
                            LabeledContent(text("Prep time"), value: String(minutes))
                        }
                        if let minutes = preview.cookMinutes {
                            LabeledContent(text("Cook time"), value: String(minutes))
                        }
                        ForEach(ingredientRows(preview)) { row in
                            let ingredient = row.ingredient
                            Text("\(ingredient.name) \(ingredient.amountText)")
                        }
                        ForEach(stepRows(preview)) { row in
                            let step = row.step
                            VStack(alignment: .leading) {
                                if !step.title.isEmpty {
                                    Text(step.title).fontWeight(.semibold)
                                }
                                Text(step.instruction)
                            }
                        }
                    }
                }

                Section {
                    if !state.isAvailable {
                        Text(text("Sharing is unavailable. Try again later."))
                            .foregroundStyle(.secondary)
                    }
                    if let errorKey = state.errorKey {
                        Text(text(errorKey)).foregroundStyle(.secondary)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    if state.isBusy {
                        ProgressView()
                    } else if !state.hasLoadedOwnerRecords && state.isAvailable {
                        Button(text("Reload public copy")) {
                            Task {
                                await state.loadOwnerRecords()
                            }
                        }
                    } else if state.needsReload {
                        Button(text("Reload public copy")) {
                            Task {
                                await state.reload()
                            }
                        }
                    } else if state.canRetry {
                        Button(text("Retry")) {
                            Task {
                                await state.retry()
                            }
                        }
                    } else {
                        Button(text(state.share == nil ? "Publish link" : "Update public copy")) {
                            Task {
                                await state.confirm()
                            }
                        }
                        .disabled(
                            state.preview == nil || !state.isAvailable
                                || !state.hasLoadedOwnerRecords)
                    }
                    if state.publicURL != nil {
                        Button(text("Copy Link")) {
                            copyLink()
                        }
                        Button(text("Share")) {
                            guard state.publicURL != nil else {
                                return
                            }
                            presentsShare = true
                        }
                    }
                    if state.confirmedSnapshot != nil {
                        Button(text("Poster Preview")) {
                            posterPublication = state.posterPublication
                        }
                        .accessibilityIdentifier("recipeShare.poster")
                    }
                    if state.share != nil {
                        if !state.needsReload {
                            Button(text("Reload public copy")) {
                                Task {
                                    await state.reload()
                                }
                            }
                            .disabled(state.isBusy)
                        }
                        Button(text("Revoke link"), role: .destructive) {
                            confirmsRevoke = true
                        }
                        .disabled(state.isBusy)
                    }
                }
            }
            .navigationTitle(text("Share"))
            .navigationBarTitleDisplayMode(.inline)
            .tint(RecipeTheme.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text("Cancel")) {
                        state.cancel()
                        dismiss()
                    }
                }
            }
            .confirmationDialog(text("Revoke this public link?"), isPresented: $confirmsRevoke) {
                Button(text("Revoke link"), role: .destructive) {
                    Task {
                        await state.revoke()
                    }
                }
            } message: {
                Text(text("This link will stop working."))
            }
        }
        .sheet(isPresented: $presentsShare) {
            ConsentURLActivity(state: state)
        }
        .sheet(item: $posterPublication) { publication in
            RecipeSharePosterPreview(
                snapshot: publication.snapshot,
                publicURL: publication.publicURL,
                isStillValid: {
                    await state.isPosterPublicationValid(publication)
                }
            )
        }
        .environment(\.locale, RecipeLanguage.active)
        .task {
            await state.loadOwnerRecords()
        }
        .onDisappear {
            state.cancel()
        }
        .onChange(of: state.accountChanged) { _, changed in
            if changed {
                state.cancel()
                presentsShare = false
                posterPublication = nil
                dismiss()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                state.refreshPreview()
            }
        }
    }

    @ViewBuilder
    private var scopePicker: some View {
        // Large accessibility text needs full labels for informed sharing consent.
        if dynamicTypeSize.isAccessibilitySize {
            scopeSelection.pickerStyle(.inline)
        } else {
            scopeSelection
        }
    }

    private var scopeSelection: some View {
        Picker(
            text("Share"),
            selection: Binding(
                get: {
                    state.scope
                },
                set: {
                    state.select(scope: $0, rightsConfirmed: false)
                }
            )
        ) {
            Text(text("Summary and source")).tag(RecipeShareScope.summaryAndSource)
            Text(text("Full instructions")).tag(RecipeShareScope.fullInstructions)
        }
    }

    /// Revalidates authorization at disclosure time; an unavailable link leaves the clipboard alone.
    @discardableResult
    func copyLink(to pasteboard: UIPasteboard = .general) -> Bool {
        guard let currentURL = state.publicURL else {
            return false
        }
        pasteboard.url = currentURL
        return true
    }

    private struct IngredientRow: Identifiable {
        let id: String
        let ingredient: PublicRecipeIngredient
    }

    private struct StepRow: Identifiable {
        let id: String
        let step: PublicRecipeStep
    }

    // Paths identify positions in the immutable approved document, never private model IDs.
    private func ingredientRows(_ snapshot: PublicRecipeSnapshot) -> [IngredientRow] {
        snapshot.ingredients.enumerated().map { index, ingredient in
            IngredientRow(id: "snapshot.ingredients[\(index)]", ingredient: ingredient)
        }
    }

    private func stepRows(_ snapshot: PublicRecipeSnapshot) -> [StepRow] {
        snapshot.steps.enumerated().map { index, step in
            StepRow(id: "snapshot.steps[\(index)]", step: step)
        }
    }

    private func text(_ key: String) -> String {
        String(
            localized: LocalizedStringResource(
                String.LocalizationValue(key), locale: RecipeLanguage.active
            ))
    }
}

/// Rechecks authorization on tap and controller creation; only the validated URL is disclosed.
@MainActor
struct ConsentURLActivity: UIViewControllerRepresentable {
    let state: RecipeShareConsentState

    func makeUIViewController(context: Context) -> UIActivityViewController {
        makeController()
    }

    func makeController() -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems(), applicationActivities: nil)
    }

    /// Reads the latest owner/source when constructing the system controller, never a cached URL.
    func activityItems() -> [Any] {
        state.publicURL.map {
            [$0]
        } ?? []
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Items already handed to the system cannot be recalled by local state updates.
    }
}
