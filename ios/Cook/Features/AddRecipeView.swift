import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import CookCore

struct AddRecipeView: View {
    @Environment(CookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var sourceLink = ""
    @State private var pastedText = ""
    @State private var isWorking = false
    @State private var status = ""
    @State private var errorMessage: String?
    @State private var textErrorMessage: String?
    @State private var photo: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var showText = false
    @State private var showFile = false
    @State private var editor: Recipe?
    @State private var savedID: UUID?
    @State private var detailID: UUID?
    @State private var failedURL: URL?
    @State private var operation: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add a recipe").font(CookTheme.title(34))
                        Text("Good food, kept in one place.").foregroundStyle(.secondary)
                    }
                    linkCard
                    if isWorking {
                        HStack(spacing: 12) { ProgressView(); Text(status) }
                            .accessibilityElement(children: .combine)
                    }
                    if let savedID, let recipe = store.recipe(id: savedID) { savedCard(recipe) }
                    VStack(spacing: 12) {
                        importOption("Take a photo", subtitle: "Read a recipe from a book or a note.", icon: "camera") { requestCamera() }
                        importOption("Import from Photos", subtitle: "Choose a screenshot or recipe photo.", icon: "photo.on.rectangle") { showPhotos = true }
                        importOption("Paste recipe text", subtitle: "Keep ingredients and directions together.", icon: "doc.on.clipboard") { showText = true }
                        importOption("Import a document", subtitle: "Choose a text file or a PDF with selectable text.", icon: "doc") { showFile = true }
                        importOption("Create manually", subtitle: "Write down a recipe of your own.", icon: "square.and.pencil") {
                            let recipe = Recipe(title: "")
                            savedID = recipe.id
                            editor = recipe
                        }
                        .accessibilityIdentifier("createManually")
                    }
                    Text("Recipe websites with structured ingredients and steps can be imported directly. For private pages and social videos, keep the source and add text or photos.")
                        .font(CookTheme.text(13, weight: .regular, relativeTo: .footnote)).foregroundStyle(.secondary)
                }
                .padding(22)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(CookTheme.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { operation?.cancel(); dismiss() } }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $detailID) { RecipeDetailView(recipeID: $0) }
            .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images)
            .onChange(of: photo) { _, selection in
                guard let selection else { return }
                perform("Reading your photo…") {
                    guard let data = try await selection.loadTransferable(type: Data.self) else { throw RecipeImportError.unreadableImage }
                    try await importPhoto(data)
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraCaptureView { data in
                    showCamera = false
                    guard let data else { return }
                    perform("Reading your photo…") { try await importPhoto(data) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showText) { textSheet }
            .sheet(item: $editor, onDismiss: {
                if let savedID, store.recipe(id: savedID) == nil { self.savedID = nil }
            }) { RecipeEditorView(recipe: $0) }
            .fileImporter(isPresented: $showFile, allowedContentTypes: [.plainText, .pdf]) { result in
                switch result {
                case .success(let url):
                    perform("Reading your document…") {
                        let text = try RecipeImportService.text(fromFile: url)
                        try saveImported(RecipeDocumentParser.recipe(fromText: text))
                    }
                case .failure(let error):
                    failedURL = nil
                    savedID = nil
                    let cocoaError = error as NSError
                    if cocoaError.domain != NSCocoaErrorDomain || cocoaError.code != NSUserCancelledError {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .alert("Couldn't finish importing", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                if let failedURL {
                    Button("Save link for later") { saveLink(failedURL) }
                    Button("Try again") { importLink() }
                }
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .onDisappear { operation?.cancel() }
        }
    }

    private var linkCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("From a link", systemImage: "link").font(CookTheme.text(17, weight: .semibold, relativeTo: .headline))
            TextField("https://…", text: $sourceLink)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.URL).textContentType(.URL)
                .padding(14).background(CookTheme.canvas, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("importURL")
            Button { importLink() } label: { Label("Import recipe", systemImage: "arrow.down.doc") }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(sourceLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
        }
        .padding(20).background(CookTheme.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func importOption(_ title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            failedURL = nil
            savedID = nil
            action()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(CookTheme.accentForeground)
                    .frame(width: 46, height: 46).background(CookTheme.accent.opacity(0.09), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(CookTheme.text(17, weight: .semibold, relativeTo: .headline)).foregroundStyle(.primary)
                    Text(subtitle).font(CookTheme.text(15, weight: .regular, relativeTo: .subheadline)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background(CookTheme.card, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain).disabled(isWorking)
    }

    private func savedCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(recipe.needsReview ? "Source saved — add the missing details" : "Saved to your recipes", systemImage: "checkmark.circle.fill")
                .foregroundStyle(CookTheme.accentForeground).font(CookTheme.text(17, weight: .semibold, relativeTo: .headline))
            Text(recipe.title)
            Button(recipe.needsReview ? "Complete recipe" : "Open recipe") {
                if recipe.needsReview { editor = recipe } else { detailID = recipe.id }
            }.buttonStyle(.bordered)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(CookTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private var textSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $pastedText).frame(minHeight: 260)
                        .accessibilityIdentifier("recipeText")
                } header: {
                    Text("Recipe text")
                } footer: {
                    Text("Include Ingredients and Instructions headings when available. The original text is always kept.")
                }
            }
            .navigationTitle("Paste recipe text").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showText = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        let text = pastedText
                        guard text.count <= RecipeDocumentParser.maximumTextCharacters else {
                            textErrorMessage = RecipeImportError.textTooLong.localizedDescription
                            return
                        }
                        showText = false
                        perform("Saving your recipe…") {
                            try saveImported(RecipeDocumentParser.recipe(fromText: text))
                        }
                    }.disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Recipe text is too long", isPresented: Binding(
                get: { textErrorMessage != nil }, set: { if !$0 { textErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { textErrorMessage = nil }
            } message: { Text(textErrorMessage ?? "") }
        }
    }

    private func importLink() {
        guard !isWorking else { return }
        failedURL = nil
        savedID = nil
        guard let url = RecipeDocumentParser.validatedSourceURL(sourceLink) else { errorMessage = RecipeImportError.invalidLink.localizedDescription; return }
        if let existing = store.recipes.first(where: {
            guard let value = $0.sourceURL, let other = URL(string: value) else { return false }
            return RecipeDocumentParser.sourceKey(other) == RecipeDocumentParser.sourceKey(url)
        }) { savedID = existing.id; return }
        perform("Reading the recipe page…") {
            do { try saveImported(try await RecipeImportService.importWebpage(url)) }
            catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                failedURL = url
                throw error
            }
        }
    }

    private func saveLink(_ url: URL) {
        do {
            let recipe = Recipe(title: "Recipe from \(url.host() ?? "a saved link")", servings: nil, sourceURL: url.absoluteString, sourceName: url.host())
            try saveImported(recipe)
            failedURL = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func saveImported(_ recipe: Recipe) throws {
        try Task.checkCancellation()
        try store.upsert(recipe)
        savedID = recipe.id
    }

    private func importPhoto(_ data: Data) async throws {
        let normalized = try RecipeImportService.normalizedPhoto(data)
        let text: String
        do { text = try await RecipeImportService.recognizeText(in: normalized) }
        catch is CancellationError { throw CancellationError() }
        catch {
            // The photo is still a usable source even when OCR finds no text.
            var recipe = Recipe(title: "Recipe from a photo", servings: nil, sourceName: "Photo import")
            recipe.coverData = normalized
            try saveImported(recipe)
            status = "Photo saved. Add the ingredients and steps when you're ready."
            return
        }
        var recipe = RecipeDocumentParser.recipe(fromText: text)
        recipe.coverData = normalized
        recipe.sourceName = "Photo import"
        try saveImported(recipe)
    }

    private func perform(_ message: String, action: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        status = message
        errorMessage = nil
        savedID = nil
        failedURL = nil
        operation = Task { @MainActor in
            defer { isWorking = false }
            do {
                try Task.checkCancellation()
                try await action()
            }
            catch is CancellationError { }
            catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }

    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "A camera isn't available here. Choose Import from Photos instead."; return
        }
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            if allowed { showCamera = true }
            else { errorMessage = "Camera access is off. Enable it for Cook in iPhone Settings, or use Import from Photos." }
        }
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    var completion: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (Data?) -> Void
        init(completion: @escaping (Data?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.8))
        }
    }
}
