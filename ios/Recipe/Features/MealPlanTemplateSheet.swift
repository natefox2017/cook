// Developer: gengyun
// Purpose: Presents weekly meal-plan templates for saving, previewing, applying, renaming, and deleting.

import RecipeCore
import SwiftUI

private struct WeeklyTemplatesGateKey: EnvironmentKey {
    static let defaultValue: any RecipeWeeklyTemplatesGate = RecipeWeeklyTemplatesAccess()
}

extension EnvironmentValues {
    var weeklyTemplatesGate: any RecipeWeeklyTemplatesGate {
        get { self[WeeklyTemplatesGateKey.self] }
        set { self[WeeklyTemplatesGateKey.self] = newValue }
    }
}

/// Standalone template manager. Saving, applying, renaming, and deleting are
/// gated by the injected weekly-templates capability; viewing stays available
/// so an expired subscription never hides already saved templates.
struct MealPlanTemplateSheet: View {
    @Environment(RecipeStore.self) private var store
    @Environment(RecipeMealPlanTemplateStore.self) private var templateStore
    @Environment(\.weeklyTemplatesGate) private var gate
    @Environment(\.dismiss) private var dismiss

    let weekStart: Date
    let calendar: Calendar

    @State private var errorMessage: String?
    @State private var isSavingTemplate = false
    @State private var templateToRename: RecipeMealPlanTemplate?
    @State private var templateToDelete: RecipeMealPlanTemplate?
    @State private var templateToApply: RecipeMealPlanTemplate?
    @State private var applySummary: String?

    private var canManage: Bool {
        gate.canManageWeeklyTemplates()
    }

    private var weekDates: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// The currently visible week's occupied slots, mapped to 0...6 offsets.
    private var currentWeekSlots: [RecipeMealPlanTemplateSlot] {
        var slots: [RecipeMealPlanTemplateSlot] = []
        for (offset, date) in weekDates.enumerated() {
            for slot in MealSlot.allCases {
                if let entry = store.mealPlan.first(where: {
                    $0.slot == slot && calendar.isDate($0.date, inSameDayAs: date)
                }) {
                    slots.append(
                        RecipeMealPlanTemplateSlot(
                            relativeDayOffset: offset,
                            mealSlot: slot,
                            recipeID: entry.recipeID
                        )
                    )
                }
            }
        }
        return slots
    }

    var body: some View {
        NavigationStack {
            Group {
                if templateStore.templates.isEmpty {
                    EmptyStateView(
                        title: "No saved templates",
                        message: "Plan a week, then save it as a reusable template.",
                        systemImage: "square.grid.2x2",
                        actionTitle: canManage ? "Save This Week" : nil,
                        action: canManage ? { isSavingTemplate = true } : nil,
                        messageLineLimit: 2
                    )
                } else {
                    templateList
                }
            }
            .background(RecipeTheme.canvas)
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if canManage {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save Week") { isSavingTemplate = true }
                            .disabled(currentWeekSlots.isEmpty)
                            .accessibilityIdentifier("mealplan.templates.saveWeek")
                    }
                }
            }
        }
        .tint(RecipeTheme.accent)
        .sheet(isPresented: $isSavingTemplate) {
            TemplateNameSheet(
                title: "Save Template",
                initialName: "",
                placeholder: "Template name"
            ) { name in
                try saveCurrentWeek(named: name)
            }
        }
        .sheet(item: $templateToRename) { template in
            TemplateNameSheet(
                title: "Rename Template",
                initialName: template.name,
                placeholder: "Template name"
            ) { name in
                try templateStore.renameTemplate(id: template.id, name: name)
            }
        }
        .confirmationDialog(
            "Delete template?",
            isPresented: Binding(
                get: { templateToDelete != nil },
                set: { if !$0 { templateToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let template = templateToDelete {
                Button("Delete template", role: .destructive) {
                    delete(template)
                }
            }
        } message: {
            Text("Your saved recipes and any applied plans stay unchanged.")
        }
        .confirmationDialog(
            "Apply template",
            isPresented: Binding(
                get: { templateToApply != nil },
                set: { if !$0 { templateToApply = nil } }
            ),
            titleVisibility: .visible
        ) {
            if templateToApply != nil {
                Button("Fill empty slots") { apply(.fillEmptySlotsOnly) }
                if applyPreview?.hasConflicts == true {
                    Button("Replace conflicts") { apply(.replaceExisting) }
                }
                Button("Cancel", role: .cancel) { templateToApply = nil }
            }
        } message: {
            Text(applyDialogMessage)
        }
        .alert(
            "Templates",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            "Template applied",
            isPresented: Binding(
                get: { applySummary != nil },
                set: { if !$0 { applySummary = nil } }
            )
        ) {
            Button("Done") { dismiss() }
        } message: {
            Text(applySummary ?? "")
        }
    }

    private var templateList: some View {
        List {
            Section {
                ForEach(templateStore.templates) { template in
                    templateRow(template)
                }
            } footer: {
                Text("Templates are saved on this device.")
                    .font(RecipeTheme.text(13, weight: .regular, relativeTo: .footnote))
            }
        }
        .recipeRootScrollClearance()
        .listStyle(.insetGrouped)
        .contentMargins(.top, RecipeSpacing.pageTop, for: .scrollContent)
        .listSectionSpacing(RecipeSpacing.medium)
        .scrollContentBackground(.hidden)
    }

    private func templateRow(_ template: RecipeMealPlanTemplate) -> some View {
        Button {
            beginApply(template)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: RecipeSpacing.xxSmall) {
                    Text(template.name)
                        .font(RecipeTheme.text(17, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(.primary)
                    Text(summary(for: template))
                        .font(RecipeTheme.text(13, weight: .regular, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if canManage {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(RecipeTheme.accentForeground)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canManage)
        .listRowBackground(RecipeTheme.card)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canManage {
                Button("Rename") { templateToRename = template }
                Button("Delete", role: .destructive) { templateToDelete = template }
            }
        }
        .contextMenu {
            if canManage {
                Button("Rename", systemImage: "pencil") { templateToRename = template }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    templateToDelete = template
                }
            }
        }
    }

    private func summary(for template: RecipeMealPlanTemplate) -> String {
        let count = template.slots.count
        return count == 1 ? "1 meal" : "\(count) meals"
    }

    private func saveCurrentWeek(named name: String) throws {
        try templateStore.saveTemplate(name: name, slots: currentWeekSlots)
    }

    private func delete(_ template: RecipeMealPlanTemplate) {
        do {
            try templateStore.deleteTemplate(id: template.id)
            templateToDelete = nil
        } catch {
            errorMessage = error.localizedDescription
            templateToDelete = nil
        }
    }

    private func beginApply(_ template: RecipeMealPlanTemplate) {
        let preview = store.previewMealTemplate(
            template, startingAt: weekStart, calendar: calendar
        )
        if preview.totalSlots > 0 && preview.missingRecipeCount == preview.totalSlots {
            errorMessage = "None of this template's recipes are in your library anymore."
            return
        }
        templateToApply = template
    }

    private var applyPreview: MealTemplatePreview? {
        guard let templateToApply else { return nil }
        return store.previewMealTemplate(
            templateToApply, startingAt: weekStart, calendar: calendar
        )
    }

    private var applyDialogMessage: String {
        guard let preview = applyPreview else { return "" }
        var parts: [String] = []
        if preview.hasMissingRecipes {
            parts.append("\(preview.missingRecipeCount) recipe missing")
        }
        if preview.hasConflicts {
            parts.append("\(preview.conflicts.count) slot already planned")
        }
        if parts.isEmpty {
            return "This adds \(preview.totalSlots) meal(s) to your week."
        }
        return parts.joined(separator: " · ")
    }

    private func apply(_ policy: RecipeMealPlanApplyPolicy) {
        guard let template = templateToApply else { return }
        do {
            let result = try store.applyMealTemplate(
                template, startingAt: weekStart, calendar: calendar, policy: policy
            )
            templateToApply = nil
            applySummary = applySummaryText(result)
        } catch {
            templateToApply = nil
            errorMessage = error.localizedDescription
        }
    }

    private func applySummaryText(_ result: MealTemplateApplyResult) -> String {
        var parts = ["Added \(result.appliedSlots) meal(s)."]
        if result.skippedConflicts > 0 {
            parts.append("\(result.skippedConflicts) already-planned slot kept.")
        }
        if result.skippedMissingRecipes > 0 {
            parts.append("\(result.skippedMissingRecipes) recipe no longer available.")
        }
        return parts.joined(separator: " ")
    }
}

/// Collects a validated template name for either a new save or a rename.
private struct TemplateNameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let placeholder: String
    let onSave: (String) throws -> Void

    @State private var name: String
    @State private var errorMessage: String?

    init(
        title: String,
        initialName: String,
        placeholder: String,
        onSave: @escaping (String) throws -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(placeholder, text: $name)
                    .textInputAutocapitalization(.words)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(
                "Template",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(RecipeTheme.accent)
    }

    private func save() {
        do {
            try onSave(name)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
