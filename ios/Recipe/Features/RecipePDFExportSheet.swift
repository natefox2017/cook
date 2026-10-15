// Developer: gengyun
// Purpose: Presents private recipe selection, ordering, A4 preview, and system PDF export.

import PDFKit
import RecipeCore
import SwiftUI
import UniformTypeIdentifiers

struct RecipePDFExportSheet: View {
    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var recipes: [Recipe] = []
    @State private var selectedIDs: [UUID] = []
    @State private var path: [RecipePDFExportRoute] = []
    @State private var pdfData: Data?
    @State private var isRendering = false
    @State private var loadError: String?
    @State private var renderError: String?
    @State private var exportsPDF = false
    @State private var exportDocument = RecipePDFExportDocument(data: Data())
    @State private var statusMessage: String?

    private static let maxSelection = 50

    var body: some View {
        NavigationStack(path: $path) {
            selectionList
                .navigationDestination(for: RecipePDFExportRoute.self) { route in
                    switch route {
                    case .arrange: arrangeList
                    case .preview: previewScreen
                    }
                }
        }
        .tint(RecipeTheme.accent)
        .task { loadRecipes() }
        .fileExporter(
            isPresented: $exportsPDF,
            document: exportDocument,
            contentType: .pdf,
            defaultFilename: exportFilename
        ) { result in
            if let feedback = RecipeExportFormat.feedback(for: result) {
                statusMessage = feedback
            }
        }
        .alert(
            "Export",
            isPresented: Binding(
                get: { statusMessage != nil },
                set: { isPresented in
                    if !isPresented { statusMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) { statusMessage = nil }
        } message: {
            Text(statusMessage ?? "Please try again.")
        }
    }

    // MARK: - Selection

    private var selectionList: some View {
        List {
            if recipes.isEmpty {
                Text("No saved recipes.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recipes) { recipe in
                    selectionRow(recipe)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .navigationTitle("Select Recipes")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") { path.append(.arrange) }
                    .disabled(selectedIDs.isEmpty)
                    .fontWeight(.semibold)
            }
        }
        .alert(
            "Couldn’t load recipes",
            isPresented: Binding(
                get: { loadError != nil },
                set: { isPresented in
                    if !isPresented { loadError = nil }
                }
            )
        ) {
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            Text(loadError ?? "Please try again.")
        }
    }

    private func selectionRow(_ recipe: Recipe) -> some View {
        let isSelected = selectedIDs.contains(recipe.id)
        return Button {
            toggle(recipe)
        } label: {
            HStack(spacing: RecipeSpacing.small) {
                Text(recipe.title)
                    .font(RecipeTheme.text(17, weight: .regular, relativeTo: .body))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? RecipeTheme.accent : Color.secondary)
                    .accessibilityLabel(isSelected ? "Selected" : "Not selected")
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isSelected && selectedIDs.count >= Self.maxSelection)
    }

    private func toggle(_ recipe: Recipe) {
        if let index = selectedIDs.firstIndex(of: recipe.id) {
            selectedIDs.remove(at: index)
        } else {
            guard selectedIDs.count < Self.maxSelection else { return }
            selectedIDs.append(recipe.id)
        }
    }

    // MARK: - Arrange

    private var arrangeList: some View {
        List {
            ForEach(orderedRecipes) { recipe in
                Text(recipe.title)
                    .font(RecipeTheme.text(17, weight: .regular, relativeTo: .body))
                    .frame(minHeight: 44)
            }
            .onMove { source, destination in
                selectedIDs.move(fromOffsets: source, toOffset: destination)
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .navigationTitle("Arrange Recipes")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
        .overlay {
            if isRendering {
                ProgressView("Preparing PDF…")
                    .padding(RecipeSpacing.medium)
                    .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Preview") { renderPDF() }
                    .disabled(isRendering)
                    .fontWeight(.semibold)
            }
        }
        .alert(
            "Export failed",
            isPresented: Binding(
                get: { renderError != nil },
                set: { isPresented in
                    if !isPresented { renderError = nil }
                }
            )
        ) {
            Button("Retry") { renderPDF() }
            Button("Cancel", role: .cancel) { renderError = nil }
        } message: {
            Text(renderError ?? "Please try again.")
        }
    }

    // MARK: - Preview

    private var previewScreen: some View {
        Group {
            if let pdfData {
                RecipePDFPreviewView(data: pdfData)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Export") {
                    guard let pdfData else { return }
                    exportDocument = RecipePDFExportDocument(data: pdfData)
                    exportsPDF = true
                }
                .disabled(pdfData == nil)
                .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Helpers

    private var orderedRecipes: [Recipe] {
        let byID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        return selectedIDs.compactMap { byID[$0] }
    }

    private var exportFilename: String {
        let date = Date().formatted(
            .iso8601.year().month().day().dateSeparator(.dash)
        )
        return "RecipePals-Recipes-\(date)"
    }

    private func loadRecipes() {
        do {
            let snapshot = try store.exportCloudSnapshot()
            recipes = snapshot.recipes.sorted {
                let comparison = $0.title.localizedStandardCompare($1.title)
                return comparison == .orderedSame
                    ? $0.id.uuidString < $1.id.uuidString
                    : comparison == .orderedAscending
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Renders the current selection off the main actor. On failure the ordered
    /// selection is preserved so the user can retry without re-selecting.
    private func renderPDF() {
        Task {
            isRendering = true
            renderError = nil
            do {
                let ordered = orderedRecipes
                let data = try await Task.detached(priority: .userInitiated) {
                    try RecipePDFExportService.render(recipes: ordered)
                }.value
                pdfData = data
                path.append(.preview)
            } catch {
                renderError = RecipeLanguage.localized(
                    "Export failed: %@", error.localizedDescription
                )
            }
            isRendering = false
        }
    }
}

private enum RecipePDFExportRoute: Hashable {
    case arrange
    case preview
}

private struct RecipePDFPreviewView: UIViewRepresentable {
    let data: Data

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(data: data)
        context.coordinator.data = data
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        guard data != context.coordinator.data else { return }
        context.coordinator.data = data
        uiView.document = PDFDocument(data: data)
    }

    final class Coordinator {
        var data: Data?
    }
}
