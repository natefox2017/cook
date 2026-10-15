// Developer: gengyun
// Purpose: Defines the Core-only handoff ports that DEV-434 and DEV-428 implement for the app-level draft/import save orchestration.

import Foundation

/// Persists a finalized, server-authored recipe to the local library in ONE atomic commit.
/// DEV-434 implements this port on RecipeStore. The inputs are Core types only, so the store
/// never imports app-level draft/import service types. `recipeID` is the server-authored stable
/// ID from finalize; `ownerID` is the verified owner the recipe belongs to.
public typealias RecipeFinalizedRecipeWriter =
    @Sendable (_ recipe: Recipe, _ recipeID: UUID, _ ownerID: UUID) async throws -> Void

/// Composes the concrete approved `Recipe` from a draft session, its accepted terminal
/// suggestions, and the approval receipt. DEV-428 owns this pure function (mirroring the backend
/// `composeApprovedDraftFields`); the suggestions come from `RecipeDraftTurn.result` `.proposal`
/// (via `RecipeDraftReviewState`), not from `receipt.selectedPaths`. Core types only.
public typealias RecipeDraftRecipeComposer =
    @Sendable (
        _ session: RecipeDraftSession,
        _ suggestions: [RecipeDraftSuggestion],
        _ receipt: RecipeDraftApprovalReceipt,
        _ ownerID: UUID
    ) async throws -> Recipe

extension RecipeStore {
    /// DEV-434 finalized-recipe write port. Honors the server-authored ID, never overwrites an
    /// existing record (so a delayed ACK retry cannot resurrect a user deletion), and commits
    /// atomically in one MainActor section with no await between the existence check and the upsert.
    public var finalizedRecipeWriter: RecipeFinalizedRecipeWriter {
        { recipe, recipeID, _ in
            try await MainActor.run {
                // Skip restoration only for an existing server ID or a known deletion tombstone;
                // never swallow a genuine persistence error (upsert throws through).
                if self.recipe(id: recipeID) != nil || self.hasRecipeDeletionTombstone(id: recipeID) {
                    return
                }
                var finalized = recipe
                finalized.id = recipeID
                try self.upsert(finalized)
            }
        }
    }
}

