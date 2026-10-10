// Developer: gengyun
// Purpose: Generate bounded, evidence-aware review questions for imported recipe drafts.

import Foundation

public struct RecipeImportReviewQuestion: Identifiable, Equatable, Sendable {
    public let id: String
    public let question: String
    public let evidenceIDs: [UUID]

    public init(id: String, question: String, evidenceIDs: [UUID] = []) {
        self.id = id
        self.question = question
        self.evidenceIDs = evidenceIDs
    }
}

/// Never invent missing measurements or instructions. This only asks users to
/// clarify fields the import worker has already flagged as needing review.
public enum RecipeImportReviewPlan {
    private static let orderedQuestions: [(key: String, text: String)] = [
        ("title", "What should this recipe be called?"),
        ("ingredients", "Which ingredients and amounts are missing?"),
        ("steps", "What preparation steps are missing?"),
        ("servings", "How many servings should this make?")
    ]

    public static func questions(
        from result: RecipeImportJobResponse.Result, maximum: Int = 3
    ) -> [RecipeImportReviewQuestion] {
        guard result.resultStatus == .needsReview, maximum > 0 else { return [] }
        let requestedPaths = result.reviewFields ?? []
        return orderedQuestions.compactMap { candidate -> RecipeImportReviewQuestion? in
            let reviewPaths = requestedPaths.filter { groupName($0) == candidate.key }
            guard !reviewPaths.isEmpty else { return nil }
            let relevant = result.fields.filter { groupName($0.key) == candidate.key }
            // Explicitly confirmed fields win over an older server review flag.
            // A user-confirmed ingredient must not suppress a question about
            // another still-unconfirmed ingredient in the same group.
            let allKnownFieldsConfirmed = !relevant.isEmpty
                && relevant.values.allSatisfy(\.userConfirmed)
            // Confirmation of one indexed field cannot resolve a different missing field.
            let missingSpecificField = reviewPaths.contains { path in
                path != candidate.key && result.fields[path]?.userConfirmed != true
            }
            guard missingSpecificField || !allKnownFieldsConfirmed else { return nil }
            let identifiers = Array(
                Set(relevant.values.flatMap(\.evidenceIDs))
            ).sorted { $0.uuidString < $1.uuidString }
            return RecipeImportReviewQuestion(
                id: candidate.key, question: candidate.text, evidenceIDs: identifiers)
        }.prefix(min(maximum, 3)).map { $0 }
    }

    private static func groupName(_ path: String) -> String {
        let group = path.split(separator: "[", maxSplits: 1).first ?? Substring(path)
        return String(group.split(separator: ".", maxSplits: 1).first ?? group)
    }
}
