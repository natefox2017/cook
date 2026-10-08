// Developer: gengyun
// Purpose: Provides the legacy RecipeApp weekly meal planning interface.

import SwiftUI

struct MealPlanView: View {
    @Environment(AppStore.self) private var store

    @State private var weekOffset = 0
    @State private var pickingDate: Date?
    @State private var meal = "Dinner"

    private var start: Date {
        let calendar = Calendar.current
        let currentWeek = calendar.date(
            byAdding: .weekOfYear,
            value: weekOffset,
            to: Date()
        )!
        return calendar.dateInterval(
            of: .weekOfYear,
            for: currentWeek
        )!.start
    }

    private var days: [Date] {
        (0..<7).compactMap {
            Calendar.current.date(
                byAdding: .day,
                value: $0,
                to: start
            )
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Button {
                        weekOffset -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                    }

                    Spacer()

                    Text(
                        start.formatted(.dateTime.month().day())
                            + " – "
                            + days.last!.formatted(.dateTime.month().day())
                    )

                    Spacer()

                    Button {
                        weekOffset += 1
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
            }

            ForEach(days, id: .self) { day in
                Section(
                    day.formatted(
                        .dateTime.weekday(.wide).month().day()
                    )
                ) {
                    ForEach(
                        store.mealPlan.filter {
                            $0.date.sameDay(as: day)
                        }
                    ) { entry in
                        if let recipe = store.recipes.first(
                            where: { $0.id == entry.recipeID }
                        ) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(recipe.title)
                                    Text(
                                        "(entry.meal) · "
                                            + "(entry.servings) servings"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    store.unplan(entry.id)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                }
                            }
                        }
                    }

                    Button {
                        pickingDate = day
                    } label: {
                        Label("Add meal", systemImage: "plus")
                    }
                }
            }
        }
        .navigationTitle("Meal Plan")
        .sheet(item: $pickingDate) { date in
            NavigationStack {
                List {
                    Picker("Meal", selection: $meal) {
                        ForEach(
                            ["Breakfast", "Lunch", "Dinner", "Snack"],
                            id: .self
                        ) {
                            Text($0)
                        }
                    }

                    ForEach(store.recipes) { recipe in
                        Button(recipe.title) {
                            store.plan(
                                recipeID: recipe.id,
                                date: date,
                                meal: meal,
                                servings: recipe.servings
                            )
                            pickingDate = nil
                        }
                    }
                }
                .navigationTitle("Choose Recipe")
            }
        }
    }
}

extension Date: @retroactive Identifiable {
    public var id: Double {
        timeIntervalSinceReferenceDate
    }
}
