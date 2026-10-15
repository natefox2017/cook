// Developer: gengyun
// Purpose: Generates and previews a deterministic weekly dinner plan from the private library.

import RecipeCore
import SwiftUI

struct MealPlanGeneratorSheet: View {
    @Environment(RecipeStore.self) private var store
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @AppStorage(RecipeUITestNamespace.preferenceKey("recipe.meal.weekStart"))
    private var weekStart = "System Default"

    @State private var selectedDates: Set<Date> = []
    @State private var limitTime = false
    @State private var maxTotalMinutes = 60
    @State private var selectedTags: Set<String> = []
    @State private var seed: UInt64 = 0
    @State private var proposal: RecipeMealPlanProposal?
    @State private var replaceSlot: RecipeMealPlanSlot?
    @State private var showConflictDialog = false
    @State private var errorMessage: String?

    private var calendar: Calendar {
        RecipeWeekCalendar.configured(weekStart: weekStart)
    }

    private var weekDates: [Date] {
        RecipeMealPlanGenerator.dinnerDates(weekContaining: Date(), calendar: calendar)
    }

    private var availableTags: [String] {
        RecipeMealPlanGenerator.normalizeTags(store.recipes.flatMap { $0.dietaryTags ?? [] })
            .sorted()
    }

    var body: some View {
        NavigationStack {
            Group {
                if let proposal {
                    preview(proposal)
                } else {
                    config
                }
            }
            .navigationTitle("Auto Plan")
            .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(RecipeTheme.accent)
        .onAppear(perform: seedDefaultsIfNeeded)
        .sheet(item: $replaceSlot) { slot in
            if let proposal {
                MealPlanCandidatePicker(slot: slot, proposal: proposal) { recipeID in
                    self.proposal = RecipeMealPlanGenerator.replace(
                        in: proposal, slotID: slot.id, recipeID: recipeID)
                }
            }
        }
        .confirmationDialog(
            "Some dinners already have a planned meal.",
            isPresented: $showConflictDialog,
            titleVisibility: .visible
        ) {
            Button("Fill empty days only") {
                applyCurrentProposal(policy: .fillEmptySlotsOnly)
            }
            Button("Replace existing dinners", role: .destructive) {
                applyCurrentProposal(policy: .replaceExisting)
            }
        } message: {
            Text("Choose how to handle days that already have a planned dinner.")
        }
        .alert(
            "Couldn’t apply plan",
            isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    // MARK: - Config

    private var config: some View {
        Form {
            Section("Dinner days") {
                ForEach(weekDates, id: \.self) { date in
                    Button {
                        toggle(date)
                    } label: {
                        HStack {
                            Text(dayLabel(date)).foregroundStyle(.primary)
                            Spacer()
                            if selectedDates.contains(date) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(RecipeTheme.accent)
                            }
                        }
                    }
                }
            }
            Section {
                Toggle("Limit total time", isOn: $limitTime)
                if limitTime {
                    Stepper(
                        "Up to \(maxTotalMinutes) minutes",
                        value: $maxTotalMinutes, in: 10...240, step: 5)
                }
                if !availableTags.isEmpty {
                    ForEach(availableTags, id: \.self) { tag in
                        Button {
                            toggleTag(tag)
                        } label: {
                            HStack {
                                Text(tag.capitalized).foregroundStyle(.primary)
                                Spacer()
                                if selectedTags.contains(tag) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(RecipeTheme.accent)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Options")
            } footer: {
                Text("A recipe must match every selected tag. Tags never guarantee allergy safety.")
            }
            Section {
                Button("Generate plan") { generate() }
                    .disabled(selectedDates.isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
    }

    // MARK: - Preview

    private func preview(_ proposal: RecipeMealPlanProposal) -> some View {
        List {
            Section {
                ForEach(proposal.slots) { slot in
                    slotRow(slot)
                }
            } footer: {
                if !proposal.skipped.isEmpty {
                    Text(skippedSummary(proposal))
                }
            }
            Section {
                Button("Regenerate unlocked meals") { regenerate() }
            }
            Section {
                Button("Apply plan") { requestApply() }
                    .disabled(!proposal.slots.contains { $0.recipeID != nil })
            }
        }
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
    }

    private func slotRow(_ slot: RecipeMealPlanSlot) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: RecipeSpacing.xxSmall) {
                Text(dayLabel(slot.date))
                    .font(RecipeTheme.text(12, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                if let recipeID = slot.recipeID, let recipe = store.recipe(id: recipeID) {
                    Text(recipe.title)
                        .font(RecipeTheme.text(16, weight: .semibold, relativeTo: .body))
                    Text(reasonText(slot.reason))
                        .font(RecipeTheme.text(12, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                } else {
                    Text(emptyText(slot.reason))
                        .font(RecipeTheme.text(15, weight: .regular, relativeTo: .body))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if slot.recipeID != nil {
                Button {
                    toggleLock(slot)
                } label: {
                    Image(systemName: slot.isLocked ? "lock.fill" : "lock.open")
                }
                .accessibilityLabel(slot.isLocked ? "Unlock meal" : "Lock meal")
                Button {
                    replaceSlot = slot
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .accessibilityLabel("Replace meal")
            }
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Actions

    private func seedDefaultsIfNeeded() {
        if selectedDates.isEmpty && proposal == nil {
            selectedDates = Set(weekDates)
        }
        if seed == 0 {
            let interval = weekDates.first?.timeIntervalSinceReferenceDate ?? 0
            seed = interval > 0 ? UInt64(interval) : 0
        }
    }

    private func generate() {
        let dates = weekDates.filter { selectedDates.contains($0) }.sorted()
        proposal = RecipeMealPlanGenerator.generate(
            recipes: store.recipes,
            dates: dates,
            seed: seed,
            maxTotalMinutes: limitTime ? maxTotalMinutes : nil,
            dietaryTags: Array(selectedTags),
            calendar: calendar)
    }

    private func regenerate() {
        guard let current = proposal else { return }
        seed &+= 1
        proposal = RecipeMealPlanGenerator.regenerate(current, recipes: store.recipes, seed: seed)
    }

    private func requestApply() {
        guard let current = proposal else { return }
        let conflicts = RecipeMealPlanGenerator.conflictingMeals(
            current, existingMeals: store.mealPlan, calendar: calendar)
        if conflicts.isEmpty {
            applyCurrentProposal(policy: .fillEmptySlotsOnly)
        } else {
            showConflictDialog = true
        }
    }

    private func applyCurrentProposal(policy: RecipeMealPlanApplyPolicy) {
        guard let current = proposal else { return }
        do {
            for slot in current.slots {
                guard let recipeID = slot.recipeID else { continue }
                let occupied = store.mealPlan.contains {
                    $0.slot == .dinner && calendar.isDate($0.date, inSameDayAs: slot.date)
                }
                if occupied && policy == .fillEmptySlotsOnly { continue }
                try store.upsertMeal(
                    MealPlanEntry(recipeID: recipeID, date: slot.date, slot: .dinner))
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggle(_ date: Date) {
        if selectedDates.contains(date) {
            selectedDates.remove(date)
        } else {
            selectedDates.insert(date)
        }
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    private func toggleLock(_ slot: RecipeMealPlanSlot) {
        guard let current = proposal else { return }
        proposal = RecipeMealPlanGenerator.setLocked(
            !slot.isLocked, slotID: slot.id, in: current)
    }

    // MARK: - Copy

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return formatter.string(from: date)
    }

    private func reasonText(_ reason: RecipeMealPlanReason) -> String {
        switch reason {
        case .assigned: return filterSummary.isEmpty ? "From your saved recipes" : filterSummary
        case .timeUnknown: return "Time unknown"
        case .locked: return "Locked"
        case .insufficientCandidates: return "No matching recipe"
        case .lockedRecipeDeleted: return "Locked recipe was deleted"
        }
    }

    private func emptyText(_ reason: RecipeMealPlanReason) -> String {
        switch reason {
        case .lockedRecipeDeleted: return "Locked recipe was deleted — pick a replacement"
        case .insufficientCandidates: return "No matching recipe left"
        default: return "No recipe"
        }
    }

    private var filterSummary: String {
        var parts: [String] = []
        if !selectedTags.isEmpty { parts.append("Matches selected tags") }
        if limitTime { parts.append("Up to \(maxTotalMinutes) min") }
        return parts.joined(separator: " · ")
    }

    private func skippedSummary(_ proposal: RecipeMealPlanProposal) -> String {
        let missingDuration = proposal.skipped.values.filter { $0 == .missingDuration }.count
        let overBudget = proposal.skipped.values.filter { $0 == .exceedsDuration }.count
        let missingTag = proposal.skipped.values.filter { $0 == .missingDietaryTag }.count
        let incomplete = proposal.skipped.values.filter { $0 == .missingIngredientsOrSteps }.count
        var parts: [String] = []
        if incomplete > 0 { parts.append("\(incomplete) incomplete") }
        if missingDuration > 0 { parts.append("\(missingDuration) missing time") }
        if overBudget > 0 { parts.append("\(overBudget) over the time limit") }
        if missingTag > 0 { parts.append("\(missingTag) missing a tag") }
        return parts.isEmpty ? "Some recipes were skipped." : "Skipped: \(parts.joined(separator: ", "))."
    }
}

private struct MealPlanCandidatePicker: View {
    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let slot: RecipeMealPlanSlot
    let proposal: RecipeMealPlanProposal
    let onPick: (UUID) -> Void

    var body: some View {
        NavigationStack {
            List(proposal.candidateIDs, id: \.self) { recipeID in
                if let recipe = store.recipe(id: recipeID) {
                    let used = proposal.slots.contains {
                        $0.id != slot.id && $0.recipeID == recipeID
                    }
                    Button {
                        onPick(recipeID)
                        dismiss()
                    } label: {
                        HStack {
                            Text(recipe.title).foregroundStyle(.primary)
                            Spacer()
                            if used {
                                Text("Already planned")
                                    .font(RecipeTheme.text(12, weight: .regular, relativeTo: .caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(used)
                }
            }
            .navigationTitle("Replace dinner")
            .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(RecipeTheme.accent)
    }
}
