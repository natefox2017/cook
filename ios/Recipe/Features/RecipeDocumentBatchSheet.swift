// Developer: gengyun
// Purpose: Batch document preview sheet for candidate selection, page progress and resume.

import RecipeCore
import SwiftUI

/// Independent preview sheet for the batch document scanner. It shows bounded
/// candidates, page-level progress and the "more pages pending" signal, and
/// resolves into a save-selected or cancel decision without charging anything
/// until the caller finalizes each selected candidate.
struct RecipeDocumentBatchSheet: View {
    let outcome: RecipeDocumentBatchOutcome
    let progress: RecipeDocumentBatchProgress
    let onSave: (Set<String>) -> Void
    let onCancel: () -> Void
    let onContinue: () -> Void

    @State private var selectedCandidateIDs = Set<String>()

    private var completedPages: Int {
        progress.pages.filter { $0.status == .completed }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        ProgressView(
                            value: Double(completedPages),
                            total: Double(max(progress.totalPages, 1))
                        )
                        Text("\(completedPages) of \(progress.totalPages) pages")
                            .font(RecipeTheme.text(13, relativeTo: .footnote))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Scan progress")
                }

                if outcome.hasMore {
                    Section {
                        Label(
                            "Remaining pages are not yet processed.",
                            systemImage: "info.circle"
                        )
                        .font(RecipeTheme.text(13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach(outcome.candidates, id: \.candidateID) { candidate in
                        Button {
                            if !selectedCandidateIDs.insert(candidate.candidateID).inserted {
                                selectedCandidateIDs.remove(candidate.candidateID)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(
                                    systemName: selectedCandidateIDs.contains(
                                        candidate.candidateID
                                    )
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
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "documentBatchCandidate.\(candidate.candidateID)")
                    }
                } header: {
                    Text("Choose recipes to save")
                } footer: {
                    Text("Only selected dishes are added to your private recipes.")
                }
            }
            .navigationTitle("Scan documents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save selected") {
                        onSave(selectedCandidateIDs)
                    }
                    .disabled(selectedCandidateIDs.isEmpty)
                    .accessibilityIdentifier("saveSelectedDocumentBatchCandidates")
                }
                if outcome.hasMore {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Continue with remaining pages") {
                            onContinue()
                        }
                    }
                }
            }
        }
    }
}
