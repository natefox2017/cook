// Developer: gengyun
// Purpose: Presents the owner draft review flow with explicit loading, review, error, retry, and manual exit paths.

import RecipeCore
import SwiftUI

struct RecipeDraftReviewView: View {
    @State private var service: RecipeDraftService?
    @State private var configurationError: String?
    @Environment(\.dismiss) private var dismiss
    private let jobID: UUID

    init(jobID: UUID) {
        self.jobID = jobID
    }

    var body: some View {
        Group {
            if let service {
                content(for: service)
            } else if let configurationError {
                failure(message: configurationError, retryable: false)
            } else {
                ProgressView()
                    .accessibilityIdentifier("draft-review.loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(RecipeLanguage.localized("Draft Review"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard service == nil && configurationError == nil else { return }
            do {
                let built = try RecipeDraftService()
                service = built
                await built.createOrResumeSession(jobID: jobID)
            } catch {
                configurationError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func content(for service: RecipeDraftService) -> some View {
        switch service.phase {
        case .idle, .loading, .approving:
            ProgressView()
                .accessibilityIdentifier("draft-review.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .reviewing(let state):
            review(state: state, service: service)
        case .ready:
            ready(service: service)
        case .committed:
            committed
        case .failed(let message, let retryable):
            failure(message: message, retryable: retryable) {
                if retryable {
                    Task {
                        await service.createOrResumeSession(jobID: jobID)
                    }
                }
            }
        }
    }

    private func review(
        state: RecipeDraftService.RecipeDraftReviewState,
        service: RecipeDraftService
    ) -> some View {
        List {
            if !state.reviewFields.isEmpty {
                Section(RecipeLanguage.localized("Fields to review")) {
                    ForEach(state.reviewFields, id: \.self) { path in
                        Text(path)
                            .font(RecipeTheme.body())
                    }
                }
            }

            if !state.questions.isEmpty {
                Section(RecipeLanguage.localized("Questions")) {
                    ForEach(state.questions, id: \.path) { question in
                        Text(question.question)
                            .font(RecipeTheme.body())
                    }
                }
            }

            if !state.suggestions.isEmpty {
                Section(RecipeLanguage.localized("AI suggestions")) {
                    ForEach(state.suggestions, id: \.path) { suggestion in
                        VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
                            Text(suggestion.rawValue)
                                .font(RecipeTheme.body())
                            Text(suggestion.reason)
                                .font(RecipeTheme.body(15))
                                .foregroundStyle(.secondary)
                            Label(
                                RecipeLanguage.localized("AI suggested"),
                                systemImage: "sparkles"
                            )
                            .font(RecipeTheme.body(13))
                            .foregroundStyle(RecipeTheme.accent)
                        }
                        .padding(.vertical, RecipeSpacing.xSmall)
                    }
                }
            }

            Section {
                Button {
                    Task {
                        await service.accept(selectedPaths: state.suggestions.map(\.path))
                    }
                } label: {
                    Text(RecipeLanguage.localized("Accept suggestions"))
                }
                .accessibilityIdentifier("draft-review.accept")
                .disabled(state.suggestions.isEmpty)

                Button(role: .destructive) {
                    Task {
                        await service.reject()
                    }
                } label: {
                    Text(RecipeLanguage.localized("Reject all"))
                }
                .accessibilityIdentifier("draft-review.reject")

                Button {
                    service.skipToManual()
                    dismiss()
                } label: {
                    Text(RecipeLanguage.localized("Skip AI and enter manually"))
                }
                .accessibilityIdentifier("draft-review.skip-manual")
            }
        }
        .accessibilityIdentifier("draft-review.review")
    }

    private func ready(service: RecipeDraftService) -> some View {
        VStack(spacing: RecipeSpacing.medium) {
            Text(RecipeLanguage.localized("This draft is ready to save."))
                .font(RecipeTheme.heading(.section))
                .multilineTextAlignment(.center)
            Button {
                service.skipToManual()
                dismiss()
            } label: {
                Text(RecipeLanguage.localized("Continue"))
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("draft-review.continue")
        }
        .padding(RecipeSpacing.pageInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var committed: some View {
        VStack(spacing: RecipeSpacing.medium) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(RecipeTheme.accent)
            Text(RecipeLanguage.localized("Review complete."))
                .font(RecipeTheme.heading(.section))
            Button(RecipeLanguage.localized("Done")) {
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("draft-review.done")
        }
        .padding(RecipeSpacing.pageInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("draft-review.committed")
    }

    private func failure(
        message: String,
        retryable: Bool,
        retry: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: RecipeSpacing.medium) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.yellow)
            Text(message)
                .font(RecipeTheme.body())
                .multilineTextAlignment(.center)
            if retryable, let retry {
                Button(RecipeLanguage.localized("Retry")) {
                    retry()
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("draft-review.retry")
            }
            Button(RecipeLanguage.localized("Skip AI and enter manually")) {
                dismiss()
            }
            .accessibilityIdentifier("draft-review.skip-manual")
        }
        .padding(RecipeSpacing.pageInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("draft-review.failure")
    }
}
