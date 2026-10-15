// Developer: gengyun
// Purpose: Deterministically builds a confirmable weekly dinner plan from the private recipe library.

import Foundation

/// Why a recipe was excluded from the candidate set. Ordering is defined by the
/// filter's precedence: structure, then duration, then dietary tags.
public enum RecipeMealPlanSkipReason: String, Hashable, Sendable, CaseIterable {
    case missingIngredientsOrSteps
    case missingDuration
    case exceedsDuration
    case missingDietaryTag
}

/// How an applied plan reconciles with dinners already on the calendar.
public enum RecipeMealPlanApplyPolicy: String, Hashable, Sendable, CaseIterable {
    /// Keep existing planned dinners; only fill dates that are still empty.
    case fillEmptySlotsOnly
    /// Overwrite the planned dinner on every selected date.
    case replaceExisting
}

/// Why a slot ended up in its current state; rendered by the preview sheet.
public enum RecipeMealPlanReason: Hashable, Sendable {
    case assigned
    case timeUnknown
    case locked
    case insufficientCandidates
    case lockedRecipeDeleted
    /// A locked slot kept despite failing an active filter. The associated
    /// reason names the filter it conflicts with. Explicit locks are respected,
    /// so the conflict is surfaced instead of being silently dropped or
    /// double-reported as "skipped".
    case lockedFilterConflict(RecipeMealPlanSkipReason)
}

/// One dinner slot in a generated proposal. Identity is stable across regeneration.
public struct RecipeMealPlanSlot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let date: Date
    public var recipeID: UUID?
    public var isLocked: Bool
    public var reason: RecipeMealPlanReason

    public init(
        id: UUID = UUID(),
        date: Date,
        recipeID: UUID? = nil,
        isLocked: Bool = false,
        reason: RecipeMealPlanReason = .insufficientCandidates
    ) {
        self.id = id
        self.date = date
        self.recipeID = recipeID
        self.isLocked = isLocked
        self.reason = reason
    }
}

/// The filtered, deterministically ordered candidate recipes plus the skipped set.
public struct RecipeMealPlanCandidates: Hashable, Sendable {
    public let orderedIDs: [UUID]
    public let skipped: [UUID: RecipeMealPlanSkipReason]

    public init(orderedIDs: [UUID], skipped: [UUID: RecipeMealPlanSkipReason]) {
        self.orderedIDs = orderedIDs
        self.skipped = skipped
    }
}

/// A reproducible, explainable weekly dinner plan. It never touches the store; the
/// view realizes an applied plan through the shared atomic write-slot API.
public struct RecipeMealPlanProposal: Hashable, Sendable {
    public var slots: [RecipeMealPlanSlot]
    public let candidateIDs: [UUID]
    public let skipped: [UUID: RecipeMealPlanSkipReason]
    public let seed: UInt64
    public let maxTotalMinutes: Int?
    public let dietaryTags: [String]

    public init(
        slots: [RecipeMealPlanSlot],
        candidateIDs: [UUID],
        skipped: [UUID: RecipeMealPlanSkipReason],
        seed: UInt64,
        maxTotalMinutes: Int?,
        dietaryTags: [String]
    ) {
        self.slots = slots
        self.candidateIDs = candidateIDs
        self.skipped = skipped
        self.seed = seed
        self.maxTotalMinutes = maxTotalMinutes
        self.dietaryTags = dietaryTags
    }
}

/// Deterministic 64-bit PRNG so the same seed and library always produce the same plan.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

public enum RecipeMealPlanGenerator {

    // MARK: - Week window

    /// The seven consecutive start-of-day dinner dates for the week containing `date`.
    public static func dinnerDates(weekContaining date: Date, calendar: Calendar) -> [Date] {
        let start =
            calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    // MARK: - Tags

    /// Trim whitespace, drop empties, deduplicate, and lowercase in a locale-independent way.
    public static func normalizeTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(key)
            }
        }
        return result
    }

    /// A recipe matches when it carries every selected tag (empty selection matches all).
    public static func matchesTags(_ recipe: Recipe, normalizedTags: [String]) -> Bool {
        guard !normalizedTags.isEmpty else { return true }
        let recipeTags = Set(normalizeTags(recipe.dietaryTags ?? []))
        return normalizedTags.allSatisfy { recipeTags.contains($0) }
    }

    // MARK: - Candidate filtering

    /// Filter the library into a candidate set sorted by stable recipe ID. This is
    /// seed-independent; the caller applies the seeded shuffle separately.
    public static func candidates(
        recipes: [Recipe],
        maxTotalMinutes: Int?,
        dietaryTags: [String]
    ) -> RecipeMealPlanCandidates {
        let tags = normalizeTags(dietaryTags)
        var skipped: [UUID: RecipeMealPlanSkipReason] = [:]
        var ids: [UUID] = []

        for recipe in recipes {
            guard !recipe.ingredients.isEmpty, !recipe.steps.isEmpty else {
                skipped[recipe.id] = .missingIngredientsOrSteps
                continue
            }
            if let limit = maxTotalMinutes {
                guard let total = recipe.totalMinutes else {
                    skipped[recipe.id] = .missingDuration
                    continue
                }
                guard total <= limit else {
                    skipped[recipe.id] = .exceedsDuration
                    continue
                }
            }
            guard matchesTags(recipe, normalizedTags: tags) else {
                skipped[recipe.id] = .missingDietaryTag
                continue
            }
            ids.append(recipe.id)
        }

        ids.sort { $0.uuidString < $1.uuidString }
        return RecipeMealPlanCandidates(orderedIDs: ids, skipped: skipped)
    }

    /// Deterministic Fisher-Yates shuffle keyed by the input seed.
    public static func shuffled(_ ids: [UUID], seed: UInt64) -> [UUID] {
        var rng = SplitMix64(seed: seed)
        var result = ids
        guard result.count > 1 else { return result }
        for index in stride(from: result.count - 1, through: 1, by: -1) {
            let swapIndex = Int.random(in: 0...index, using: &rng)
            result.swapAt(index, swapIndex)
        }
        return result
    }

    // MARK: - Generation

    /// Build a fresh proposal over `dates`, assigning the shuffled candidates in order
    /// with no duplicate recipe. Empty slots mean the candidate set ran out.
    public static func generate(
        recipes: [Recipe],
        dates: [Date],
        seed: UInt64,
        maxTotalMinutes: Int?,
        dietaryTags: [String],
        calendar: Calendar = .current
    ) -> RecipeMealPlanProposal {
        let candidateSet = candidates(
            recipes: recipes, maxTotalMinutes: maxTotalMinutes, dietaryTags: dietaryTags)
        let ordered = shuffled(candidateSet.orderedIDs, seed: seed)
        let normalizedDates = normalizeDates(dates, calendar: calendar)
        let recipeByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })

        var slots: [RecipeMealPlanSlot] = []
        for (index, date) in normalizedDates.enumerated() {
            let recipeID = index < ordered.count ? ordered[index] : nil
            let reason = reason(for: recipeID, recipeByID: recipeByID, maxTotalMinutes: maxTotalMinutes)
            slots.append(
                RecipeMealPlanSlot(date: date, recipeID: recipeID, isLocked: false, reason: reason))
        }

        return RecipeMealPlanProposal(
            slots: slots,
            candidateIDs: ordered,
            skipped: candidateSet.skipped,
            seed: seed,
            maxTotalMinutes: maxTotalMinutes,
            dietaryTags: normalizeTags(dietaryTags))
    }

    /// Recompute candidates and refill only unlocked slots. A locked slot keeps its
    /// recipe unless that recipe was deleted from the library, in which case the lock
    /// is released and the slot is left for the user to re-confirm. Pass a different
    /// `seed` to reshuffle the unlocked slots; the default keeps the stored seed.
    public static func regenerate(
        _ proposal: RecipeMealPlanProposal,
        recipes: [Recipe],
        seed: UInt64? = nil
    ) -> RecipeMealPlanProposal {
        let effectiveSeed = seed ?? proposal.seed
        let candidateSet = candidates(
            recipes: recipes,
            maxTotalMinutes: proposal.maxTotalMinutes,
            dietaryTags: proposal.dietaryTags)
        let ordered = shuffled(candidateSet.orderedIDs, seed: effectiveSeed)
        let libraryIDs = Set(recipes.map(\.id))
        let recipeByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })

        var used = Set<UUID>()
        var releasedSlotIDs = Set<UUID>()
        var slots = proposal.slots.map { slot -> RecipeMealPlanSlot in
            guard slot.isLocked else { return slot }
            guard let recipeID = slot.recipeID, libraryIDs.contains(recipeID) else {
                releasedSlotIDs.insert(slot.id)
                return RecipeMealPlanSlot(
                    id: slot.id,
                    date: slot.date,
                    recipeID: nil,
                    isLocked: false,
                    reason: .lockedRecipeDeleted)
            }
            used.insert(recipeID)
            if let conflict = candidateSet.skipped[recipeID] {
                return RecipeMealPlanSlot(
                    id: slot.id,
                    date: slot.date,
                    recipeID: recipeID,
                    isLocked: true,
                    reason: .lockedFilterConflict(conflict))
            }
            return RecipeMealPlanSlot(
                id: slot.id,
                date: slot.date,
                recipeID: recipeID,
                isLocked: true,
                reason: .locked)
        }

        var candidateIndex = 0
        for index in slots.indices
        where !slots[index].isLocked && !releasedSlotIDs.contains(slots[index].id) {
            var assigned: UUID?
            while candidateIndex < ordered.count {
                let candidate = ordered[candidateIndex]
                candidateIndex += 1
                if !used.contains(candidate) {
                    assigned = candidate
                    used.insert(candidate)
                    break
                }
            }
            slots[index].recipeID = assigned
            slots[index].reason = reason(
                for: assigned, recipeByID: recipeByID, maxTotalMinutes: proposal.maxTotalMinutes)
        }

        // Locked recipes that survive regeneration are scheduled, not skipped:
        // drop them from the skipped set so the footer never double-reports a
        // pinned dinner as both "skipped" and placed.
        var skipped = candidateSet.skipped
        for slot in slots {
            guard slot.isLocked, let recipeID = slot.recipeID else { continue }
            skipped.removeValue(forKey: recipeID)
        }

        return RecipeMealPlanProposal(
            slots: slots,
            candidateIDs: ordered,
            skipped: skipped,
            seed: effectiveSeed,
            maxTotalMinutes: proposal.maxTotalMinutes,
            dietaryTags: proposal.dietaryTags)
    }

    // MARK: - Single-slot edits

    /// Swap one slot's recipe for another candidate. Rejected (returned unchanged) when
    /// the target is not a candidate or would duplicate another slot's recipe.
    public static func replace(
        in proposal: RecipeMealPlanProposal,
        slotID: UUID,
        recipeID: UUID
    ) -> RecipeMealPlanProposal {
        guard let index = proposal.slots.firstIndex(where: { $0.id == slotID }),
            proposal.candidateIDs.contains(recipeID),
            proposal.slots[index].recipeID != recipeID
        else {
            return proposal
        }
        if proposal.slots.contains(where: { $0.id != slotID && $0.recipeID == recipeID }) {
            return proposal
        }
        var slots = proposal.slots
        slots[index].recipeID = recipeID
        slots[index].reason = .assigned
        var next = proposal
        next.slots = slots
        return next
    }

    /// Lock or unlock a single slot. Regeneration only refills unlocked slots.
    public static func setLocked(
        _ locked: Bool,
        slotID: UUID,
        in proposal: RecipeMealPlanProposal
    ) -> RecipeMealPlanProposal {
        guard let index = proposal.slots.firstIndex(where: { $0.id == slotID }) else {
            return proposal
        }
        var slots = proposal.slots
        slots[index].isLocked = locked
        var next = proposal
        next.slots = slots
        return next
    }

    // MARK: - Apply reconciliation

    /// Dinners already on the calendar for any assigned proposal date.
    public static func conflictingMeals(
        _ proposal: RecipeMealPlanProposal,
        existingMeals: [MealPlanEntry],
        calendar: Calendar = .current
    ) -> [MealPlanEntry] {
        let assignedDates = Set(
            proposal.slots.compactMap { slot in
                slot.recipeID.map { _ in calendar.startOfDay(for: slot.date) }
            })
        return existingMeals.filter {
            $0.slot == .dinner && assignedDates.contains(calendar.startOfDay(for: $0.date))
        }
    }

    /// Pure apply: returns the resulting meal plan without mutating the store. The
    /// caller is responsible for the atomic write; cancel is simply not calling this.
    public static func apply(
        _ proposal: RecipeMealPlanProposal,
        existingMeals: [MealPlanEntry],
        policy: RecipeMealPlanApplyPolicy,
        calendar: Calendar = .current
    ) -> [MealPlanEntry] {
        var result = existingMeals

        for slot in proposal.slots {
            guard let recipeID = slot.recipeID else { continue }
            let day = calendar.startOfDay(for: slot.date)
            let occupiedIndices = result.indices.filter {
                result[$0].slot == .dinner && calendar.isDate(result[$0].date, inSameDayAs: day)
            }
            switch (occupiedIndices.isEmpty, policy) {
            case (true, _):
                result.append(MealPlanEntry(recipeID: recipeID, date: day, slot: .dinner))
            case (false, .replaceExisting):
                for index in occupiedIndices.sorted(by: >) {
                    result.remove(at: index)
                }
                result.append(MealPlanEntry(recipeID: recipeID, date: day, slot: .dinner))
            case (false, .fillEmptySlotsOnly):
                continue
            }
        }

        result.sort { $0.date < $1.date }
        return result
    }

    // MARK: - Helpers

    private static func normalizeDates(_ dates: [Date], calendar: Calendar) -> [Date] {
        var seen = Set<Date>()
        return dates
            .map { calendar.startOfDay(for: $0) }
            .filter { seen.insert($0).inserted }
            .sorted()
    }

    private static func reason(
        for recipeID: UUID?,
        recipeByID: [UUID: Recipe],
        maxTotalMinutes: Int?
    ) -> RecipeMealPlanReason {
        guard let recipeID, let recipe = recipeByID[recipeID] else {
            return .insufficientCandidates
        }
        if maxTotalMinutes == nil && recipe.totalMinutes == nil {
            return .timeUnknown
        }
        return .assigned
    }
}
