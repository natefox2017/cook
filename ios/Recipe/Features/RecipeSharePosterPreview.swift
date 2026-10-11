// Developer: gengyun
// Purpose: Preview and export only a caller-authorized published poster snapshot and its matching public link.

import Observation
import RecipeCore
import SwiftUI
import UIKit

/// The caller supplies a snapshot and URL from the same confirmed publication version.
/// Its validator must remain bound to that captured owner/share/version, including account changes and revocation.
@MainActor
struct RecipeSharePosterPreview: View {
    let snapshot: PublicRecipeSnapshot
    let publicURL: URL
    let isStillValid: @MainActor () async -> Bool

    var body: some View {
        RecipePosterPreviewContent(
            snapshot: snapshot,
            publicURL: publicURL,
            isStillValid: isStillValid
        )
        // A replacement publication creates new presentation-owned state, never an old cached image.
        .id(RecipePosterPreviewIdentity(snapshot: snapshot, publicURL: publicURL))
        .environment(\.locale, RecipeLanguage.active)
    }
}

private struct RecipePosterPreviewIdentity: Hashable {
    let snapshotData: Data
    let publicURL: URL

    init(snapshot: PublicRecipeSnapshot, publicURL: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        snapshotData = (try? encoder.encode(snapshot)) ?? Data()
        self.publicURL = publicURL
    }
}

@MainActor
@Observable
final class RecipePosterPreviewState {
    struct Activity: Identifiable {
        let id = UUID()
        let image: UIImage
        let url: URL

        var items: [Any] {
            [image, url]
        }
    }

    typealias Renderer = @MainActor (PublicRecipeSnapshot, URL, RecipePosterFormat) async throws ->
        UIImage

    private(set) var image: UIImage?
    private(set) var isBusy = false
    private(set) var isUnavailable = false
    private(set) var hasRenderError = false
    var activity: Activity?

    private let snapshot: PublicRecipeSnapshot
    private let publicURL: URL
    private let isStillValid: @MainActor () async -> Bool
    private let renderer: Renderer
    private let copyURL: @MainActor (URL) -> Void
    private var generation = 0
    private var isClosed = false

    init(
        snapshot: PublicRecipeSnapshot,
        publicURL: URL,
        isStillValid: @escaping @MainActor () async -> Bool,
        renderer: @escaping Renderer = { snapshot, url, format in
            try RecipeSharePosterRenderer.render(snapshot: snapshot, url: url, format: format)
        },
        copyURL: @escaping @MainActor (URL) -> Void = { url in
            UIPasteboard.general.url = url
        }
    ) {
        self.snapshot = snapshot
        self.publicURL = publicURL
        self.isStillValid = isStillValid
        self.renderer = renderer
        self.copyURL = copyURL
    }

    func render(format: RecipePosterFormat) async {
        guard !isClosed, !isUnavailable else {
            return
        }
        generation += 1
        let ticket = generation
        image = nil
        activity = nil
        hasRenderError = false
        isBusy = true
        defer {
            if generation == ticket {
                isBusy = false
            }
        }
        guard await validate(ticket: ticket) else {
            return
        }
        do {
            let rendered = try await renderer(snapshot, publicURL, format)
            guard await validate(ticket: ticket) else {
                return
            }
            image = rendered
        } catch {
            guard isCurrent(ticket) else {
                return
            }
            hasRenderError = true
        }
    }

    func share() async {
        guard !isBusy, !isClosed, !isUnavailable, let image, activity == nil else {
            return
        }
        generation += 1
        let ticket = generation
        isBusy = true
        defer {
            if generation == ticket {
                isBusy = false
            }
        }
        guard await validate(ticket: ticket) else {
            return
        }
        activity = Activity(image: image, url: publicURL)
    }

    func copyLink() async {
        guard !isBusy, !isClosed, !isUnavailable else {
            return
        }
        generation += 1
        let ticket = generation
        isBusy = true
        defer {
            if generation == ticket {
                isBusy = false
            }
        }
        guard await validate(ticket: ticket) else {
            return
        }
        copyURL(publicURL)
    }

    func close() {
        isClosed = true
        generation += 1
        image = nil
        activity = nil
        isBusy = false
    }

    private func isCurrent(_ ticket: Int) -> Bool {
        !isClosed && generation == ticket && !Task.isCancelled
    }

    private func validate(ticket: Int) async -> Bool {
        guard isCurrent(ticket) else {
            return false
        }
        guard RecipePublicShareURL.isValid(publicURL) else {
            invalidate()
            return false
        }
        let valid = await isStillValid()
        guard isCurrent(ticket) else {
            return false
        }
        guard valid else {
            invalidate()
            return false
        }
        return true
    }

    private func invalidate() {
        isUnavailable = true
        image = nil
        activity = nil
        hasRenderError = false
        isBusy = false
    }
}

@MainActor
private struct RecipePosterPreviewContent: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLongImage = false
    @State private var state: RecipePosterPreviewState
    @State private var outputTask: Task<Void, Never>?
    @State private var retry = 0

    init(
        snapshot: PublicRecipeSnapshot,
        publicURL: URL,
        isStillValid: @escaping @MainActor () async -> Bool
    ) {
        // This presentation owns one immutable publication; the outer identity resets it on replacement.
        _state = State(
            initialValue: RecipePosterPreviewState(
                snapshot: snapshot, publicURL: publicURL, isStillValid: isStillValid
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: RecipeSpacing.medium) {
                    Picker(selection: $isLongImage) {
                        Text("Story").tag(false)
                        Text("Long Image").tag(true)
                    } label: {
                        Text("Poster Preview")
                    }
                    .pickerStyle(.segmented)
                    .disabled(state.isUnavailable)
                    .accessibilityIdentifier("posterPreview.format")

                    if state.isUnavailable {
                        Text("Recipe unavailable")
                            .font(RecipeTheme.heading(.card))
                            .accessibilityIdentifier("posterPreview.unavailable")
                    } else if let image = state.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .accessibilityLabel(Text("Poster Preview"))
                            .accessibilityIdentifier("posterPreview.image")
                    } else if state.hasRenderError {
                        Text("Please try again.")
                        Button("Try Again") {
                            retry += 1
                        }
                    } else {
                        ProgressView()
                    }

                    Button {
                        startOutput {
                            await state.share()
                        }
                    } label: {
                        Label("Share Image", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.image == nil || state.isBusy || state.isUnavailable)
                    .accessibilityIdentifier("posterPreview.share")

                    Button {
                        startOutput {
                            await state.copyLink()
                        }
                    } label: {
                        Label("Copy Link", systemImage: "link")
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.isBusy || state.isUnavailable)
                    .accessibilityIdentifier("posterPreview.copy")
                }
                .font(RecipeTheme.body())
                .recipePageContentInsets()
            }
            .background(RecipeTheme.canvas)
            .tint(RecipeTheme.accent)
            .navigationTitle(Text("Poster Preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancel()
                        dismiss()
                    }
                }
            }
            .task(id: RenderIdentity(isLongImage: isLongImage, retry: retry)) {
                await state.render(format: isLongImage ? .long : .story)
            }
            .sheet(item: $state.activity) { activity in
                RecipePosterActivity(items: activity.items)
            }
            .onDisappear {
                cancel()
            }
        }
    }

    private struct RenderIdentity: Hashable {
        let isLongImage: Bool
        let retry: Int
    }

    private func startOutput(_ operation: @escaping @MainActor () async -> Void) {
        guard outputTask == nil else {
            return
        }
        outputTask = Task {
            await operation()
            outputTask = nil
        }
    }

    private func cancel() {
        outputTask?.cancel()
        outputTask = nil
        state.close()
    }
}

@MainActor
private struct RecipePosterActivity: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(
                x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1
            )
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
    }
}
