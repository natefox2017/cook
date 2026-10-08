// Developer: gengyun
// Purpose: Provides the legacy RecipeApp grocery list interface.

import SwiftUI

struct GroceriesView: View {
    @Environment(AppStore.self) private var store

    @State private var hidesChecked = false
    @State private var newItem = ""

    private var items: [GroceryItem] {
        hidesChecked
            ? store.groceries.filter { !$0.checked }
            : store.groceries
    }

    private var groups: [String: [GroceryItem]] {
        Dictionary(grouping: items, by: \.aisle)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Add an item", text: $newItem)
                        .submitLabel(.done)
                        .onSubmit(addItem)

                    Button(action: addItem) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(
                        newItem.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                }
            }

            if items.isEmpty {
                ContentUnavailableView(
                    "Your list is empty",
                    systemImage: "cart",
                    description: Text(
                        "Add an item or ingredients from a recipe."
                    )
                )
            } else {
                ForEach(groups.keys.sorted(), id: \.self) { aisle in
                    Section(aisle) {
                        ForEach(groups[aisle] ?? []) { item in
                            Button {
                                store.toggleGrocery(item.id)
                            } label: {
                                HStack {
                                    Image(
                                        systemName: item.checked
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                    )
                                    .foregroundStyle(RecipeTheme.green)

                                    VStack(alignment: .leading) {
                                        Text(item.name)
                                            .foregroundStyle(.primary)

                                        HStack {
                                            if !item.amount.isEmpty {
                                                Text(item.amount)
                                            }

                                            if
                                                let recipeID = item.recipeID,
                                                let recipe = store.recipes.first(
                                                    where: { $0.id == recipeID }
                                                )
                                            {
                                                Text("· \(recipe.title)")
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Groceries")
        .toolbar {
            Menu {
                Toggle("Hide checked", isOn: $hidesChecked)

                Button("Add this week’s meal plan") {
                    store.addPlannedGroceries()
                }

                Button("Clear checked", role: .destructive) {
                    store.clearChecked()
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
    }

    private func addItem() {
        store.addManualGrocery(newItem)
        newItem = ""
    }
}
