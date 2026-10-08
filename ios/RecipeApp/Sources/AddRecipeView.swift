// Developer: gengyun
// Purpose: Provides the legacy RecipeApp recipe creation and import screen.

import PhotosUI
import SwiftUI

struct AddRecipeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var link = ""
    @State private var createsManually = false
    @State private var importedRecipe: Recipe?
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 18) {
            Text("Add a Recipe")
                .font(RecipeTheme.title())
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Paste a recipe link", text: $link)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .padding()
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: 16)
                )

            Button("Import from Link") {
                importedRecipe = store.importURL(link)
            }
            .buttonStyle(PrimaryButtonStyle())

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Import from Photos", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                createsManually = true
            } label: {
                Label("Create Manually", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
        .background(RecipeTheme.paper)
        .navigationTitle("Add")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Close") { dismiss() }
        }
        .alert(
            "Couldn’t import",
            isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            )
        ) {
            Button("OK") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
        .sheet(item: $importedRecipe) { recipe in
            NavigationStack {
                RecipeEditorView(recipe: recipe)
            }
        }
        .sheet(isPresented: $createsManually) {
            NavigationStack {
                RecipeEditorView(
                    recipe: Recipe(
                        title: "",
                        sourceURL: nil,
                        servings: 2,
                        minutes: 0,
                        isFavorite: false,
                        needsReview: true,
                        ingredients: [],
                        steps: []
                    )
                )
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            if newValue != nil {
                createsManually = true
            }
        }
    }
}
