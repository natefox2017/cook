// Developer: gengyun
// Purpose: Defines weekly meal-plan templates, their atomic apply/preview contract, and the premium access seam.

import Foundation

/// A single day/slot reference inside a weekly template. `relativeDayOffset`
/// is 0...6 from the template's own week start so applying stays DST-safe
/// when combined with `Calendar` day addition (never 86400-second math).
public struct RecipeMealPlanTemplateSlot: Codable, Hashable, Sendable {
    public let relativeDayOffset: Int
    public let mealSlot: MealSlot
    public let recipeID: UUID

    public init(relativeDayOffset: Int, mealSlot: MealSlot, recipeID: UUID) {
        self.relativeDayOffset = relativeDayOffset
        self.mealSlot = mealSlot
        self.recipeID = recipeID
    }
}

/// A named, locally persisted weekly template. It references recipes by ID
/// only and never copies recipe bodies, servings, or other recipe content.
public struct RecipeMealPlanTemplate: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var slots: [RecipeMealPlanTemplateSlot]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        slots: [RecipeMealPlanTemplateSlot],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.slots = slots
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// On-disk envelope for the independent template store. Templates deliberately
/// never join the cloud library snapshot, so this file owns its own version.
public struct RecipeMealPlanTemplateFile: Codable, Sendable, Equatable {
    public var version: Int
    public var templates: [RecipeMealPlanTemplate]

    public init(version: Int = 1, templates: [RecipeMealPlanTemplate] = []) {
        self.version = version
        self.templates = templates
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case templates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        templates =
            try container.decodeIfPresent([RecipeMealPlanTemplate].self, forKey: .templates) ?? []
    }
}

public enum RecipeMealPlanTemplateError: LocalizedError, Equatable {
    case unreadable(String)
    case missingTemplate
    case emptyName
    case nameTooLong
    case emptyWeek
    case invalidSlot

    public var errorDescription: String? {
        switch self {
        case .unreadable(let reason):
            RecipeLanguage.localized(
                "Your templates could not be read. The original file has been preserved. %@",
                reason
            )
        case .missingTemplate:
            RecipeLanguage.localized("This template is no longer available.")
        case .emptyName:
            RecipeLanguage.localized("Give the template a name.")
        case .nameTooLong:
            RecipeLanguage.localized("Template names can be up to 80 characters.")
        case .emptyWeek:
            RecipeLanguage.localized("Add at least one meal before saving a template.")
        case .invalidSlot:
            RecipeLanguage.localized("The template contains an invalid day or slot.")
        }
    }
}

/// One target-week slot that already holds a different recipe.
public struct MealTemplateConflict: Identifiable, Hashable, Sendable {
    public let date: Date
    public let mealSlot: MealSlot
    public let existingRecipeID: UUID
    public let incomingRecipeID: UUID

    public init(
        date: Date,
        mealSlot: MealSlot,
        existingRecipeID: UUID,
        incomingRecipeID: UUID
    ) {
        self.date = date
        self.mealSlot = mealSlot
        self.existingRecipeID = existingRecipeID
        self.incomingRecipeID = incomingRecipeID
    }

    public var id: String {
        "\(date.timeIntervalSinceReferenceDate):\(mealSlot.rawValue)"
    }
}

/// Read-only preview of what applying a template would touch, computed without
/// mutating the meal plan.
public struct MealTemplatePreview: Hashable, Sendable {
    public let missingRecipeCount: Int
    public let conflicts: [MealTemplateConflict]
    public let totalSlots: Int

    public var hasMissingRecipes: Bool { missingRecipeCount > 0 }
    public var hasConflicts: Bool { !conflicts.isEmpty }

    public init(
        missingRecipeCount: Int,
        conflicts: [MealTemplateConflict],
        totalSlots: Int
    ) {
        self.missingRecipeCount = missingRecipeCount
        self.conflicts = conflicts
        self.totalSlots = totalSlots
    }
}

/// Result of one atomic template application against the meal plan.
public struct MealTemplateApplyResult: Hashable, Sendable {
    public let appliedSlots: Int
    public let skippedMissingRecipes: Int
    public let skippedConflicts: Int

    public init(
        appliedSlots: Int,
        skippedMissingRecipes: Int,
        skippedConflicts: Int
    ) {
        self.appliedSlots = appliedSlots
        self.skippedMissingRecipes = skippedMissingRecipes
        self.skippedConflicts = skippedConflicts
    }
}

/// Seam that lets the meal-plan UI ask whether weekly templates are manageable
/// without coupling to StoreKit or the purchase bridge. The default adapter
/// keeps the free-test baseline available; a commercial access client supplies
/// its own `RecipeAccessResponse` when that wiring is ready.
public protocol RecipeWeeklyTemplatesGate: Sendable {
    func canManageWeeklyTemplates() -> Bool
}

public struct RecipeWeeklyTemplatesAccess: RecipeWeeklyTemplatesGate {
    public let response: RecipeAccessResponse?

    public init(response: RecipeAccessResponse? = nil) {
        self.response = response
    }

    public func canManageWeeklyTemplates() -> Bool {
        guard let response else {
            // No access contract has been fetched yet. The first fully-free
            // release stays available until the commercial policy is wired.
            return true
        }
        switch response.stage {
        case .freeTest:
            return true
        case .commercial:
            return response.capabilities.contains { $0.id == .weeklyTemplates && $0.entitled }
        }
    }
}
