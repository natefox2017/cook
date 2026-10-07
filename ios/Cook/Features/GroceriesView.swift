import CookCore
import SwiftUI

struct GroceriesView: View {
    @Environment(CookStore.self) private var store
    @State private var filter: GroceryFilter = .all
    @State private var collapsedCategories: Set<String> = []
    @State private var editor: GroceryEditorPresentation?
    @State private var itemToDelete: GroceryItem?
    @State private var confirmsClear = false
    @State private var errorMessage: String?

    private var visibleItems: [GroceryItem] {
        store.groceries.filter { item in
            switch filter {
            case .all: true
            case .remaining: !item.isChecked
            case .purchased: item.isChecked
            }
        }
    }

    private var purchasedCount: Int { store.groceries.filter(\.isChecked).count }
    private var sourceCount: Int { Set(store.groceries.flatMap(\.recipeIDs)).count }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(store.groceries.count) items")
                                .font(CookTheme.title(25))
                            Text("From \(sourceCount) saved \(sourceCount == 1 ? "recipe" : "recipes")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(purchasedCount) bought")
                            .font(.subheadline)
                            .foregroundStyle(CookTheme.accent)
                    }
                    Picker("Grocery filter", selection: $filter) {
                        ForEach(GroceryFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("groceries.filter")
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))

            if store.groceries.isEmpty {
                emptyState(
                    title: "Your next shop starts here",
                    message: "Add ingredients from a recipe, or make a list of your own.",
                    actionTitle: "Add an item"
                ) { editor = GroceryEditorPresentation(item: nil) }
            } else if visibleItems.isEmpty {
                emptyState(
                    title: filter == .remaining ? "All picked up" : "Nothing checked off yet",
                    message: filter == .remaining
                        ? "Everything on your list is bought. You can add an item or view the full list."
                        : "Tap the circle beside an item as you shop.",
                    actionTitle: "Show all items"
                ) { filter = .all }
            } else {
                ForEach(GroceryCategory.allCases) { category in
                    let items = visibleItems.filter { $0.category == category }
                    if !items.isEmpty {
                        Section {
                            if !collapsedCategories.contains(category.rawValue) {
                                ForEach(items) { item in
                                    groceryRow(item)
                                }
                            }
                        } header: {
                            Button {
                                withAnimation {
                                    if collapsedCategories.contains(category.rawValue) {
                                        collapsedCategories.remove(category.rawValue)
                                    } else {
                                        collapsedCategories.insert(category.rawValue)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(category.rawValue)
                                    Text("\(items.count)").foregroundStyle(.secondary)
                                    Spacer()
                                    Image(systemName: collapsedCategories.contains(category.rawValue)
                                          ? "chevron.down" : "chevron.up")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .textCase(nil)
                            .accessibilityLabel("\(category.rawValue), \(items.count) items")
                            .accessibilityValue(collapsedCategories.contains(category.rawValue) ? "Collapsed" : "Expanded")
                            .accessibilityHint("Double tap to expand or collapse this group")
                        }
                        .listRowBackground(CookTheme.card)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(CookTheme.canvas)
        .navigationTitle("Groceries")
        .tint(CookTheme.accent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Clear bought items", systemImage: "checkmark.circle") { confirmsClear = true }
                        .disabled(purchasedCount == 0)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Grocery list actions")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add item", systemImage: "plus") {
                    editor = GroceryEditorPresentation(item: nil)
                }
                .accessibilityIdentifier("groceries.add")
            }
        }
        .sheet(item: $editor) { presentation in
            GroceryItemEditorView(item: presentation.item)
        }
        .confirmationDialog("Clear bought items?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Clear \(purchasedCount) bought items", role: .destructive) {
                perform { try store.clearCheckedGroceries() }
            }
        } message: {
            Text("Bought items will be removed from this list. Your saved recipes will stay in your library.")
        }
        .confirmationDialog("Remove this item?", isPresented: deleteConfirmation, titleVisibility: .visible) {
            if let item = itemToDelete {
                Button("Remove \(item.name)", role: .destructive) {
                    perform { try store.deleteGrocery(id: item.id) }
                    itemToDelete = nil
                }
            }
        } message: {
            Text("This removes the item from your grocery list.")
        }
        .alert("Couldn’t update groceries", isPresented: errorPresentation) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func groceryRow(_ item: GroceryItem) -> some View {
        HStack(spacing: 12) {
            Button {
                perform { try store.toggleGrocery(id: item.id) }
            } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isChecked ? CookTheme.accent : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(item.name) as \(item.isChecked ? "to buy" : "bought")")
            .accessibilityValue(item.isChecked ? "Bought" : "To buy")
            .accessibilityIdentifier("grocery.check.\(item.id.uuidString)")

            Button {
                editor = GroceryEditorPresentation(item: item)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.body.weight(.medium))
                            .strikethrough(item.isChecked)
                            .foregroundStyle(item.isChecked ? Color.secondary : Color.primary)
                        if !item.amountText.isEmpty {
                            Text(item.amountText).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if !item.recipeIDs.isEmpty {
                            Text("From \(item.recipeIDs.count) \(item.recipeIDs.count == 1 ? "recipe" : "recipes")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(item.name)\(item.amountText.isEmpty ? "" : ", \(item.amountText)")")
        }
        .padding(.vertical, 3)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive) { itemToDelete = item }
            Button("Edit") { editor = GroceryEditorPresentation(item: item) }
                .tint(CookTheme.accent)
        }
        .contextMenu {
            Button("Edit item", systemImage: "pencil") { editor = GroceryEditorPresentation(item: item) }
            Button("Remove item", systemImage: "trash", role: .destructive) { itemToDelete = item }
        }
    }

    private func emptyState(title: String, message: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        EmptyStateView(title: title, message: message, systemImage: "basket", actionTitle: actionTitle, action: action)
            .frame(maxWidth: .infinity, minHeight: 260)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private var deleteConfirmation: Binding<Bool> {
        Binding(get: { itemToDelete != nil }, set: { if !$0 { itemToDelete = nil } })
    }

    private var errorPresentation: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}

private enum GroceryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case remaining = "To buy"
    case purchased = "Bought"
    var id: String { rawValue }
}

private struct GroceryEditorPresentation: Identifiable {
    let id = UUID()
    let item: GroceryItem?
}

private struct GroceryItemEditorView: View {
    @Environment(CookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GroceryItem
    @State private var errorMessage: String?
    private let originalItem: GroceryItem?

    init(item: GroceryItem?) {
        originalItem = item
        _draft = State(initialValue: item ?? GroceryItem(name: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("grocery.editor.name")
                    TextField("Amount, for example 2 cups or to taste", text: $draft.amountText)
                        .accessibilityIdentifier("grocery.editor.amount")
                    Picker("Category", selection: $draft.category) {
                        ForEach(GroceryCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    Toggle("Bought", isOn: $draft.isChecked)
                }
                Section {
                    Text("Amounts can be numbers, ranges or words such as “to taste”. Keep the amount that works for your shop.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !draft.recipeIDs.isEmpty {
                    Section("From your recipes") {
                        ForEach(draft.recipeIDs, id: \.self) { recipeID in
                            if let recipe = store.recipe(id: recipeID) {
                                NavigationLink(recipe.title) {
                                    RecipeDetailView(recipeID: recipeID)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CookTheme.canvas)
            .navigationTitle(originalItem == nil ? "Add Grocery Item" : "Edit Grocery Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("grocery.editor.save")
                }
            }
            .alert("Couldn’t save item", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Please try again.") }
        }
        .tint(CookTheme.accent)
    }

    private func save() {
        var item = draft
        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.amountText = item.amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.name.isEmpty else { return }
        if originalItem?.amountText != item.amountText {
            let parsed = RecipeIngredient.from(name: item.name, amountText: item.amountText, category: item.category)
            item.quantity = parsed.quantity
            item.unit = parsed.unit
        }
        do {
            try store.upsertGrocery(item)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
