// Developer: gengyun
// Purpose: Presents the RecipePouch settings hub and local preference screens.

import RecipeCore
import SwiftUI

struct SettingsHubView: View {
    var body: some View {
        List {
            Section("Account") {
                NavigationLink {
                    AccountView()
                } label: {
                    SettingsRow("RecipePouch Account", "person.crop.circle")
                }

                NavigationLink {
                    SubscriptionView()
                } label: {
                    SettingsRow("Subscription", "sparkles")
                }

                NavigationLink {
                    CloudSyncSettingsView()
                } label: {
                    SettingsRow("Cloud Sync", "arrow.triangle.2.circlepath.icloud")
                }
            }

            Section("App preferences") {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    SettingsRow("Appearance", "circle.lefthalf.filled")
                }

                NavigationLink {
                    NotificationPreferencesView()
                } label: {
                    SettingsRow("Notifications", "bell")
                }

                NavigationLink {
                    CookingSettingsView()
                } label: {
                    SettingsRow("Cooking", "frying.pan")
                }

                NavigationLink {
                    GrocerySettingsView()
                } label: {
                    SettingsRow("Groceries", "basket")
                }

                NavigationLink {
                    MealPlanSettingsView()
                } label: {
                    SettingsRow("Meal Plan", "calendar")
                }
            }

            Section("Data & support") {
                NavigationLink {
                    DataPrivacySettingsView()
                } label: {
                    SettingsRow("Data & Privacy", "hand.raised")
                }

                NavigationLink {
                    HelpCenterView()
                } label: {
                    SettingsRow("Help & Support", "questionmark.circle")
                }

                NavigationLink {
                    AboutSettingsView()
                } label: {
                    SettingsRow("About RecipePouch", "info.circle")
                }
            }
        }
        .listSectionSpacing(RecipeSpacing.medium)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct SettingsRow: View {
    let title: String
    let icon: String

    init(_ title: String, _ icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 32)
                .foregroundStyle(RecipeTheme.accentForeground)

            // These labels are static product copy routed through a shared
            // String helper, not user-authored settings values.
            Text(LocalizedStringKey(title))
        }
        .frame(minHeight: 50)
    }
}

struct CloudSyncSettingsView: View {
    @Environment(CloudSyncCoordinator.self) private var cloudSync
    @Environment(\.locale) private var locale
    @State private var auth = RecipeAuthService.shared
    @State private var conflictChoices: [String: LibraryMergeSource] = [:]

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Account", value: accountLabel)
                LabeledContent("Last synced", value: lastSyncedLabel)
                LabeledContent("Status", value: statusLabel)

                if isSignedIn {
                    Button("Sync Now") {
                        Task { await cloudSync.syncNow() }
                    }
                    .disabled(isSyncing)
                } else {
                    LabeledContent(
                        "Manual Sync",
                        value: "Available after sign in"
                    )
                }
            }

            Section("Sync behavior") {
                Picker("Update", selection: modeBinding) {
                    ForEach(CloudSyncMode.allCases, id: \.rawValue) { mode in
                        Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                    }
                }
            }

            stateActions
        }
        .navigationTitle("Cloud Sync")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: conflictIDs) { _, ids in
            conflictChoices = conflictChoices.filter {
                ids.contains($0.key)
            }
        }
    }

    @ViewBuilder
    private var stateActions: some View {
        switch cloudSync.state {
        case .initialChoice(let local, let cloud):
            Section("First sync") {
                Text(
                    String(
                        localized:
                            "Choose how to connect this iPhone’s local library to your RecipePouch account."
                    ))

                LabeledContent(
                    "This iPhone",
                    value: countSummary(local)
                )
                LabeledContent(
                    "Cloud",
                    value: cloud.map(countSummary) ?? "Empty"
                )

                Button("Merge Local + Cloud") {
                    Task {
                        await cloudSync.chooseInitialSync(.mergeLibraries)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Keep Local for Now") {
                    Task {
                        await cloudSync.chooseInitialSync(.keepLocalUntilLater)
                    }
                }
            }

        case .conflicts(let conflicts):
            Section("Conflicts") {
                Text(
                    String(
                        localized:
                            "Both this iPhone and the cloud changed the same data. Choose which version to keep for each conflict."
                    )
                )
                .foregroundStyle(.secondary)

                ForEach(conflicts) { conflict in
                    Picker(
                        conflictLabel(conflict),
                        selection: conflictBinding(for: conflict)
                    ) {
                        Text("Choose…").tag(Optional<LibraryMergeSource>.none)
                        Text("This iPhone").tag(
                            Optional(LibraryMergeSource.local)
                        )
                        Text("Cloud").tag(
                            Optional(LibraryMergeSource.cloud)
                        )
                    }
                }

                Button("Resolve & Sync") {
                    let choices = conflicts.compactMap { conflict in
                        conflictChoices[conflict.id].map {
                            LibraryMergeChoice(
                                conflict: conflict,
                                source: $0
                            )
                        }
                    }
                    Task {
                        await cloudSync.resolveConflicts(with: choices)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(
                    conflicts.contains {
                        conflictChoices[$0.id] == nil
                    }
                )
            }

        case .error(let message):
            Section("Sync Error") {
                Text(message)
                    .foregroundStyle(.red)
                if isSignedIn {
                    Button("Try Again") {
                        Task { await cloudSync.syncNow() }
                    }
                }
            }

        case .localOnly, .syncing, .synced:
            EmptyView()
        }
    }

    private var modeBinding: Binding<CloudSyncMode> {
        Binding(
            get: { cloudSync.mode },
            set: { cloudSync.setMode($0) }
        )
    }

    private var isSignedIn: Bool {
        if case .signedIn = auth.state { return true }
        return false
    }

    private var isSyncing: Bool {
        if case .syncing = cloudSync.state { return true }
        return false
    }

    private var accountLabel: String {
        switch auth.state {
        case .signedIn(_, let email):
            return email ?? String(localized: "Signed in")
        case .loading, .authenticating:
            return String(localized: "Checking…")
        default:
            return String(localized: "Not connected")
        }
    }

    private var lastSyncedLabel: String {
        guard let date = cloudSync.lastSyncedAt else {
            return String(localized: "Never")
        }
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(locale)
        )
    }

    private var statusLabel: String {
        switch cloudSync.state {
        case .localOnly:
            return String(localized: "Local only")
        case .syncing:
            return String(localized: "Syncing…")
        case .synced:
            return String(localized: "Synced")
        case .initialChoice:
            return String(localized: "Waiting for your choice")
        case .conflicts(let conflicts):
            return String(localized: "\(conflicts.count) conflicts")
        case .error:
            return String(localized: "Needs attention")
        }
    }

    private var conflictIDs: Set<String> {
        if case .conflicts(let conflicts) = cloudSync.state {
            return Set(conflicts.map(\.id))
        }
        return []
    }

    private func conflictBinding(
        for conflict: LibraryMergeConflict
    ) -> Binding<LibraryMergeSource?> {
        Binding(
            get: { conflictChoices[conflict.id] },
            set: { conflictChoices[conflict.id] = $0 }
        )
    }

    private func conflictLabel(
        _ conflict: LibraryMergeConflict
    ) -> String {
        if conflict.id.hasPrefix("collection-name:") {
            return String(localized: "Collection name")
        }
        if conflict.id.hasPrefix("meal-slot:") {
            return String(localized: "Meal plan slot")
        }

        switch conflict.entity {
        case .recipe:
            return String(localized: "Recipe")
        case .grocery:
            return String(localized: "Grocery item")
        case .meal:
            return String(localized: "Meal plan entry")
        case .collection:
            return String(localized: "Collection")
        case .membership:
            return String(localized: "Collection membership")
        case .settings:
            return String(localized: "Settings")
        }
    }

    private func countSummary(_ counts: CloudLibraryCounts) -> String {
        let recipeCount = String.localizedStringWithFormat(
            String(localized: "%lld recipes"),
            counts.recipes
        )
        let groceryCount = String.localizedStringWithFormat(
            String(localized: "%lld grocery items"),
            counts.groceries
        )
        let mealCount = String.localizedStringWithFormat(
            String(localized: "%lld planned meals"),
            counts.plannedMeals
        )
        return [recipeCount, groceryCount, mealCount].joined(separator: " · ")
    }
}

struct AppearanceSettingsView: View {
    @Environment(RecipeStore.self) private var store
    @State private var error: String?

    var body: some View {
        Form {
            Section("Theme") {
                Picker(
                    "Appearance",
                    selection: Binding(
                        get: { store.settings.appearance },
                        set: { value in update { $0.appearance = value } }
                    )
                ) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(LocalizedStringKey(appearance.rawValue)).tag(appearance)
                    }
                }
            }

            Section("Recipe display") {
                LabeledContent("Recipe image placeholders", value: "On")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Couldn’t save",
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )
        ) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func update(_ change: (inout RecipeSettings) -> Void) {
        var settings = store.settings
        change(&settings)

        do {
            try store.updateSettings(settings)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct CookingSettingsView: View {
    @Environment(RecipeStore.self) private var store
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("Keep Screen Awake", isOn: binding(\.keepScreenAwake))

                // Reuse the permission-aware flow instead of writing an
                // enabled preference when the device has denied notifications.
                NavigationLink {
                    NotificationPreferencesView()
                } label: {
                    HStack {
                        Text("Timer Notifications")
                        Spacer()
                        Text(store.settings.timerNotifications ? "On" : "Off")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("During cooking") {
                LabeledContent("Navigation", value: "Full screen")
                LabeledContent("Ingredient checkoff", value: "Remembered per session")
                LabeledContent("Interrupted session", value: "Restored")
            }
        }
        .navigationTitle("Cooking")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Couldn’t save",
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )
        ) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func binding(
        _ keyPath: WritableKeyPath<RecipeSettings, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { value in
                var settings = store.settings
                settings[keyPath: keyPath] = value

                do {
                    try store.updateSettings(settings)
                } catch {
                    self.error = error.localizedDescription
                }
            }
        )
    }
}

struct GrocerySettingsView: View {
    @AppStorage("recipe.grocery.consolidate") private var consolidate = true
    @AppStorage("recipe.grocery.sources") private var sources = true

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Consolidate compatible ingredients",
                    isOn: $consolidate
                )
                Toggle("Show recipe names", isOn: $sources)
            }

            Section("Organization") {
                LabeledContent("Grouping", value: "Grocery category")
                LabeledContent("Bought items", value: "Can be hidden or cleared")
            }
        }
        .navigationTitle("Groceries")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MealPlanSettingsView: View {
    @AppStorage("recipe.meal.weekStart") private var weekStart = "System Default"

    var body: some View {
        Form {
            Section {
                Picker("Week Starts On", selection: $weekStart) {
                    Text("System Default").tag("System Default")
                    Text("Sunday").tag("Sunday")
                    Text("Monday").tag("Monday")
                }
            }

            Section("Meal types") {
                ForEach(["Breakfast", "Lunch", "Dinner"], id: \.self) { mealType in
                    Text(mealType)
                }
            }
        }
        .navigationTitle("Meal Plan")
        .navigationBarTitleDisplayMode(.inline)
    }
}
