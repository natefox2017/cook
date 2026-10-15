// Developer: gengyun
// Purpose: Verifies the deterministic weekly dinner plan generator's filtering, ordering, locking, and apply reconciliation.

import Foundation
import Testing

@testable import RecipeCore

private func recipeID(_ index: Int) -> UUID {
    UUID(uuidString: String(format: "A0000000-0000-4000-8000-%012X", index))!
}

private func makeRecipe(
    _ index: Int,
    prep: Int? = nil,
    cook: Int? = nil,
    tags: [String]? = nil,
    includeIngredients: Bool = true,
    includeSteps: Bool = true
) -> Recipe {
    Recipe(
        id: recipeID(index),
        title: "Recipe \(index)",
        prepMinutes: prep,
        cookMinutes: cook,
        ingredients: includeIngredients ? [RecipeIngredient(name: "Item")] : [],
        steps: includeSteps ? [RecipeStep(instruction: "Do it.")] : [],
        dietaryTags: tags)
}

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.minimumDaysInFirstWeek = 1
    return calendar
}

private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
    utcCalendar().date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
}

@Test func sameSeedProducesIdenticalShuffleAndDifferentSeedDiffers() {
    let ids = (0..<10).map { recipeID($0) }
    #expect(
        RecipeMealPlanGenerator.shuffled(ids, seed: 42)
            == RecipeMealPlanGenerator.shuffled(ids, seed: 42))
    #expect(
        RecipeMealPlanGenerator.shuffled(ids, seed: 42)
            != RecipeMealPlanGenerator.shuffled(ids, seed: 43))
}

@Test func dietaryTagFilterRequiresAllSelectedTagsAndIgnoresCase() {
    let recipes = [
        makeRecipe(1, tags: ["Vegetarian"]),
        makeRecipe(2, tags: ["Vegetarian", "Gluten-Free"]),
        makeRecipe(3, tags: ["Vegan"]),
        makeRecipe(4, tags: nil),
    ]
    let result = RecipeMealPlanGenerator.candidates(
        recipes: recipes, maxTotalMinutes: nil, dietaryTags: [" vegetarian "])
    #expect(result.orderedIDs == [recipeID(1), recipeID(2)])
    #expect(result.skipped[recipeID(3)] == .missingDietaryTag)
    #expect(result.skipped[recipeID(4)] == .missingDietaryTag)
}

@Test func durationLimitExcludesUnknownAndOverBudget() {
    let recipes = [
        makeRecipe(1, prep: 10, cook: 20),
        makeRecipe(2),
        makeRecipe(3, prep: 30, cook: 30),
    ]
    let result = RecipeMealPlanGenerator.candidates(
        recipes: recipes, maxTotalMinutes: 45, dietaryTags: [])
    #expect(result.orderedIDs == [recipeID(1)])
    #expect(result.skipped[recipeID(2)] == .missingDuration)
    #expect(result.skipped[recipeID(3)] == .exceedsDuration)
}

@Test func unknownDurationAllowedWhenNoLimitSet() {
    let recipes = [makeRecipe(1), makeRecipe(2, prep: 15)]
    let result = RecipeMealPlanGenerator.candidates(
        recipes: recipes, maxTotalMinutes: nil, dietaryTags: [])
    #expect(Set(result.orderedIDs) == [recipeID(1), recipeID(2)])
}

@Test func incompleteRecipeIsExcluded() {
    let recipes = [
        makeRecipe(1, includeIngredients: false),
        makeRecipe(2, includeSteps: false),
        makeRecipe(3),
    ]
    let result = RecipeMealPlanGenerator.candidates(
        recipes: recipes, maxTotalMinutes: nil, dietaryTags: [])
    #expect(result.orderedIDs == [recipeID(3)])
    #expect(result.skipped[recipeID(1)] == .missingIngredientsOrSteps)
    #expect(result.skipped[recipeID(2)] == .missingIngredientsOrSteps)
}

@Test func sevenDaysWithFewerCandidatesLeavesEmptyAndNeverDuplicates() {
    let recipes = (1...3).map { makeRecipe($0) }
    let dates = (0..<7).map { day(2026, 1, 5 + $0) }
    let proposal = RecipeMealPlanGenerator.generate(
        recipes: recipes, dates: dates, seed: 7, maxTotalMinutes: nil, dietaryTags: [],
        calendar: utcCalendar())
    #expect(proposal.slots.count == 7)
    let assigned = proposal.slots.compactMap(\.recipeID)
    #expect(assigned.count == 3)
    #expect(Set(assigned).count == 3)
    #expect(proposal.slots.filter { $0.reason == .insufficientCandidates }.count == 4)
}

@Test func lockSurvivesRegenerationWhileUnlockedSlotsRefill() throws {
    var recipes = (1...7).map { makeRecipe($0) }
    let dates = (0..<7).map { day(2026, 1, 5 + $0) }
    let original = RecipeMealPlanGenerator.generate(
        recipes: recipes, dates: dates, seed: 3, maxTotalMinutes: nil, dietaryTags: [],
        calendar: utcCalendar())
    let lockedSlotID = original.slots[0].id
    let lockedRecipeID = try #require(original.slots[0].recipeID)
    let locked = RecipeMealPlanGenerator.setLocked(true, slotID: lockedSlotID, in: original)

    recipes.append(makeRecipe(8))
    let regenerated = RecipeMealPlanGenerator.regenerate(locked, recipes: recipes)

    let kept = try #require(regenerated.slots.first { $0.id == lockedSlotID })
    #expect(kept.recipeID == lockedRecipeID)
    #expect(kept.isLocked)
    let assigned = regenerated.slots.compactMap(\.recipeID)
    #expect(Set(assigned).count == assigned.count)
    #expect(regenerated.slots.filter(\.isLocked).count == 1)
}

@Test func lockedDeletedRecipeReleasesForReconfirmation() throws {
    let recipes = (1...7).map { makeRecipe($0) }
    let dates = (0..<7).map { day(2026, 1, 5 + $0) }
    let original = RecipeMealPlanGenerator.generate(
        recipes: recipes, dates: dates, seed: 5, maxTotalMinutes: nil, dietaryTags: [],
        calendar: utcCalendar())
    let lockedSlotID = original.slots[0].id
    let lockedRecipeID = try #require(original.slots[0].recipeID)
    let locked = RecipeMealPlanGenerator.setLocked(true, slotID: lockedSlotID, in: original)

    let remaining = recipes.filter { $0.id != lockedRecipeID }
    let regenerated = RecipeMealPlanGenerator.regenerate(locked, recipes: remaining)

    let released = try #require(regenerated.slots.first { $0.id == lockedSlotID })
    #expect(released.recipeID == nil)
    #expect(!released.isLocked)
    #expect(released.reason == .lockedRecipeDeleted)
}

@Test func replaceSwapsCandidateAndRejectsDuplicate() throws {
    let recipes = (1...8).map { makeRecipe($0) }
    let dates = (0..<7).map { day(2026, 1, 5 + $0) }
    let original = RecipeMealPlanGenerator.generate(
        recipes: recipes, dates: dates, seed: 5, maxTotalMinutes: nil, dietaryTags: [],
        calendar: utcCalendar())
    let spare = try #require(original.candidateIDs.last)
    #expect(!original.slots.contains { $0.recipeID == spare })

    let slotB = original.slots[1]
    let valid = RecipeMealPlanGenerator.replace(in: original, slotID: slotB.id, recipeID: spare)
    #expect(valid.slots[1].recipeID == spare)

    let slotA = original.slots[0]
    let rejected = RecipeMealPlanGenerator.replace(
        in: original, slotID: slotB.id, recipeID: try #require(slotA.recipeID))
    #expect(rejected.slots[1].recipeID == original.slots[1].recipeID)
}

@Test func applyRespectsConflictPolicy() throws {
    let recipes = (1...2).map { makeRecipe($0) }
    let date = day(2026, 1, 5)
    let proposal = RecipeMealPlanGenerator.generate(
        recipes: recipes, dates: [date], seed: 1, maxTotalMinutes: nil, dietaryTags: [],
        calendar: utcCalendar())
    let existing = MealPlanEntry(recipeID: recipeID(99), date: date, slot: .dinner)

    let conflicts = RecipeMealPlanGenerator.conflictingMeals(
        proposal, existingMeals: [existing], calendar: utcCalendar())
    #expect(conflicts.count == 1)

    let fillOnly = RecipeMealPlanGenerator.apply(
        proposal, existingMeals: [existing], policy: .fillEmptySlotsOnly,
        calendar: utcCalendar())
    #expect(fillOnly.count == 1)
    #expect(fillOnly[0].recipeID == recipeID(99))

    let replaced = RecipeMealPlanGenerator.apply(
        proposal, existingMeals: [existing], policy: .replaceExisting,
        calendar: utcCalendar())
    #expect(replaced.count == 1)
    #expect(replaced[0].recipeID == proposal.slots[0].recipeID)
}

@Test func weekWindowRespectsConfiguredWeekStart() throws {
    var sunday = Calendar(identifier: .gregorian)
    sunday.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    sunday.firstWeekday = 1
    sunday.minimumDaysInFirstWeek = 1
    var monday = Calendar(identifier: .gregorian)
    monday.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    monday.firstWeekday = 2
    monday.minimumDaysInFirstWeek = 1

    // 2026-01-07 is a Wednesday.
    let anchor = try #require(
        sunday.date(from: DateComponents(year: 2026, month: 1, day: 7)))

    let sundayWeek = RecipeMealPlanGenerator.dinnerDates(weekContaining: anchor, calendar: sunday)
    let mondayWeek = RecipeMealPlanGenerator.dinnerDates(weekContaining: anchor, calendar: monday)

    #expect(sundayWeek.count == 7)
    #expect(mondayWeek.count == 7)
    #expect(sunday.dateComponents([.weekday], from: sundayWeek[0]).weekday == 1)
    #expect(monday.dateComponents([.weekday], from: mondayWeek[0]).weekday == 2)
    #expect(sundayWeek.contains { sunday.isDate($0, inSameDayAs: anchor) })
    #expect(mondayWeek.contains { monday.isDate($0, inSameDayAs: anchor) })
}
