import SwiftUI

struct GroceriesView: View {
    @Environment(CookStore.self) private var store
    @State private var editing: GroceryRecord?
    @State private var failure: String?
    private var items: [GroceryRecord] { store.snapshot.groceries }

    var body: some View {
        List {
            if let loadError = store.loadError {
                Section {
                    InlineFailure(message: loadError)
                    Button("Try again") { store.reload() }
                }
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label("Your grocery list is empty", systemImage: "cart")
                } description: {
                    Text("Add ingredients from a recipe to start your list.")
                }
            } else {
                Section {
                    Text("\(items.filter { !$0.checked }.count) items to buy")
                        .font(CookTheme.heading(.title2))
                    Text("From \(Set(items.flatMap(\.sourceRecipeIDs)).count) recipes")
                        .foregroundStyle(.secondary)
                }
                grocerySection("To buy", checked: false)
                grocerySection("Bought", checked: true)
            }
            if let failure { Section { InlineFailure(message: failure) } }
        }
        .scrollContentBackground(.hidden).background(CookTheme.paper)
        .navigationTitle("Groceries")
        .sheet(item: $editing) { item in NavigationStack { GroceryEditorView(item: item) } }
    }

    @ViewBuilder private func grocerySection(_ title: String, checked: Bool) -> some View {
        let matching = items.filter { $0.checked == checked }
        if !matching.isEmpty {
            Section(LocalizedStringKey(title)) {
                ForEach(matching) { item in
                    HStack(alignment: .top, spacing: 16) {
                        Button {
                            do { try store.toggleGrocery(item.id) } catch { failure = error.localizedDescription }
                        } label: {
                            Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                                .font(.title2).frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain).accessibilityLabel(item.checked ? String(localized: "Mark \(item.name) not bought") : String(localized: "Mark \(item.name) bought"))
                        Button {
                            editing = item
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).strikethrough(item.checked)
                                Text(item.summary).font(.subheadline).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct GroceryEditorView: View {
    @Environment(CookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var item: GroceryRecord
    @State private var failure: String?
    var body: some View {
        Form {
            TextField("Ingredient", text: $item.name)
            TextField("Amount or note", text: $item.amount)
            TextField("Unit", text: $item.unit)
            if let failure { InlineFailure(message: failure) }
        }
        .navigationTitle("Edit grocery item").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do { try store.updateGrocery(item); dismiss() } catch { failure = error.localizedDescription }
                }.disabled(item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
