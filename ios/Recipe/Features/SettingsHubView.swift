// Developer: gengyun
// Purpose: Presents the Recipe Pals settings hub and local preference screens.

import RecipeCore
import SwiftUI

struct SettingsHubView: View {
    var body: some View {
        List {
            Section("Account") {
                NavigationLink {
                    AccountView(onExpand: {})
                } label: {
                    SettingsRow("Account", "person.crop.circle")
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
                    LocalePreferencesView()
                } label: {
                    SettingsRow("Language & Country", "globe")
                }

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
                    SettingsRow("About", "info.circle")
                }
            }
        }
        .listSectionSpacing(RecipeSpacing.medium)
        .contentMargins(.top, RecipeSpacing.pageTop, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct SettingsRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let icon: String

    init(_ title: String, _ icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: RecipeSpacing.small) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .frame(width: 24)
                .foregroundStyle(RecipeTheme.accentForeground)
                .accessibilityHidden(true)

            Text(LocalizedStringKey(title))
                .font(RecipeTheme.text(17, relativeTo: .body))
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
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
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
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
                        localized: LocalizedStringResource(
                            "Choose how to connect this iPhone’s local library to your Recipe Pals account.",
                            locale: RecipeLanguage.active)))

                LabeledContent(
                    "This iPhone",
                    value: countSummary(local)
                )
                LabeledContent(
                    "Cloud",
                    value: cloud.map(countSummary)
                        ?? String(
                            localized: LocalizedStringResource(
                                "Empty", locale: RecipeLanguage.active))
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
                        localized: LocalizedStringResource(
                            "Both this iPhone and the cloud changed the same data. Choose which version to keep for each conflict.",
                            locale: RecipeLanguage.active))
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
            return email
                ?? String(
                    localized: LocalizedStringResource("Signed in", locale: RecipeLanguage.active))
        case .loading, .authenticating:
            return String(
                localized: LocalizedStringResource("Checking…", locale: RecipeLanguage.active))
        default:
            return String(
                localized: LocalizedStringResource("Not connected", locale: RecipeLanguage.active))
        }
    }

    private var lastSyncedLabel: String {
        guard let date = cloudSync.lastSyncedAt else {
            return String(
                localized: LocalizedStringResource("Never", locale: RecipeLanguage.active))
        }
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(locale)
        )
    }

    private var statusLabel: String {
        switch cloudSync.state {
        case .localOnly:
            return String(
                localized: LocalizedStringResource("Local only", locale: RecipeLanguage.active))
        case .syncing:
            return String(
                localized: LocalizedStringResource("Syncing…", locale: RecipeLanguage.active))
        case .synced:
            return String(
                localized: LocalizedStringResource("Synced", locale: RecipeLanguage.active))
        case .initialChoice:
            return String(
                localized: LocalizedStringResource(
                    "Waiting for your choice", locale: RecipeLanguage.active))
        case .conflicts(let conflicts):
            return String(
                localized: LocalizedStringResource(
                    "\(conflicts.count) conflicts", locale: RecipeLanguage.active))
        case .error:
            return String(
                localized: LocalizedStringResource("Needs attention", locale: RecipeLanguage.active)
            )
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
            return String(
                localized: LocalizedStringResource("Collection name", locale: RecipeLanguage.active)
            )
        }
        if conflict.id.hasPrefix("meal-slot:") {
            return String(
                localized: LocalizedStringResource("Meal plan slot", locale: RecipeLanguage.active))
        }

        switch conflict.entity {
        case .recipe:
            return String(
                localized: LocalizedStringResource("Recipe", locale: RecipeLanguage.active))
        case .grocery:
            return String(
                localized: LocalizedStringResource("Grocery item", locale: RecipeLanguage.active))
        case .meal:
            return String(
                localized: LocalizedStringResource("Meal plan entry", locale: RecipeLanguage.active)
            )
        case .collection:
            return String(
                localized: LocalizedStringResource("Collection", locale: RecipeLanguage.active))
        case .membership:
            return String(
                localized: LocalizedStringResource(
                    "Collection membership", locale: RecipeLanguage.active))
        case .settings:
            return String(
                localized: LocalizedStringResource("Settings", locale: RecipeLanguage.active))
        }
    }

    private func countSummary(_ counts: CloudLibraryCounts) -> String {
        let recipeCount = String.localizedStringWithFormat(
            String(
                localized: LocalizedStringResource("%lld recipes", locale: RecipeLanguage.active)),
            counts.recipes
        )
        let groceryCount = String.localizedStringWithFormat(
            String(
                localized: LocalizedStringResource(
                    "%lld grocery items", locale: RecipeLanguage.active)),
            counts.groceries
        )
        let mealCount = String.localizedStringWithFormat(
            String(
                localized: LocalizedStringResource(
                    "%lld planned meals", locale: RecipeLanguage.active)),
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

        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
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
                        Text(LocalizedStringKey(store.settings.timerNotifications ? "On" : "Off"))
                            .foregroundStyle(.secondary)
                    }
                }
            }

        }
        .navigationTitle("Cooking")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
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
    @AppStorage(RecipeUITestNamespace.preferenceKey("recipe.grocery.consolidate"))
    private var consolidate = true
    @AppStorage(RecipeUITestNamespace.preferenceKey("recipe.grocery.sources"))
    private var sources = true

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Consolidate compatible ingredients",
                    isOn: $consolidate
                )
                Toggle("Show recipe names", isOn: $sources)
            }

        }
        .navigationTitle("Groceries")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
    }
}

struct MealPlanSettingsView: View {
    @AppStorage(RecipeUITestNamespace.preferenceKey("recipe.meal.weekStart"))
    private var weekStart = "System Default"

    var body: some View {
        Form {
            Section {
                Picker("Week Starts On", selection: $weekStart) {
                    Text("System Default").tag("System Default")
                    Text("Sunday").tag("Sunday")
                    Text("Monday").tag("Monday")
                }
            }

        }
        .navigationTitle("Meal Plan")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
    }
}


struct LocalePreferencesView: View {
    @AppStorage(RecipeLanguage.preferenceKey) private var languageOverride = ""
    @AppStorage("recipe.countryOverride") private var countryOverride = ""
    private let languages: [(id: String, label: String)] = [
        ("en", "English"), ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"), ("ja", "日本語"),
    ]

    private var countryCodes: [String] {
        Locale.Region.isoRegions
            .map(\.identifier)
            .filter { code in
                code.count == 2 && code.allSatisfy { $0.isASCII && $0.isLetter }
            }
            .sorted {
                let lhs = RecipeLanguage.active.localizedString(forRegionCode: $0) ?? $0
                let rhs = RecipeLanguage.active.localizedString(forRegionCode: $1) ?? $1
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
    }

    var body: some View {
        Form {
            Section("App language") {
                Picker("Language", selection: $languageOverride) {
                    Text("English (test default)").tag("")
                    ForEach(languages, id: \.id) { language in
                        Text(language.label).tag(language.id)
                    }
                }
                .pickerStyle(.navigationLink)
                .accessibilityIdentifier("settings.languagePicker")
            }
            Section("Country or region") {
                Picker("Country or region", selection: $countryOverride) {
                    Text("Use device region").tag("")
                    ForEach(countryCodes, id: \.self) { code in
                        Text(RecipeLanguage.active.localizedString(forRegionCode: code) ?? code)
                            .tag(code)
                    }
                }
            }
            Section {
                Text("Country is a preference for future regional content. It does not change your account country or App Store subscriptions.")
                    .font(RecipeTheme.text(13, relativeTo: .footnote))
            }
        }
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .navigationTitle("Language & Country")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
    }
}
