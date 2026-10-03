import SwiftUI
import PhotosUI
import UIKit

struct RecipeEditorView: View {
    @Environment(CookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var recipe: RecipeRecord
    @State private var sourceLink = ""
    @State private var servingsKnown = true
    @State private var photo: PhotosPickerItem?
    @State private var failure: String?

    var body: some View {
        Form {
            Section {
                TextField("Recipe name", text: $recipe.title)
                if let data = recipe.coverData {
                    RecipeCover(data: data, height: 180).clipShape(RoundedRectangle(cornerRadius: 16))
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Choose a food photo", systemImage: "photo.badge.plus")
                }
            }
            Section("Original source") {
                TextField("Source link (optional)", text: $sourceLink)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(recipe.sourceURL != nil)
                TextField("Platform or website", text: $recipe.sourcePlatform)
                TextField("Author (if known)", text: $recipe.sourceAuthor)
                TextField("Original title (if known)", text: $recipe.sourceTitle)
            }
            Section("Servings") {
                Toggle("Original serving size is known", isOn: $servingsKnown)
                if servingsKnown {
                    Stepper("\(recipe.servings ?? 2) servings", value: Binding(
                        get: { recipe.servings ?? 2 }, set: { recipe.servings = $0 }), in: 1...24)
                }
            }
            Section("Ingredients") {
                ForEach($recipe.ingredients) { $ingredient in
                    VStack(alignment: .leading) {
                        TextField("Ingredient", text: $ingredient.name)
                        HStack {
                            TextField("Amount or “to taste”", text: $ingredient.amount)
                            TextField("Unit", text: $ingredient.unit)
                        }.font(.subheadline)
                    }
                }
                .onDelete { recipe.ingredients.remove(atOffsets: $0) }
                Button("Add ingredient", systemImage: "plus") {
                    recipe.ingredients.append(IngredientRecord(name: ""))
                }
                Text("Keep phrases like “a pinch” or “to taste”. Cook won't invent exact amounts.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Steps") {
                ForEach($recipe.steps) { $step in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("What to do", text: $step.instruction, axis: .vertical)
                        Stepper("Timer: \((step.durationSeconds ?? 0) / 60) min", value: Binding(
                            get: { (step.durationSeconds ?? 0) / 60 },
                            set: { step.durationSeconds = $0 == 0 ? nil : $0 * 60 }), in: 0...180)
                        Text("Only add a timer when the source gives a duration.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onDelete { recipe.steps.remove(atOffsets: $0) }
                Button("Add step", systemImage: "plus") { recipe.steps.append(StepRecord(instruction: "")) }
            }
            if let failure { Section { InlineFailure(message: failure) } }
        }
        .navigationTitle(recipe.title.isEmpty ? String(localized: "New Recipe") : String(localized: "Edit Recipe"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            sourceLink = recipe.sourceURL?.absoluteString ?? ""
            servingsKnown = recipe.servings != nil
        }
        .onChange(of: photo) { _, selected in
            guard let selected else { return }
            Task {
                do {
                    guard let data = try await selected.loadTransferable(type: Data.self),
                          let image = UIImage(data: data),
                          let compressed = image.jpegData(compressionQuality: 0.75) else { throw LocalStoreError.emptyInput }
                    guard compressed.count <= 5 * 1024 * 1024 else { throw LocalStoreError.oversizedCover }
                    recipe.coverData = compressed
                } catch { failure = error.localizedDescription }
            }
        }
    }

    private func save() {
        failure = nil
        let source = sourceLink.trimmingCharacters(in: .whitespacesAndNewlines)
        if !source.isEmpty {
            guard let url = URL(string: source), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil, url.user == nil, url.password == nil else {
                failure = LocalStoreError.invalidURL.localizedDescription
                return
            }
            recipe.sourceURL = url
        } else { recipe.sourceURL = nil }
        recipe.title = recipe.title.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.servings = servingsKnown ? recipe.servings ?? 2 : nil
        recipe.ingredients.removeAll { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        recipe.reviewFields.removeAll { field in !recipe.ingredients.contains { $0.id == field.ingredientID } }
        recipe.steps.removeAll { $0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        do { try store.save(recipe); dismiss() } catch { failure = error.localizedDescription }
    }
}
