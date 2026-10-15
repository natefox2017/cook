// Developer: gengyun
// Purpose: Independent owner review screen for AI draft suggestions, with explicit approve, skip, retry, and manual-exit paths.

import RecipeCore
import SwiftUI

struct RecipeDraftReviewView: View {
    @Bindable var service: RecipeDraftService
    @Environment(\.dismiss) private var dismiss

    private let jobID: UUID
    private let clientRequestID: UUID

    init(service: RecipeDraftService, jobID: UUID, clientRequestID: UUID) {
        self.service = service
        self.jobID = jobID
        self.clientRequestID = clientRequestID
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(
                    String(
                        localized: LocalizedStringResource(
                            "Review Recipe", locale: RecipeLanguage.active
                        )
                    )
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            service.reset()
                            dismiss()
                        } label: {
                            Text(
                                String(
                                    localized: LocalizedStringResource(
                                        "Cancel", locale: RecipeLanguage.active
                                    )
                                )
                            )
                        }
                    }
                }
        }
        .task {
            await service.start(jobID: jobID, clientRequestID: clientRequestID)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch service.phase {
        case .idle, .loading:
            loading
        case .reviewing(let review):
            reviewList(review)
        case .approving:
            approving
        case .saved:
            saved
        case .noChangesNeeded:
            noChanges
        case .manualFallback:
            manualFallback
        case .failed(let failure):
            failureView(failure)
        case .unavailable(let message):
            unavailable(message)
        }
    }

    private var loading: some View {
        VStack(spacing: RecipeSpacing.medium) {
            ProgressView()
            Text(
                String(
                    localized: LocalizedStringResource(
                        "Reviewing this recipe…", locale: RecipeLanguage.active
                    )
                )
            )
            .font(RecipeTheme.body())
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RecipeTheme.canvas.ignoresSafeArea())
    }

    private var approving: some View {
        VStack(spacing: RecipeSpacing.medium) {
            ProgressView()
            Text(
                String(
                    localized: LocalizedStringResource(
                        "Saving approved changes…", locale: RecipeLanguage.active
                    )
                )
            )
            .font(RecipeTheme.body())
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RecipeTheme.canvas.ignoresSafeArea())
    }

    private var saved: some View {
        VStack(spacing: RecipeSpacing.medium) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(RecipeTheme.accent)
            Text(
                String(
                    localized: LocalizedStringResource(
                        "Saved to your library", locale: RecipeLanguage.active
                    )
                )
            )
            .font(RecipeTheme.heading(.section))
            Button {
                dismiss()
            } label: {
                Text(
                    String(
                        localized: LocalizedStringResource(
                            "Done", locale: RecipeLanguage.active
                        )
                    )
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("draftReviewDone")
        }
        .padding(RecipeSpacing.pageInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RecipeTheme.canvas.ignoresSafeArea())
    }

    private var noChanges: some View {
        VStack(spacing: RecipeSpacing.medium) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(RecipeTheme.accent)
            Text(
                String(
                    localized: LocalizedStringResource(
                        "No changes needed", locale: RecipeLanguage.active
                    )
                )
            )
            .font(RecipeTheme.heading(.section))
            Text(
                String(
                    localized: LocalizedStringResource(
                        "This recipe is complete. You can save it now.", locale: RecipeLanguage.active
                    )
                )
            )
            .font(RecipeTheme.body())
            .foregroundStyle(.secondary)
            Button {
                service.skipToManual()
            } label: {
                Text(
                    String(
                        localized: LocalizedStringResource(
                            "Continue", locale: RecipeLanguage.active
                        )
                    )
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(RecipeSpacing.pageInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RecipeTheme.canvas.ignoresSafeArea())
    }

    private var manualFallback: some View {
        Color.clear.onAppear {
            service.reset()
            dismiss()
        }
    }

    private func unavailable(_ message: String) -> some View {
        VStack(spacing: RecipeSpacing.medium) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(message)
                .font(RecipeTheme.body())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                service.skipToManual()
            } label: {
                Text(
                    String(
                        localized: LocalizedStringResource(
                            "Enter Manually", locale: RecipeLanguage.active
                        )
                    )
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(RecipeSpacing.pageInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RecipeTheme.canvas.ignoresSafeArea())
    }

    private func failureView(_ failure: RecipeDraftFailure) -> some View {
        VStack(spacing: RecipeSpacing.medium) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(failure.message)
                .font(RecipeTheme.body())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if failure.recoverable {
                Button {
                    Task {
                        await service.retry()
                    }
                } label: {
                    Text(
                        String(
                            localized: LocalizedStringResource(
                                "Try Again", locale: RecipeLanguage.active
                            )
                        )
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            Button {
                service.skipToManual()
            } label: {
                Text(
                    String(
                        localized: LocalizedStringResource(
                            "Enter Manually", locale: RecipeLanguage.active
                        )
                    )
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(RecipeSpacing.pageInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RecipeTheme.canvas.ignoresSafeArea())
    }

    private func reviewList(_ review: RecipeDraftReview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RecipeSpacing.large) {
                if !review.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: RecipeSpacing.small) {
                        Text(
                            String(
                                localized: LocalizedStringResource(
                                    "AI Suggestions", locale: RecipeLanguage.active
                                )
                            )
                        )
                        .font(RecipeTheme.heading(.section))

                        ForEach(review.suggestions, id: \.self) { suggestion in
                            SuggestionRow(
                                suggestion: suggestion,
                                isSelected: review.selectedPaths.contains(suggestion.path),
                                onToggle: {
                                    if review.selectedPaths.contains(suggestion.path) {
                                        service.deselect(suggestion.path)
                                    } else {
                                        service.select(suggestion.path)
                                    }
                                }
                            )
                        }
                    }
                }

                if !review.questions.isEmpty || !review.reviewFields.isEmpty {
                    VStack(alignment: .leading, spacing: RecipeSpacing.small) {
                        Text(
                            String(
                                localized: LocalizedStringResource(
                                    "Needs Your Input", locale: RecipeLanguage.active
                                )
                            )
                        )
                        .font(RecipeTheme.heading(.section))

                        ForEach(review.questions, id: \.self) { question in
                            QuestionRow(question: question)
                        }
                        ForEach(review.reviewFields, id: \.self) { path in
                            Text(path)
                                .font(RecipeTheme.body())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(spacing: RecipeSpacing.small) {
                    Button {
                        Task {
                            await service.approve()
                        }
                    } label: {
                        Text(
                            String(
                                localized: LocalizedStringResource(
                                    "Save Approved Changes", locale: RecipeLanguage.active
                                )
                            )
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(review.selectedPaths.isEmpty)
                    .accessibilityIdentifier("draftReviewApprove")

                    Button {
                        Task {
                            await service.rejectAI()
                        }
                    } label: {
                        Text(
                            String(
                                localized: LocalizedStringResource(
                                    "Skip AI Suggestions", locale: RecipeLanguage.active
                                )
                            )
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("draftReviewSkip")
                }
            }
            .padding(RecipeSpacing.pageInset)
        }
        .background(RecipeTheme.canvas.ignoresSafeArea())
    }
}

private struct SuggestionRow: View {
    let suggestion: RecipeDraftSuggestion
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: RecipeSpacing.small) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? RecipeTheme.accent : .secondary)
                VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
                    Text(suggestion.rawValue)
                        .font(RecipeTheme.body(17))
                        .multilineTextAlignment(.leading)
                    if !suggestion.reason.isEmpty {
                        Text(suggestion.reason)
                            .font(RecipeTheme.body(14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Text(
                        String(
                            localized: LocalizedStringResource(
                                "AI suggested", locale: RecipeLanguage.active
                            )
                        )
                    )
                    .font(RecipeTheme.body(12))
                    .foregroundStyle(RecipeTheme.accent)
                    .padding(.horizontal, RecipeSpacing.small)
                    .padding(.vertical, RecipeSpacing.xxSmall)
                    .background(RecipeTheme.accent.opacity(0.12), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .padding(RecipeSpacing.medium)
            .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("draftSuggestion-\(suggestion.path)")
    }
}

private struct QuestionRow: View {
    let question: RecipeDraftQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
            Text(question.question)
                .font(RecipeTheme.body())
            Text(
                String(
                    localized: LocalizedStringResource(
                        "Answer by entering the details manually.", locale: RecipeLanguage.active
                    )
                )
            )
            .font(RecipeTheme.body(14))
            .foregroundStyle(.secondary)
        }
        .padding(RecipeSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }
}
