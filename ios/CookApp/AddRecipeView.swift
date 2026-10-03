import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AddRecipeView: View {
    @Environment(CookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var text = ""
    @State private var showText = false
    @State private var showManual = false
    @State private var showDocument = false
    @State private var photo: PhotosPickerItem?
    @State private var saving = false
    @State private var message: String?
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Add a Recipe").font(CookTheme.heading())
                Text("Keep recipes from anywhere.").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Paste a recipe link", text: $link)
                        .textContentType(.URL).keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Button("Save link", systemImage: "link") {
                        capture { _ = try store.captureURL(link) }
                    }.cookAction().disabled(saving || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Divider()
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Import a screenshot or photo", systemImage: "photo")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.cookAction(prominent: false).disabled(saving)
                Button("Import a PDF", systemImage: "doc") { showDocument = true }
                    .cookAction(prominent: false).disabled(saving)
                DisclosureGroup("Other ways") {
                    VStack(alignment: .leading, spacing: 16) {
                        Button("Paste recipe text", systemImage: "text.alignleft") { showText.toggle() }
                        if showText {
                            TextEditor(text: $text).frame(minHeight: 160)
                                .accessibilityLabel("Recipe text")
                            Button("Save text") { capture { _ = try store.captureText(text) } }
                                .cookAction().disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Button("Create manually", systemImage: "square.and.pencil") { showManual = true }
                    }.padding(.top, 12)
                }
                Text("Links and files are saved on this device. Automatic recipe processing will be available after the import service is connected.")
                    .font(.footnote).foregroundStyle(.secondary)
                if saving { ProgressView("Saving…") }
                if let message { Label(message, systemImage: "checkmark.circle").foregroundStyle(CookTheme.green) }
                if let failure { InlineFailure(message: failure) }
            }.padding(24)
        }
        .background(CookTheme.paper)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $showManual) {
            NavigationStack { RecipeEditorView(recipe: RecipeRecord(title: "")) }
        }
        .onChange(of: photo) { _, selected in
            guard let selected else { return }
            Task {
                saving = true
                failure = nil
                message = nil
                defer { saving = false; photo = nil }
                do {
                    guard let data = try await selected.loadTransferable(type: Data.self) else { throw LocalStoreError.emptyInput }
                    _ = try store.captureAttachment(data, kind: .image, extension: "image")
                    message = String(localized: "Saved on this device.")
                } catch { failure = error.localizedDescription }
            }
        }
        .fileImporter(isPresented: $showDocument, allowedContentTypes: [.pdf]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 20 * 1024 * 1024 else { throw LocalStoreError.oversizedAttachment }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                capture { _ = try store.captureAttachment(data, kind: .file, extension: "pdf") }
            } catch { failure = error.localizedDescription }
        }
    }

    private func capture(_ operation: () throws -> Void) {
        failure = nil
        message = nil
        do {
            try operation()
            message = String(localized: "Saved on this device.")
            link = ""
            text = ""
        } catch { failure = error.localizedDescription }
    }
}

struct SavedSourceView: View {
    @Environment(\.dismiss) private var dismiss
    var capture: LocalCapture
    @State private var editing = false

    private var draft: RecipeRecord {
        RecipeRecord(title: "", sourceURL: capture.kind == .url ? URL(string: capture.value) : nil,
                     sourcePlatform: capture.kind == .url ? URL(string: capture.value)?.host ?? "" : "")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your source is saved").font(CookTheme.heading())
                Text("Cook hasn't parsed this source yet. Your original content is kept on this device.")
                    .foregroundStyle(.secondary)
                if capture.kind == .url, let url = URL(string: capture.value) {
                    Link(destination: url) { Label("Open original source", systemImage: "arrow.up.right.square") }
                    Text(capture.value).font(.footnote).textSelection(.enabled)
                } else {
                    Text(capture.value).textSelection(.enabled)
                }
                Button("Create a recipe from this source") { editing = true }.cookAction()
                Text("You can add the ingredients and steps yourself while automatic processing is unavailable.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }
        .background(CookTheme.paper)
        .sheet(isPresented: $editing) { NavigationStack { RecipeEditorView(recipe: draft) } }
        .navigationTitle("Saved source").navigationBarTitleDisplayMode(.inline)
    }
}
