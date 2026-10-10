// Developer: gengyun
// Purpose: Implements the grocery list, editing, grouping, source references, and purchase state.

import RecipeCore
import SwiftUI

struct GroceriesView: View {
    @Environment(RecipeStore.self) private var store
    @AppStorage(RecipeUITestNamespace.preferenceKey("recipe.grocery.sources"))
    private var showRecipeNames = true
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

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: RecipeSpacing.medium) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(store.groceries.count) items")
                            .font(RecipeTheme.heading(.section))
                        Spacer()
                        Text("\(purchasedCount) bought")
                            .font(RecipeTheme.text(15, weight: .regular, relativeTo: .subheadline))
                            .foregroundStyle(RecipeTheme.accentForeground)
                    }
                    Picker("Grocery filter", selection: $filter) {
                        ForEach(GroceryFilter.allCases) { filter in
                            Text(LocalizedStringKey(filter.rawValue)).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("groceries.filter")
                }
                .padding(.bottom, RecipeSpacing.xSmall)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))

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
                                    Text(LocalizedStringKey(category.rawValue))
                                    Text(items.count, format: .number).foregroundStyle(.secondary)
                                    Spacer()
                                    Image(
                                        systemName: collapsedCategories.contains(category.rawValue)
                                            ? "chevron.down" : "chevron.up")
                                }
                                .font(
                                    RecipeTheme.text(
                                        15, weight: .semibold, relativeTo: .subheadline)
                                )
                                .foregroundStyle(.primary)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .textCase(nil)
                            .accessibilityLabel(LocalizedStringKey(category.rawValue))
                            .accessibilityValue(
                                collapsedCategories.contains(category.rawValue)
                                    ? LocalizedStringKey("Collapsed, \(items.count) items")
                                    : LocalizedStringKey("Expanded, \(items.count) items")
                            )
                            .accessibilityHint("Double tap to expand or collapse this group")
                        }
                        .listRowBackground(RecipeTheme.card)
                    }
                }
            }
        }
        .recipeRootScrollClearance()
        .listStyle(.insetGrouped)
        .contentMargins(.top, RecipeSpacing.pageTop, for: .scrollContent)
        .listSectionSpacing(RecipeSpacing.medium)
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .navigationTitle("Groceries")
        .navigationBarTitleDisplayMode(RecipeNavigation.rootTitleMode)
        .tint(RecipeTheme.accent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Clear bought items", systemImage: "checkmark.circle") {
                        confirmsClear = true
                    }
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
        .confirmationDialog(
            "Clear bought items?", isPresented: $confirmsClear, titleVisibility: .visible
        ) {
            Button("Clear \(purchasedCount) bought item", role: .destructive) {
                perform { try store.clearCheckedGroceries() }
            }
        } message: {
            Text(
                "Bought items will be removed from this list. Your saved recipes will stay in your library."
            )
        }
        .confirmationDialog(
            "Remove this item?", isPresented: deleteConfirmation, titleVisibility: .visible
        ) {
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

    private func sourceDescription(for item: GroceryItem) -> String? {
        guard showRecipeNames else { return nil }

        let titles = item.recipeIDs.compactMap { id -> String? in
            guard
                let title = store.recipe(id: id)?.title
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !title.isEmpty
            else {
                return nil
            }
            return title
        }
        return titles.isEmpty
            ? nil : RecipeLanguage.localized("From %@", titles.joined(separator: ", "))
    }

    private func groceryRow(_ item: GroceryItem) -> some View {
        HStack(spacing: 12) {
            Button {
                RecipePerformanceSignposts.measure("Grocery Write") {
                    perform {
                        try store.toggleGrocery(id: item.id)
                    }
                }
            } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        item.isChecked ? RecipeTheme.accentForeground : Color.secondary
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                item.isChecked
                    ? LocalizedStringKey("Mark \(item.name) as to buy")
                    : LocalizedStringKey("Mark \(item.name) as bought")
            )
            .accessibilityValue(
                item.isChecked
                    ? LocalizedStringKey("Bought")
                    : LocalizedStringKey("To buy")
            )
            .accessibilityIdentifier("grocery.check.\(item.id.uuidString)")

            Button {
                editor = GroceryEditorPresentation(item: item)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: RecipeSpacing.xxSmall) {
                        Text(item.name)
                            .font(RecipeTheme.text(17, weight: .semibold, relativeTo: .body))
                            .strikethrough(item.isChecked)
                            .foregroundStyle(item.isChecked ? Color.secondary : Color.primary)
                        if !item.amountText.isEmpty {
                            Text(item.amountText).font(
                                RecipeTheme.text(15, weight: .regular, relativeTo: .subheadline)
                            ).foregroundStyle(.secondary)
                        }
                        if let sourceNames = sourceDescription(for: item) {
                            Text(sourceNames)
                                .font(RecipeTheme.text(12, weight: .regular, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                item.amountText.isEmpty
                    ? LocalizedStringKey("Edit \(item.name)")
                    : LocalizedStringKey("Edit \(item.name), \(item.amountText)")
            )
        }
        .padding(.vertical, 3)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                RecipePerformanceSignposts.measure("Grocery Write") {
                    perform { try store.toggleGrocery(id: item.id) }
                }
            } label: {
                if item.isChecked {
                    Label("To buy", systemImage: "arrow.uturn.backward")
                } else {
                    Label("Bought", systemImage: "checkmark.circle")
                }
            }
            .tint(RecipeTheme.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive) { itemToDelete = item }
            Button("Edit") { editor = GroceryEditorPresentation(item: item) }
                .tint(RecipeTheme.accent)
        }
        .contextMenu {
            Button("Edit item", systemImage: "pencil") {
                editor = GroceryEditorPresentation(item: item)
            }
            .accessibilityLabel(
                item.amountText.isEmpty
                    ? LocalizedStringKey("Edit \(item.name)")
                    : LocalizedStringKey("Edit \(item.name), \(item.amountText)")
            )
            Button("Remove item", systemImage: "trash", role: .destructive) { itemToDelete = item }
        }
    }

    private func emptyState(
        title: String, message: String, actionTitle: String, action: @escaping () -> Void
    ) -> some View {
        EmptyStateView(
            title: title, message: message, systemImage: "basket", actionTitle: actionTitle,
            action: action
        )
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
    @Environment(RecipeStore.self) private var store
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
                            Text(LocalizedStringKey(category.rawValue)).tag(category)
                        }
                    }
                    Toggle("Bought", isOn: $draft.isChecked)
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
            .background(RecipeTheme.canvas)
            .navigationTitle(
                LocalizedStringKey(originalItem == nil ? "Add Grocery Item" : "Edit Grocery Item")
            )
            .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(
                            draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                        .accessibilityIdentifier("grocery.editor.save")
                }
            }
            .alert(
                "Couldn’t save item",
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

    private func save() {
        var item = draft
        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.amountText = item.amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.name.isEmpty else { return }
        if originalItem?.amountText != item.amountText {
            let parsed = RecipeIngredient.from(
                name: item.name, amountText: item.amountText, category: item.category)
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
