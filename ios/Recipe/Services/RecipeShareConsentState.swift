// Developer: gengyun
// Purpose: Coordinates explicit sharing consent through the existing injected owner client.

import Foundation
import Observation
import RecipeCore

/// Caller-retained local lineage, never evidence that the server checked a private recipe.
struct RecipeShareConsentExistingShare {
    let share: RecipePublishedShare
    let recipeID: UUID
}

@MainActor
@Observable
final class RecipeShareConsentState {
    let recipeID: UUID
    private(set) var scope: RecipeShareScope = .summaryAndSource
    private(set) var rightsConfirmed = false
    private(set) var preview: PublicRecipeSnapshot?
    private(set) var share: RecipePublishedShare?
    private(set) var errorKey: String?
    private(set) var isBusy = false
    private(set) var needsReload = false
    private var previewSourceDate: Date?
    private var isActive = true
    private var acceptedSourceDate: Date?
    private var acceptedOwnerID: UUID?
    private var intent: Intent?
    private var generation = 0
    private var task: Task<Void, Never>?
    private let service: RecipeSharePublishingService
    private let currentOwnerID: @MainActor () -> UUID?
    private let readRecipe: @MainActor (UUID) -> Recipe?
    private let existingBindingValid: Bool

    private struct Intent {
        let recipe: Recipe
        let approval: RecipeShareApproval
        let ownerID: UUID
        let snapshot: PublicRecipeSnapshot
        let key: UUID
    }

    init(
        recipeID: UUID,
        service: RecipeSharePublishingService,
        currentOwnerID: @escaping @MainActor () -> UUID?,
        readRecipe: @escaping @MainActor (UUID) -> Recipe?,
        existingShare: RecipeShareConsentExistingShare? = nil
    ) {
        self.recipeID = recipeID
        self.service = service
        self.currentOwnerID = currentOwnerID
        self.readRecipe = readRecipe
        existingBindingValid =
            existingShare == nil
            || (existingShare?.recipeID == recipeID
                && existingShare?.share.authenticatedOwnerID == currentOwnerID())
        // Existing metadata alone does not authorize sharing a freshly generated preview.
        if existingBindingValid, let existingShare,
            existingShare.share.authenticatedOwnerID == currentOwnerID()
        {
            share = existingShare.share
        }
        refreshPreview()
    }

    var publicURL: URL? {
        guard isActive, !isBusy, !needsReload, let share, share.revokedAt == nil,
            acceptedOwnerID == currentOwnerID(),
            acceptedOwnerID == share.authenticatedOwnerID,
            acceptedSourceDate == readRecipe(recipeID)?.updatedAt,
            acceptedSourceDate != nil,
            RecipePublicShareURL.isValid(share.publicURL)
        else {
            return nil
        }
        return share.publicURL
    }

    var canRetry: Bool {
        intent != nil && errorKey != nil && !needsReload && !isBusy
    }

    func select(scope: RecipeShareScope, rightsConfirmed: Bool) {
        guard !isBusy else { return }
        self.scope = scope
        self.rightsConfirmed = rightsConfirmed
        acceptedSourceDate = nil
        intent = nil
        errorKey = nil
        refreshPreview()
    }

    func refreshPreview() {
        guard let recipe = readRecipe(recipeID) else {
            preview = nil
            previewSourceDate = nil
            acceptedSourceDate = nil
            errorKey = "This recipe changed. Review it before sharing."
            return
        }
        previewSourceDate = recipe.updatedAt
        preview = try? PublicRecipeSnapshot.preview(
            of: recipe,
            approvedBy: RecipeShareApproval(
                recipeID: recipeID, expectedUpdatedAt: recipe.updatedAt,
                scope: scope, hasDistributionRights: rightsConfirmed
            )
        )
    }

    func confirm() async {
        guard isActive, !isBusy, !needsReload else { return }
        intent = nil
        do {
            let owner = try owner()
            let recipe = try source()
            guard recipe.updatedAt == previewSourceDate else {
                refreshPreview()
                throw RecipeShareValidationError.staleRecipe
            }
            let approval = RecipeShareApproval(
                recipeID: recipeID, expectedUpdatedAt: recipe.updatedAt,
                scope: scope, hasDistributionRights: rightsConfirmed
            )
            let snapshot = try PublicRecipeSnapshot.preview(of: recipe, approvedBy: approval)
            intent = Intent(
                recipe: recipe, approval: approval, ownerID: owner,
                snapshot: snapshot, key: UUID()
            )
            await submit()
        } catch {
            record(error)
        }
    }

    func retry() async {
        guard isActive, canRetry else { return }
        await submit()
    }

    private func submit() async {
        guard !isBusy, let intent else { return }
        await perform {
            try self.validate(intent)
            let result: RecipePublishedShare
            if let share = self.share {
                result = try await self.service.update(
                    share, recipe: intent.recipe, approval: intent.approval
                )
            } else {
                result = try await self.service.create(
                    recipe: intent.recipe, approval: intent.approval,
                    ownerID: intent.ownerID, idempotencyKey: intent.key
                )
            }
            try self.validate(intent)
            return result
        } completion: { result in
            self.share = result
            self.acceptedOwnerID = intent.ownerID
            self.acceptedSourceDate = intent.recipe.updatedAt
            self.preview = intent.snapshot
            self.intent = nil
        }
    }

    func reload() async {
        guard isActive, !isBusy, let share else { return }
        let date = readRecipe(recipeID)?.updatedAt
        await perform {
            guard try self.owner() == share.authenticatedOwnerID else {
                throw RecipeSharePublishingError.accountChanged
            }
            _ = try self.source()
            let result = try await self.service.get(
                shareID: share.shareID, ownerID: share.authenticatedOwnerID
            )
            guard try self.owner() == share.authenticatedOwnerID else {
                throw RecipeSharePublishingError.accountChanged
            }
            guard try self.source().updatedAt == date else {
                throw RecipeShareValidationError.staleRecipe
            }
            return result
        } completion: { result in
            self.share = result.revokedAt == nil ? result : nil
            self.needsReload = false
            self.intent = nil
            // Fresh owner metadata authorizes the URL, never a newly generated poster snapshot.
            self.acceptedSourceDate = result.revokedAt == nil ? date : nil
            self.acceptedOwnerID = result.revokedAt == nil ? result.authenticatedOwnerID : nil
        }
    }

    func revoke() async {
        guard isActive, !isBusy, let share else { return }
        let date = readRecipe(recipeID)?.updatedAt
        await perform {
            guard try self.owner() == share.authenticatedOwnerID else {
                throw RecipeSharePublishingError.accountChanged
            }
            _ = try self.source()
            try await self.service.revoke(share)
            guard try self.owner() == share.authenticatedOwnerID else {
                throw RecipeSharePublishingError.accountChanged
            }
            guard try self.source().updatedAt == date else {
                throw RecipeShareValidationError.staleRecipe
            }
            return share
        } completion: { _ in
            self.share = nil
            self.acceptedOwnerID = nil
            self.acceptedSourceDate = nil
            self.intent = nil
            self.needsReload = false
        }
    }

    func cancel() {
        isActive = false
        generation += 1
        task?.cancel()
        task = nil
        isBusy = false
        intent = nil
    }

    private func owner() throws -> UUID {
        guard existingBindingValid else {
            throw RecipeShareValidationError.wrongRecipe
        }
        guard let owner = currentOwnerID() else {
            throw RecipeSharePublishingError.notSignedIn
        }
        guard share == nil || share?.authenticatedOwnerID == owner else {
            throw RecipeSharePublishingError.accountChanged
        }
        return owner
    }

    private func source() throws -> Recipe {
        guard let recipe = readRecipe(recipeID), recipe.id == recipeID else {
            throw RecipeShareValidationError.staleRecipe
        }
        return recipe
    }

    private func validate(_ intent: Intent) throws {
        guard try owner() == intent.ownerID else {
            throw RecipeSharePublishingError.accountChanged
        }
        guard try source().updatedAt == intent.recipe.updatedAt else {
            throw RecipeShareValidationError.staleRecipe
        }
    }

    private func perform(
        operation: @escaping @MainActor () async throws -> RecipePublishedShare,
        completion: @escaping @MainActor (RecipePublishedShare) -> Void
    ) async {
        generation += 1
        let operationGeneration = generation
        isBusy = true
        errorKey = nil
        task = Task { @MainActor in
            defer {
                if self.generation == operationGeneration {
                    self.isBusy = false
                    self.task = nil
                }
            }
            do {
                let result = try await operation()
                try Task.checkCancellation()
                guard self.generation == operationGeneration else { return }
                completion(result)
            } catch {
                guard self.generation == operationGeneration else { return }
                if !(error is CancellationError) {
                    self.record(error)
                }
            }
        }
        let operationTask = task
        await withTaskCancellationHandler {
            await operationTask?.value
        } onCancel: {
            operationTask?.cancel()
        }
    }

    private func record(_ error: Error) {
        switch error {
        case RecipeSharePublishingError.notSignedIn:
            errorKey = "Sharing requires sign-in."
            acceptedOwnerID = nil
            intent = nil
        case RecipeSharePublishingError.accountChanged:
            errorKey = "Your account changed. Sign in again."
            acceptedOwnerID = nil
            intent = nil
        case RecipeShareValidationError.staleRecipe, RecipeShareValidationError.wrongRecipe:
            errorKey = "This recipe changed. Review it before sharing."
            acceptedSourceDate = nil
            intent = nil
        case RecipeSharePublishingError.httpStatus(409):
            errorKey = "The public copy changed. Reload before updating."
            needsReload = true
        case RecipeSharePublishingError.httpStatus(401):
            errorKey = "Sharing requires sign-in."
            acceptedOwnerID = nil
        case RecipeSharePublishingError.httpStatus(404):
            errorKey = "The public link is unavailable."
            acceptedSourceDate = nil
        case RecipeSharePublishingError.httpStatus(429):
            errorKey = "Too many requests. Try again later."
        case RecipeSharePublishingError.httpStatus(503):
            errorKey = "Sharing is unavailable. Try again later."
        default:
            errorKey = "Could not share. Try again."
        }
    }
}
