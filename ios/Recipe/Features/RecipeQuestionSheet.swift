// Developer: gengyun
// Purpose: Presents the bounded recipe Q&A sheet with source/AI marks and explicit edit handoff.

import RecipeCore
import SwiftUI

/// A standalone Q&A surface for the current recipe. Entry into RecipeDetailView
/// and CookingView is wired by the TTS/edit owners (DEV-437/DEV-76); this sheet
/// only depends on an existing Recipe and a RecipeQuestionService.
@MainActor
struct RecipeQuestionSheet: View {
    let recipe: Recipe
    let service: RecipeQuestionService
    let onRequestEdit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var answer: RecipeQuestionAnswer?
    @State private var errorMessage: String?
    @State private var isAsking = false

    private var canAsk: Bool {
        !isAsking && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                questionSection
                if let answer {
                    answerSection(answer)
                }
                if !service.history.isEmpty {
                    historySection
                }
            }
            .navigationTitle(text("Ask"))
            .navigationBarTitleDisplayMode(.inline)
            .tint(RecipeTheme.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text("Close")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAsking {
                        ProgressView()
                    } else {
                        Button(text("Ask")) {
                            ask()
                        }
                        .disabled(!canAsk)
                    }
                }
            }
            .alert(
                text("Question"),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button(text("OK"), role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .environment(\.locale, RecipeLanguage.active)
        .onDisappear {
            service.close()
        }
    }

    private var questionSection: some View {
        Section(text("Your question")) {
            TextEditor(text: $question)
                .frame(minHeight: 80)
                .onChange(of: question) { _, value in
                    if value.unicodeScalars.count > 1000 {
                        question = String(value.prefix(1000))
                    }
                }
            Text("\(question.unicodeScalars.count)/1000")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func answerSection(_ answer: RecipeQuestionAnswer) -> some View {
        Section(text("Answer")) {
            Text(answer.answer)
                .font(RecipeTheme.body())
            ForEach(answer.statements, id: \.self) { statement in
                HStack(alignment: .top, spacing: 8) {
                    Text(statement.kind == .recipe ? text("From recipe") : text("AI suggestion"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statement.kind == .recipe ? RecipeTheme.accent : .secondary)
                    Text(statement.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Button(text("Send to edit review")) {
                onRequestEdit(answer.answer)
            }
            .disabled(answer.answer.isEmpty)
        }
    }

    private var historySection: some View {
        Section(text("Earlier")) {
            ForEach(service.history, id: \.self) { turn in
                VStack(alignment: .leading, spacing: 4) {
                    Text(turn.question)
                        .font(.subheadline.weight(.semibold))
                    Text(turn.answer)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func ask() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isAsking = true
        errorMessage = nil
        Task { @MainActor in
            defer { isAsking = false }
            do {
                answer = try await service.ask(recipe: recipe, question: trimmed)
                question = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func text(_ key: String) -> String {
        String(
            localized: LocalizedStringResource(
                String.LocalizationValue(key), locale: RecipeLanguage.active
            )
        )
    }
}
