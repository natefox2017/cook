// Developer: gengyun
// Purpose: Provides the legacy RecipeApp profile and preference overview.

import SwiftUI

struct ProfileView: View {
    @Environment(AppStore.self) private var store

    @AppStorage("recipe.notifications") private var notifications = true
    @AppStorage("recipe.metric") private var metric = true
    @AppStorage("recipe.keepAwake") private var keepAwake = true

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(RecipeTheme.green)

                    VStack(alignment: .leading) {
                        Text("My RecipePouch")
                            .font(.title2.bold())
                        Text("(store.recipes.count) saved recipes")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Plan") {
                NavigationLink {
                    MealPlanView()
                } label: {
                    Label("Weekly Meal Plan", systemImage: "calendar")
                }
            }

            Section("Cooking") {
                Toggle(
                    "Keep screen awake while cooking",
                    isOn: $keepAwake
                )
                Toggle("Notifications", isOn: $notifications)
                Toggle("Metric units", isOn: $metric)
            }

            Section("Data") {
                LabeledContent(
                    "Recipes",
                    value: "(store.recipes.count)"
                )
                LabeledContent(
                    "Groceries",
                    value: "(store.groceries.count)"
                )
                LabeledContent(
                    "Planned meals",
                    value: "(store.mealPlan.count)"
                )
            }

            Section {
                NavigationLink("Privacy & Data") {
                    Text(
                        "Your recipes are stored locally in this prototype. "
                            + "Server sync follows the project privacy and RLS rules."
                    )
                    .padding()
                }

                NavigationLink("About RecipePouch") {
                    Text(
                        "RecipePouch turns recipes you find into a personal cookbook."
                    )
                    .padding()
                }
            }
        }
        .navigationTitle("Me")
    }
}
