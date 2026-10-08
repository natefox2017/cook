import CookCore
import SwiftUI

struct MealPlanView: View {
    @Environment(CookStore.self) private var store
    @State private var selectedDate = Date()
    @State private var recipePicker: MealPlanPickerPresentation?
    @State private var mealToDelete: MealPlanEntry?
    @State private var errorMessage: String?

    private let calendar = Calendar.current

    private var weekDates: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start
            ?? calendar.startOfDay(for: selectedDate)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekDescription: String {
        guard let start = weekDates.first, let end = weekDates.last else { return "This week" }
        return "\(englishDate(start, format: "MMM d")) – \(englishDate(end, format: "MMM d, yyyy"))"
    }

    private var weeklyMealCount: Int {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else { return 0 }
        return store.mealPlan.filter { $0.date >= interval.start && $0.date < interval.end }.count
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Button("Previous week", systemImage: "chevron.left") { moveWeek(by: -1) }
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                        Spacer(minLength: 0)
                        Text(weekDescription)
                            .font(CookTheme.text(15, weight: .semibold, relativeTo: .subheadline))
                            .multilineTextAlignment(.center)
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
                    HStack {
                        Text("\(weeklyMealCount) \(weeklyMealCount == 1 ? "meal" : "meals") planned this week")
                            .font(CookTheme.text(13, weight: .regular, relativeTo: .footnote))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    DatePicker("Choose a date", selection: $selectedDate, displayedComponents: .date)
                        .font(CookTheme.text(15, weight: .regular, relativeTo: .subheadline))
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
                            "\(entries(for: slot).isEmpty ? "Add" : "Change") \(slot.rawValue.lowercased())",
                            systemImage: entries(for: slot).isEmpty ? "plus.circle" : "arrow.triangle.2.circlepath"
                        )
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("mealplan.add.\(slot.rawValue.lowercased())")
                } header: {
                    Text(slot.rawValue).textCase(nil).font(CookTheme.text(17, weight: .semibold, relativeTo: .headline))
                }
                .listRowBackground(CookTheme.card)
            }

            Section {
                Text("Choose from your saved recipes. Open a planned recipe when you’re ready to cook or add its ingredients to Groceries.")
                    .font(CookTheme.text(13, weight: .regular, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(CookSpacing.medium)
        .scrollContentBackground(.hidden)
        .background(CookTheme.canvas)
        .navigationTitle("Meal Plan").navigationBarTitleDisplayMode(.large)
        .tint(CookTheme.accent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { selectedDate = Date() }
            }
        }
        .sheet(item: $recipePicker) { presentation in
            MealPlanRecipePicker(date: presentation.date, slot: presentation.slot)
        }
        .confirmationDialog("Remove planned meal?", isPresented: Binding(
            get: { mealToDelete != nil }, set: { if !$0 { mealToDelete = nil } }
        ), titleVisibility: .visible) {
            if let entry = mealToDelete {
                Button("Remove meal", role: .destructive) {
                    do { try store.deleteMeal(id: entry.id) }
                    catch { errorMessage = error.localizedDescription }
                    mealToDelete = nil
                }
            }
        } message: {
            Text("The recipe will stay in your saved recipes.")
        }
        .alert("Couldn’t update meal plan", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Please try again.") }
    }

    private func dayButton(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let hasMeals = store.mealPlan.contains { calendar.isDate($0.date, inSameDayAs: date) }
        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 7) {
                Text(englishDate(date, format: "EEE"))
                    .font(CookTheme.text(12, weight: .regular, relativeTo: .caption))
                Text(englishDate(date, format: "d"))
                    .font(CookTheme.text(20, weight: .semibold, relativeTo: .title3))
                Circle()
                    .fill(hasMeals ? (selected ? Color.white : CookTheme.accent) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(minWidth: 44)
            .padding(.horizontal, 5)
            .padding(.vertical, 10)
            .background(selected ? CookTheme.accent : CookTheme.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(englishDate(date, format: "EEEE, MMMM d, yyyy"))
        .accessibilityValue("\(selected ? "Selected. " : "")\(hasMeals ? "Meals planned" : "No meals planned")")
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.title).font(CookTheme.text(17, weight: .semibold, relativeTo: .body))
                            if let minutes = recipe.totalMinutes {
                                Label("\(minutes) min", systemImage: "clock")
                                    .font(CookTheme.text(12, weight: .regular, relativeTo: .caption))
                                    .foregroundStyle(.secondary)
                            }
                            if recipe.needsReview {
                                Text("Needs review").font(CookTheme.text(12, weight: .regular, relativeTo: .caption)).foregroundStyle(.secondary)
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
            Button("Remove from plan", systemImage: "trash", role: .destructive) { mealToDelete = entry }
        }
    }

    private func entries(for slot: MealSlot) -> [MealPlanEntry] {
        store.mealPlan.filter { $0.slot == slot && calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private func moveWeek(by count: Int) {
        if let date = calendar.date(byAdding: .weekOfYear, value: count, to: selectedDate) {
            selectedDate = date
        }
    }
}

private func englishDate(_ date: Date, format: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en")
    formatter.dateFormat = format
    return formatter.string(from: date)
}

private struct MealPlanPickerPresentation: Identifiable {
    let id = UUID()
    let date: Date
    let slot: MealSlot
}

private struct MealPlanRecipePicker: View {
    @Environment(CookStore.self) private var store
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
                                    if hasPlannedMeal { replacementRecipe = recipe }
                                    else { save(recipe) }
                                } label: {
                                    HStack(spacing: 12) {
                                        RecipeImage(recipe: recipe, height: 60)
                                            .frame(width: 60, height: 60)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(recipe.title).foregroundStyle(.primary)
                                            if alreadyAdded {
                                                Text("Already planned").font(CookTheme.text(12, weight: .regular, relativeTo: .caption)).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: alreadyAdded ? "checkmark.circle.fill" : "plus.circle")
                                            .foregroundStyle(CookTheme.accentForeground)
                                    }
                                    .frame(minHeight: 60)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(alreadyAdded)
                            }
                        } header: {
                            Text("\(slot.rawValue) · \(englishDate(date, format: "MMM d, yyyy"))")
                                .textCase(nil)
                        }
                        .listRowBackground(CookTheme.card)
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
            .background(CookTheme.canvas)
            .navigationTitle("Choose a Recipe").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .confirmationDialog("Replace planned meal?", isPresented: Binding(
                get: { replacementRecipe != nil }, set: { if !$0 { replacementRecipe = nil } }
            ), titleVisibility: .visible) {
                if let recipe = replacementRecipe {
                    Button("Replace with \(recipe.title)") {
                        save(recipe)
                        replacementRecipe = nil
                    }
                }
            } message: {
                Text("This changes \(slot.rawValue.lowercased()) for \(englishDate(date, format: "MMM d, yyyy")). Both recipes stay in your library.")
            }
            .alert("Couldn’t plan recipe", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Please try again.") }
        }
        .tint(CookTheme.accent)
    }

    private var hasPlannedMeal: Bool {
        store.mealPlan.contains { $0.slot == slot && Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    private func save(_ recipe: Recipe) {
        do {
            try store.upsertMeal(MealPlanEntry(
                recipeID: recipe.id,
                date: Calendar.current.startOfDay(for: date),
                slot: slot
            ))
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
