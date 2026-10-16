// Developer: gengyun
// Purpose: Typed ports and orchestration for reviewable recipe translation.

import Foundation

/// One translation job: the private source recipe plus an explicit target locale.
public struct RecipeTranslationRequest: Equatable, Sendable {
    public let recipe: Recipe
    public let target: RecipeTranslationTarget
    /// Client-stable idempotency key. The caller generates one per translation attempt and reuses
    /// it verbatim across retries of that attempt; a fresh attempt gets a fresh UUID.
    public let proposalID: UUID

    public init(recipe: Recipe, target: RecipeTranslationTarget, proposalID: UUID = UUID()) {
        self.recipe = recipe
        self.target = target
        self.proposalID = proposalID
    }
}

/// Produces a reviewable translation proposal. A later HTTP client can back this
/// with the `recipe-translations` Edge Function; the port keeps the service pure.
public protocol RecipeTranslationProviderPort: Sendable {
    func translate(_ request: RecipeTranslationRequest) async throws -> RecipeTranslationProposal
}

/// Persists an approved translation variant. Saving must be idempotent by the
/// variant's stable recipe id so a crash-and-replay never creates a duplicate.
public protocol RecipeTranslationSavePort: Sendable {
    func saveVariant(
        _ variant: Recipe,
        provenance: RecipeTranslationProvenance
    ) async throws -> Recipe
}

/// Result of approving a proposal before it is persisted.
public struct RecipeTranslationApproval: Equatable, Sendable {
    public let variant: Recipe
    public let provenance: RecipeTranslationProvenance

    public init(variant: Recipe, provenance: RecipeTranslationProvenance) {
        self.variant = variant
        self.provenance = provenance
    }
}

/// Orchestrates translate → review → approve → save through injected ports.
/// Quota settlement is deliberately absent: it is composed by the quota task
/// around this service per the frozen DEV-425 `recipe_translation` capability,
/// so a missing settlement can never silently become an unmetered path.
public struct RecipeTranslationService: Sendable {
    public let provider: any RecipeTranslationProviderPort
    public let save: any RecipeTranslationSavePort

    public init(
        provider: any RecipeTranslationProviderPort,
        save: any RecipeTranslationSavePort
    ) {
        self.provider = provider
        self.save = save
    }

    /// Cancelling here leaves the source recipe untouched: no side effects happen
    /// until an explicit save.
    public func translate(_ request: RecipeTranslationRequest) async throws -> RecipeTranslationProposal {
        try Task.checkCancellation()
        return try await provider.translate(request)
    }

    /// Approve a reviewable proposal into a variant with a stable id and provenance.
    /// This is a pure transform; it never mutates or persists the source recipe.
    public func approve(
        _ proposal: RecipeTranslationProposal,
        original: Recipe
    ) throws -> RecipeTranslationApproval {
        let variant = try proposal.approvedVariant(from: original)
        return RecipeTranslationApproval(
            variant: variant,
            // The variant already carries the durable lineage; keep the standalone record
            // identical so callers never observe two provenance timestamps.
            provenance: variant.translationProvenance ?? proposal.provenance()
        )
    }

    /// Approve and persist. Recovery is safe: the deterministic variant id means a
    /// repeated save returns the same recipe instead of a duplicate variant.
    public func saveVariant(
        _ proposal: RecipeTranslationProposal,
        original: Recipe
    ) async throws -> Recipe {
        let approval = try approve(proposal, original: original)
        return try await save.saveVariant(approval.variant, provenance: approval.provenance)
    }
}
