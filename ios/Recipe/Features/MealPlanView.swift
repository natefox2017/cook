// Developer: gengyun
// Purpose: Implements weekly meal planning, recipe selection, replacement, and navigation.

import RecipeCore
import SwiftUI

struct MealPlanView: View {
    let titleDisplayMode: NavigationBarItem.TitleDisplayMode

    init(titleDisplayMode: NavigationBarItem.TitleDisplayMode = RecipeNavigation.rootTitleMode) {
        self.titleDisplayMode = titleDisplayMode
    }

    @Environment(RecipeStore.self) private var store
    @Environment(\.locale) private var locale
    @AppStorage(RecipeUITestNamespace.preferenceKey("recipe.meal.weekStart"))
    private var weekStart = "System Default"
    @State private var selectedDate = Date()
    @State private var recipePicker: MealPlanPickerPresentation?
    @State private var mealToDelete: MealPlanEntry?
    @State private var errorMessage: String?

    // Use the same configured calendar for date order, counts, and navigation.
    private var calendar: Calendar {
        RecipeWeekCalendar.configured(weekStart: weekStart)
    }

    private var weekDates: [Date] {
        let start =
            calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start
            ?? calendar.startOfDay(for: selectedDate)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekDescription: String {
        guard let start = weekDates.first, let end = weekDates.last else { return "This week" }
        return
            "\(localizedMealDate(start, template: "MMM d", locale: locale)) – \(localizedMealDate(end, template: "MMM d, yyyy", locale: locale))"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: RecipeSpacing.medium) {
                    HStack(spacing: 8) {
                        Button("Previous week", systemImage: "chevron.left") { moveWeek(by: -1) }
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                        Spacer(minLength: 0)
                        Text(weekDescription)
                            .font(RecipeTheme.text(15, weight: .semibold, relativeTo: .subheadline))
                            .multilineTextAlignment(.center)
                            .contentShape(Rectangle())
                            // This date-range gesture has priority over root tab navigation.
                            // Keep the horizontal seven-day ScrollView's drag untouched.
                            .gesture(
                                DragGesture(minimumDistance: 40)
                                    .onEnded { value in
                                        guard let direction = RecipeHorizontalSwipe(
                                            translation: value.translation,
                                            minimumDistance: 65
                                        ) else {
                                            return
                                        }
                                        moveWeek(by: direction == .next ? 1 : -1)
                                    }
                            )
                            .accessibilityIdentifier("mealplan.weekRange")
                        Spacer(minLength: 0)
                        Button("Next week", systemImage: "chevron.right") { moveWeek(by: 1) }
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(weekDates, id: \.self) { date in
                                dayButton(date)
                            }
                        }
                    }
                    DatePicker(
                        "Choose a date", selection: $selectedDate, displayedComponents: .date
                    )
                    .font(RecipeTheme.text(15, weight: .regular, relativeTo: .subheadline))
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))

            ForEach(MealSlot.allCases) { slot in
                Section {
                    ForEach(entries(for: slot)) { entry in
                        mealRow(entry)
                    }
                    Button {
                        recipePicker = MealPlanPickerPresentation(date: selectedDate, slot: slot)
                    } label: {
                        Label(
                            actionTitle(for: slot),
                            systemImage: entries(for: slot).isEmpty
                                ? "plus.circle" : "arrow.triangle.2.circlepath"
                        )
                        .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("mealplan.add.\(slot.rawValue.lowercased())")
                } header: {
                    Text(LocalizedStringKey(slot.rawValue)).textCase(nil).font(
                        RecipeTheme.text(17, weight: .semibold, relativeTo: .headline))
                }
                .listRowBackground(RecipeTheme.card)
            }

        }
        .recipeRootScrollClearance()
        .listStyle(.insetGrouped)
        .contentMargins(.top, RecipeSpacing.pageTop, for: .scrollContent)
        .listSectionSpacing(RecipeSpacing.medium)
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .navigationTitle("Meal Plan")
        .navigationBarTitleDisplayMode(titleDisplayMode)
        .tint(RecipeTheme.accent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { selectedDate = Date() }
            }
        }
        .sheet(item: $recipePicker) { presentation in
            MealPlanRecipePicker(date: presentation.date, slot: presentation.slot)
        }
        .confirmationDialog(
            "Remove planned meal?",
            isPresented: Binding(
                get: { mealToDelete != nil }, set: { if !$0 { mealToDelete = nil } }
            ), titleVisibility: .visible
        ) {
            if let entry = mealToDelete {
                Button("Remove meal", role: .destructive) {
                    do { try store.deleteMeal(id: entry.id) } catch {
                        errorMessage = error.localizedDescription
                    }
                    mealToDelete = nil
                }
            }
        } message: {
            Text("The recipe will stay in your saved recipes.")
        }
        .alert(
            "Couldn’t update meal plan",
            isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func dayButton(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let hasMeals = store.mealPlan.contains { calendar.isDate($0.date, inSameDayAs: date) }
        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: RecipeSpacing.xxSmall) {
                Text(localizedMealDate(date, template: "EEE", locale: locale))
                    .font(RecipeTheme.text(12, weight: .regular, relativeTo: .caption))
                Text(localizedMealDate(date, template: "d", locale: locale))
                    .font(RecipeTheme.text(20, weight: .semibold, relativeTo: .title3))
                Circle()
                    .fill(hasMeals ? (selected ? Color.white : RecipeTheme.accent) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .background(
                selected ? RecipeTheme.accent : RecipeTheme.card,
                in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localizedMealDate(date, template: "EEEE, MMMM d, yyyy", locale: locale))
        .accessibilityValue(
            selected
                ? LocalizedStringKey(
                    hasMeals ? "Selected. Meals planned" : "Selected. No meals planned")
                : LocalizedStringKey(hasMeals ? "Meals planned" : "No meals planned")
        )
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func mealRow(_ entry: MealPlanEntry) -> some View {
        Group {
            if let recipe = store.recipe(id: entry.recipeID) {
                NavigationLink {
                    RecipeDetailView(recipeID: recipe.id)
                } label: {
                    HStack(spacing: 12) {
                        RecipeImage(recipe: recipe, height: 66)
                            .frame(width: 66, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: RecipeSpacing.xxSmall) {
                            Text(recipe.title).font(
                                RecipeTheme.text(17, weight: .semibold, relativeTo: .body))
                            if let minutes = recipe.totalMinutes {
                                Label(
                                    Duration.seconds(minutes * 60).formatted(
                                        .units(width: .abbreviated, maximumUnitCount: 1).locale(
                                            locale)
                                    ),
                                    systemImage: "clock"
                                )
                                .font(RecipeTheme.text(12, weight: .regular, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                            }
                            if recipe.needsReview {
                                Text("Needs review").font(
                                    RecipeTheme.text(12, weight: .regular, relativeTo: .caption)
                                ).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            } else {
                Label("Recipe no longer available", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Remove", role: .destructive) { mealToDelete = entry }
        }
        .contextMenu {
            Button("Remove from plan", systemImage: "trash", role: .destructive) {
                mealToDelete = entry
            }
        }
    }

    private func entries(for slot: MealSlot) -> [MealPlanEntry] {
        store.mealPlan.filter {
            $0.slot == slot && calendar.isDate($0.date, inSameDayAs: selectedDate)
        }
    }

    private func actionTitle(for slot: MealSlot) -> String {
        let isAdding = entries(for: slot).isEmpty
        switch (slot, isAdding) {
        case (.breakfast, true):
            return String(
                localized: LocalizedStringResource("Add breakfast", locale: RecipeLanguage.active))
        case (.lunch, true):
            return String(
                localized: LocalizedStringResource("Add lunch", locale: RecipeLanguage.active))
        case (.dinner, true):
            return String(
                localized: LocalizedStringResource("Add dinner", locale: RecipeLanguage.active))
        case (.breakfast, false):
            return String(
                localized: LocalizedStringResource(
                    "Change breakfast", locale: RecipeLanguage.active))
        case (.lunch, false):
            return String(
                localized: LocalizedStringResource("Change lunch", locale: RecipeLanguage.active))
        case (.dinner, false):
            return String(
                localized: LocalizedStringResource("Change dinner", locale: RecipeLanguage.active))
        }
    }

    private func moveWeek(by count: Int) {
        if let date = calendar.date(byAdding: .weekOfYear, value: count, to: selectedDate) {
            selectedDate = date
        }
    }
}

// Date templates are resolved for the active SwiftUI locale, including the
// English UI-test override and the iPhone's preferred language in production.
private func localizedMealDate(_ date: Date, template: String, locale: Locale) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
}

private struct MealPlanPickerPresentation: Identifiable {
    let id = UUID()
    let date: Date
    let slot: MealSlot
}

private struct MealPlanRecipePicker: View {
    @Environment(RecipeStore.self) private var store
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var replacementRecipe: Recipe?
    @State private var errorMessage: String?
    let date: Date
    let slot: MealSlot

    private var recipes: [Recipe] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.recipes.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.recipes.isEmpty {
                    EmptyStateView(
                        title: "Save a recipe first",
                        message: "Your saved recipes will appear here, ready to add to your week.",
                        systemImage: "book.closed",
                        actionTitle: "Done",
                        action: { dismiss() }
                    )
                } else {
                    List {
                        Section {
                            ForEach(recipes) { recipe in
                                let alreadyAdded = store.mealPlan.contains {
                                    $0.recipeID == recipe.id && $0.slot == slot
                                        && Calendar.current.isDate($0.date, inSameDayAs: date)
                                }
                                Button {
                                    if hasPlannedMeal {
                                        replacementRecipe = recipe
                                    } else {
                                        save(recipe)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        RecipeImage(recipe: recipe, height: 60)
                                            .frame(width: 60, height: 60)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: RecipeSpacing.xxSmall)
                                        {
                                            Text(recipe.title).foregroundStyle(.primary)
                                            if alreadyAdded {
                                                Text("Already planned").font(
                                                    RecipeTheme.text(
                                                        12, weight: .regular, relativeTo: .caption)
                                                ).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(
                                            systemName: alreadyAdded
                                                ? "checkmark.circle.fill" : "plus.circle"
                                        )
                                        .foregroundStyle(RecipeTheme.accentForeground)
                                    }
                                    .frame(minHeight: 60)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(alreadyAdded)
                            }
                        } header: {
                            let dateLabel = localizedMealDate(
                                date,
                                template: "MMM d, yyyy",
                                locale: locale
                            )
                            Text(
                                String(
                                    localized: LocalizedStringResource(
                                        "\(localizedMealSlot(slot)) · \(dateLabel)",
                                        locale: locale
                                    )
                                )
                            )
                            .textCase(nil)
                        }
                        .listRowBackground(RecipeTheme.card)
                    }
                    .overlay {
                        if recipes.isEmpty {
                            EmptyStateView(
                                title: "No matching recipes",
                                message: "Try another recipe name.",
                                systemImage: "magnifyingglass"
                            )
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .searchable(text: $searchText, prompt: "Find a saved recipe")
                }
            }
            .background(RecipeTheme.canvas)
            .navigationTitle("Choose a Recipe")
            .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .confirmationDialog(
                "Replace planned meal?",
                isPresented: Binding(
                    get: { replacementRecipe != nil }, set: { if !$0 { replacementRecipe = nil } }
                ), titleVisibility: .visible
            ) {
                if let recipe = replacementRecipe {
                    Button("Replace with \(recipe.title)") {
                        save(recipe)
                        replacementRecipe = nil
                    }
                }
            } message: {
                let dateLabel = localizedMealDate(
                    date,
                    template: "MMM d, yyyy",
                    locale: locale
                )
                Text(
                    String(
                        localized: LocalizedStringResource(
                            "This changes \(localizedMealSlot(slot).lowercased(with: locale)) for \(dateLabel). Both recipes stay in your library.",
                            locale: locale
                        )
                    )
                )
            }
            .alert(
                "Couldn’t plan recipe",
                isPresented: Binding(
                    get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
        .tint(RecipeTheme.accent)
    }

    private var hasPlannedMeal: Bool {
        store.mealPlan.contains {
            $0.slot == slot && Calendar.current.isDate($0.date, inSameDayAs: date)
        }
    }

    private func localizedMealSlot(_ slot: MealSlot) -> String {
        return switch slot {
        case .breakfast: String(localized: LocalizedStringResource("Breakfast", locale: locale))
        case .lunch: String(localized: LocalizedStringResource("Lunch", locale: locale))
        case .dinner: String(localized: LocalizedStringResource("Dinner", locale: locale))
        }
    }

    private func save(_ recipe: Recipe) {
        do {
            try store.upsertMeal(
                MealPlanEntry(
                    recipeID: recipe.id,
                    date: Calendar.current.startOfDay(for: date),
                    slot: slot
                ))
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
