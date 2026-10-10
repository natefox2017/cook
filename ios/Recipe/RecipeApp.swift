// Developer: gengyun
// Purpose: Creates the Recipe iOS app, shared services, compatibility migrations, and primary navigation.

import Foundation
import RecipeCore
import StoreKit
import SwiftUI

enum RecipeUITestNamespace {
    static let resetCookingSessionsArgument = "--uitesting-reset-cooking-sessions"
    static let exportQAArgument = "--uitesting-export-qa"
    static let resetExportQAArgument = "--uitesting-export-qa-reset"
    static let exportQAPermissionFailureArgument =
        "--uitesting-export-qa-inject-write-permission-denial"

    static var isUITesting: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("--uitesting")
        #else
            false
        #endif
    }

    static var isExportQA: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains(exportQAArgument) && isUITesting
        #else
            false
        #endif
    }

    static var injectsExportQAPermissionFailure: Bool {
        #if DEBUG
            return isExportQA
                && ProcessInfo.processInfo.arguments.contains(exportQAPermissionFailureArgument)
        #else
            return false
        #endif
    }

    static var authDefaults: UserDefaults {
        authDefaults(isUITesting: isUITesting)
    }

    static func authDefaults(isUITesting: Bool) -> UserDefaults {
        #if DEBUG
            if isUITesting {
                return UserDefaults(
                    suiteName: "com.shopkivoo.recipe.uitesting-auth"
                )!
            }
        #endif
        return .standard
    }

    static func preferenceKey(_ key: String, isUITesting: Bool) -> String {
        guard isUITesting else { return key }

        let suffix =
            key.hasPrefix("recipe.")
            ? String(key.dropFirst("recipe.".count))
            : key
        return "recipe.uitesting.\(suffix)"
    }

    static func preferenceKey(_ key: String) -> String {
        preferenceKey(key, isUITesting: isUITesting)
    }

    static func clearCookingSessions(from defaults: UserDefaults) {
        for key in Array(defaults.dictionaryRepresentation().keys)
        where key.hasPrefix("recipe.uitesting.cookingSession.") {
            defaults.removeObject(forKey: key)
        }
    }

    static func clearPreferences(from defaults: UserDefaults) {
        for key in Array(defaults.dictionaryRepresentation().keys)
        where key.hasPrefix("recipe.uitesting.") {
            defaults.removeObject(forKey: key)
        }
    }

    static func timerNotificationPrefix(recipeID: UUID, isUITesting: Bool) -> String {
        let prefix = isUITesting ? "recipe.uitesting.timer." : "cook.timer."
        return "\(prefix)\(recipeID.uuidString)."
    }

    static func timerNotificationID(
        recipeID: UUID,
        timerID: UUID,
        isUITesting: Bool
    ) -> String {
        let prefix = timerNotificationPrefix(recipeID: recipeID, isUITesting: isUITesting)
        return "\(prefix)\(timerID.uuidString)"
    }

    static var exportQALibraryURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Recipe", isDirectory: true)
            .appendingPathComponent("UITestExportQA", isDirectory: true)
            .appendingPathComponent("library.json")
    }
}

#if DEBUG
    enum RecipeExportQAFixture {
        static let seed: UInt64 = 127
        static let recipeIDs = (0..<5).map {
            RecipePerformanceFixtureConfiguration.recipeID(seed: seed, index: $0)
        }
        static let firstRecipeID = recipeIDs[0]
        static let privateNotes = "PRIVATE QA NOTES: synthetic export fixture; not personal data."
        static let sourceURL = "https://example.test/recipe-export-qa/roast"

        private static let timestamp = Date(timeIntervalSince1970: 1_790_000_000)
        private static let coverImageData: Data = {
            guard
                let data = Data(
                    base64Encoded:
                        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"
                )
            else {
                preconditionFailure("The embedded QA cover image must be valid base64.")
            }
            return data
        }()

        static let snapshot = RecipeLibrarySnapshot(
            recipes: (0..<5).map(recipe),
            groceries: [
                GroceryItem(
                    id: RecipePerformanceFixtureConfiguration.recipeID(seed: seed, index: 80_001),
                    name: "QA flour",
                    amountText: "about 2 cups",
                    category: .pantry,
                    recipeIDs: [recipeIDs[1]]
                ),
                GroceryItem(
                    id: RecipePerformanceFixtureConfiguration.recipeID(seed: seed, index: 80_002),
                    name: "QA tomatoes",
                    amountText: "a few",
                    category: .produce,
                    recipeIDs: [recipeIDs[0]]
                ),
            ],
            mealPlan: [
                MealPlanEntry(
                    id: RecipePerformanceFixtureConfiguration.recipeID(seed: seed, index: 90_001),
                    recipeID: recipeIDs[0],
                    date: Date(timeIntervalSince1970: 1_790_060_000),
                    slot: .dinner
                ),
                MealPlanEntry(
                    id: RecipePerformanceFixtureConfiguration.recipeID(seed: seed, index: 90_002),
                    recipeID: recipeIDs[1],
                    date: Date(timeIntervalSince1970: 1_790_146_400),
                    slot: .breakfast
                ),
            ],
            collections: [
                RecipeCollection(
                    id: RecipePerformanceFixtureConfiguration.recipeID(seed: seed, index: 10_001),
                    name: "QA Export Collection",
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            ],
            collectionMemberships: [
                RecipeCollectionMembership(
                    recipeID: recipeIDs[0],
                    collectionID: RecipePerformanceFixtureConfiguration.recipeID(
                        seed: seed,
                        index: 10_001
                    )
                ),
                RecipeCollectionMembership(
                    recipeID: recipeIDs[1],
                    collectionID: RecipePerformanceFixtureConfiguration.recipeID(
                        seed: seed,
                        index: 10_001
                    )
                ),
            ],
            settings: RecipeSettings(
                displayName: "Export QA",
                email: "qa-export@example.test",
                appearance: .dark,
                keepScreenAwake: false,
                timerNotifications: false
            ),
            deletedEntities: []
        )

        @MainActor
        static func makeStore(at fileURL: URL, reset: Bool = false) throws -> RecipeStore {
            if reset, FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
            let store = RecipeStore(fileURL: fileURL)
            guard !fileExists else { return store }
            try store.replaceLibrary(with: snapshot)
            return store
        }

        private static func recipe(index: Int) -> Recipe {
            let recipeID = recipeIDs[index]
            let ingredients: [RecipeIngredient]
            if index == 0 {
                ingredients = [
                    RecipeIngredient(
                        id: RecipePerformanceFixtureConfiguration.recipeID(
                            seed: seed, index: 20_001),
                        name: "Olive oil",
                        amountText: "a little",
                        category: .pantry
                    ),
                    RecipeIngredient(
                        id: RecipePerformanceFixtureConfiguration.recipeID(
                            seed: seed, index: 20_002),
                        name: "Sea salt",
                        amountText: "to taste",
                        category: .pantry
                    ),
                    RecipeIngredient(
                        id: RecipePerformanceFixtureConfiguration.recipeID(
                            seed: seed, index: 20_003),
                        name: "Stock",
                        amountText: "about 1 cup",
                        category: .other
                    ),
                ]
            } else {
                ingredients = [
                    RecipeIngredient(
                        id: RecipePerformanceFixtureConfiguration.recipeID(
                            seed: seed,
                            index: 20_000 + index * 10
                        ),
                        name: "QA ingredient",
                        amountText: "to taste"
                    )
                ]
            }

            return Recipe(
                id: recipeID,
                title: [
                    "QA Export Roast",
                    "QA Export Breakfast",
                    "QA Export Dessert",
                    "QA Export Side",
                    "QA Export Drink",
                ][index],
                summary: "Synthetic fixture for Recipe export QA.",
                category: RecipeCategory.allCases[index % RecipeCategory.allCases.count],
                servings: index == 0 ? 4 : 2,
                prepMinutes: index == 0 ? 15 : nil,
                cookMinutes: index == 0 ? 40 : nil,
                ingredients: ingredients,
                steps: [
                    RecipeStep(
                        id: RecipePerformanceFixtureConfiguration.recipeID(
                            seed: seed,
                            index: 50_000 + index
                        ),
                        title: "Prepare",
                        instruction: "Prepare the synthetic Recipe export QA fixture."
                    )
                ],
                sourceURL: index == 0
                    ? sourceURL
                    : "https://example.test/recipe-export-qa/\(recipeID.uuidString)",
                sourceText: index == 0 ? "QA source text retained for export verification." : nil,
                sourceName: "Recipe Export QA",
                coverData: index == 0 ? coverImageData : nil,
                isFavorite: index == 0,
                notes: index == 0 ? privateNotes : "Synthetic QA sample \(index + 1).",
                createdAt: timestamp,
                updatedAt: timestamp
            )
        }
    }
#endif

@main
@MainActor
struct RecipeApp: App {
    @State private var store: RecipeStore
    @State private var subscriptions = SubscriptionStore()
    @AppStorage(RecipeLanguage.preferenceKey) private var languageOverride = ""
    @State private var cloudSync: CloudSyncCoordinator
    private let isUITesting: Bool
    private let bypassOnboarding: Bool

    init() {
        TimerNotifications.configurePresentation()
        let defaults = UserDefaults.standard
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = RecipeUITestNamespace.isUITesting

        #if DEBUG
            // Keep the manual language UI smoke test independent of prior runs.
            if isUITesting && arguments.contains("--uitesting-reset-language") {
                defaults.removeObject(forKey: RecipeLanguage.preferenceKey)
            }
        #endif

        if !isUITesting {
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("cook.") {
                let recipeKey = "recipe." + key.dropFirst("cook.".count)
                if defaults.object(forKey: recipeKey) == nil,
                    let value = defaults.object(forKey: key)
                {
                    defaults.set(value, forKey: recipeKey)
                }
            }
        }

        RecipeTheme.installUIKitTypography()

        var bypassOnboarding = isUITesting
        #if DEBUG
            if isUITesting && arguments.contains("--uitesting-onboarding") {
                // Exercise the real first-launch flow with isolated UI-test fixtures.
                bypassOnboarding = false
                defaults.set(
                    false,
                    forKey: RecipeUITestNamespace.preferenceKey(
                        FirstLaunchFlowView.completionKey,
                        isUITesting: true
                    )
                )
            }
        #endif
        self.isUITesting = isUITesting
        self.bypassOnboarding = bypassOnboarding
        let cloudSyncService: any RecipeCloudSyncing =
            isUITesting
            ? UnconfiguredCloudSync()
            : SupabaseCloudSync()
        _cloudSync = State(
            initialValue: CloudSyncCoordinator(
                service: cloudSyncService,
                defaults: RecipeUITestNamespace.authDefaults,
                monitorsNetworkChanges: !isUITesting
            )
        )

        _ = RecipeAuthService.shared

        let performanceFixtureRequested = RecipePerformanceFixtureConfiguration.isRequested(
            arguments: arguments
        )
        let localStore: RecipeStore
        #if DEBUG
            if RecipeUITestNamespace.isExportQA {
                do {
                    localStore = try RecipeExportQAFixture.makeStore(
                        at: RecipeUITestNamespace.exportQALibraryURL,
                        reset: arguments.contains(RecipeUITestNamespace.resetExportQAArgument)
                    )
                } catch {
                    assertionFailure("Export QA fixture could not be loaded: \(error)")
                    localStore = RecipeStore(fileURL: RecipeUITestNamespace.exportQALibraryURL)
                }
            } else if performanceFixtureRequested {
                let configuration = RecipePerformanceFixtureConfiguration.parse(
                    arguments: arguments)
                if let configuration {
                    do {
                        localStore = try configuration.makeStore(arguments: arguments)
                    } catch {
                        assertionFailure("Performance fixture could not be loaded: \(error)")
                        localStore = RecipeStore(fileURL: nil)
                    }
                } else {
                    assertionFailure(
                        "Pass a supported --uitesting-performance-count=100, 500, 1000, or 5000."
                    )
                    localStore = RecipeStore(fileURL: nil)
                }
            } else if isUITesting {
                if arguments.contains(RecipeUITestNamespace.resetCookingSessionsArgument) {
                    RecipeUITestNamespace.clearCookingSessions(from: defaults)
                }
                localStore = RecipeStore(fileURL: nil)
                do {
                    try localStore.loadSampleRecipes()
                } catch {
                    assertionFailure("UI test fixtures could not be loaded: \(error)")
                }
            } else {
                localStore = Self.makeProductionStore(defaults: defaults)
            }
        #else
            localStore = Self.makeProductionStore(defaults: defaults)
        #endif

        _store = State(initialValue: localStore)
    }

    private static func makeProductionStore(defaults: UserDefaults) -> RecipeStore {
        let libraryURL = RecipeStore.defaultFileURL()
        if FileManager.default.fileExists(atPath: libraryURL.path),
            defaults.object(forKey: FirstLaunchFlowView.completionKey) == nil
        {
            // Existing installs with a persisted library should not be mistaken for new users
            // when this onboarding key is introduced for the first time.
            defaults.set(true, forKey: FirstLaunchFlowView.completionKey)
        }
        return RecipeStore(fileURL: libraryURL)
    }

    var body: some Scene {
        WindowGroup {
            RecipeRootView(isUITesting: isUITesting, bypassOnboarding: bypassOnboarding)
                .environment(store)
                .environment(subscriptions)
                .environment(cloudSync)
                .onOpenURL { url in
                    RecipeAuthService.shared.handleAuthCallback(url)
                }
                .tint(RecipeTheme.accent)
                .font(RecipeTheme.body())
                .preferredColorScheme(colorScheme)
                .environment(\.locale, appLocale)
        }
    }

    private var appLocale: Locale {
        RecipeLanguage.resolve(
            arguments: ProcessInfo.processInfo.arguments,
            supportedIdentifiers: Bundle.main.localizations,
            selectedIdentifier: languageOverride.isEmpty ? nil : languageOverride
        )
    }

    private var colorScheme: ColorScheme? {
        switch store.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// Shared direction classifier for deliberate horizontal navigation on native pages.
enum RecipeHorizontalSwipe: Equatable {
    case previous
    case next

    init?(translation: CGSize, minimumDistance: CGFloat = 96) {
        let horizontal = translation.width
        guard abs(horizontal) >= minimumDistance,
            abs(horizontal) > abs(translation.height) * 1.8
        else {
            return nil
        }

        self = horizontal < 0 ? .next : .previous
    }
}

private struct RecipeRootTabVisibility: ViewModifier {
    @Binding var selectedTab: RecipeTab
    let tab: RecipeTab
    @State private var isRootVisible = false

    func body(content: Content) -> some View {
        content
            // Inactive roots must relinquish their preference to the current page.
            .toolbarVisibility(isRootVisible ? .visible : .automatic, for: .tabBar)
            // Lower precedence preserves child horizontal strips and native row actions.
            // Only root screens carry this gesture; pushed pages keep system back-swipe.
            .gesture(
                DragGesture(minimumDistance: 55)
                    .onEnded { value in
                        guard isRootVisible, selectedTab == tab,
                            let direction = RecipeHorizontalSwipe(translation: value.translation),
                            let destination = tab.neighbor(in: direction)
                        else {
                            return
                        }
                        selectedTab = destination
                    }
            )
            .onAppear {
                isRootVisible = true
            }
            .onDisappear {
                isRootVisible = false
            }
    }
}

private struct RecipeRootView: View {
    @State private var auth = RecipeAuthService.shared
    @Environment(RecipeStore.self) private var store
    @Environment(CloudSyncCoordinator.self) private var cloudSync
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(
        RecipeUITestNamespace.preferenceKey(FirstLaunchFlowView.completionKey)
    ) private var hasCompletedOnboarding = false
    @State private var selectedTab: RecipeTab = .recipes
    @State private var shareInbox = RecipeShareInboxCoordinator()
    @State private var isAccountPresented = false
    @State private var accountDetent: PresentationDetent = .large

    let isUITesting: Bool
    let bypassOnboarding: Bool

    var body: some View {
        Group {
            if let message = store.loadError {
                NavigationStack {
                    EmptyStateView(
                        title: "Your saved library needs attention",
                        message:
                            RecipeLanguage.localized(
                                "Recipe Pals couldn't read your saved library. The file has been left unchanged."
                            ) + "\n\n" + message,
                        systemImage: "externaldrive.badge.exclamationmark",
                        actionTitle: "Try again",
                        action: {
                            store.reload()
                        },
                        messageLineLimit: nil
                    )
                    .padding()
                    .navigationTitle("Recipes")
                    .background(RecipeTheme.canvas)
                }
            } else if !hasCompletedOnboarding && !bypassOnboarding {
                FirstLaunchGateView {
                    hasCompletedOnboarding = true
                }
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        RecipesView()
                            .modifier(RecipeRootTabVisibility(selectedTab: $selectedTab, tab: .recipes))
                    }
                    .tabItem {
                        Label(RecipeTab.recipes.title, systemImage: RecipeTab.recipes.symbol)
                            .accessibilityIdentifier("tab.\(RecipeTab.recipes.rawValue)")
                    }
                    .tag(RecipeTab.recipes)

                    NavigationStack {
                        MealPlanView()
                            .modifier(RecipeRootTabVisibility(selectedTab: $selectedTab, tab: .plan))
                    }
                    .tabItem {
                        Label(RecipeTab.plan.title, systemImage: RecipeTab.plan.symbol)
                            .accessibilityIdentifier("tab.\(RecipeTab.plan.rawValue)")
                    }
                    .tag(RecipeTab.plan)

                    NavigationStack {
                        GroceriesView()
                            .modifier(RecipeRootTabVisibility(selectedTab: $selectedTab, tab: .groceries))
                    }
                    .tabItem {
                        Label(RecipeTab.groceries.title, systemImage: RecipeTab.groceries.symbol)
                            .accessibilityIdentifier("tab.\(RecipeTab.groceries.rawValue)")
                    }
                    .tag(RecipeTab.groceries)

                    NavigationStack {
                        ProfileView(onOpenAccount: presentAccount)
                            .modifier(RecipeRootTabVisibility(selectedTab: $selectedTab, tab: .profile))
                    }
                    .tabItem {
                        Label(RecipeTab.profile.title, systemImage: RecipeTab.profile.symbol)
                            .accessibilityIdentifier("tab.\(RecipeTab.profile.rawValue)")
                    }
                    .tag(RecipeTab.profile)
                }
            }
        }
        .environment(shareInbox)
        .sheet(isPresented: $isAccountPresented) {
            NavigationStack {
                AccountView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        accountDetent = .large
                    }
                }
            }
            .presentationDetents([.medium, .large], selection: $accountDetent)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(RecipeTheme.canvas)
        }
        .task {
            // In UI-test mode App Group provisioning may not be installed.
            // Normal installs read durable receipts from the shared container.
            if !isUITesting {
                await shareInbox.synchronize(store: store)
            }
        }
        .task {
            guard !isUITesting else {
                return
            }
            await cloudSync.bind(store: store, authState: auth.state)
            if auth.authCallbackGeneration > 0 {
                openAccountForAuthCallback()
            }
        }
        .task {
            // Load StoreKit product metadata so lifecycle status is available
            // even when the user never opens the subscription screen.
            await subscriptions.load()
        }
        .onChange(of: auth.state) { _, state in
            // An ACK from the previous account must not hide a receipt from
            // the newly signed-in account after an authentication transition.
            if !isUITesting {
                shareInbox.refresh()
            }
            if !isUITesting {
                Task {
                    await cloudSync.authenticationChanged(state)
                }
            }
            Task {
                if !isUITesting {
                    await shareInbox.synchronize(store: store)
                }
            }
        }
        .onChange(of: auth.authCallbackGeneration) { _, _ in
            openAccountForAuthCallback()
        }
        .onChange(of: store.changeToken) { _, token in
            guard !isUITesting else {
                return
            }
            Task {
                await cloudSync.localStoreChanged(token: token)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                return
            }
            if !isUITesting {
                shareInbox.refresh()
            }
            if !isUITesting {
                Task {
                    await cloudSync.appBecameActive()
                }
            }
            Task {
                if !isUITesting {
                    await shareInbox.synchronize(store: store)
                }
            }
            Task {
                if subscriptions.products.isEmpty {
                    await subscriptions.load(force: true)
                } else {
                    await subscriptions.refreshEntitlements()
                }
            }
        }
    }

    private func presentAccount() {
        accountDetent = .large
        isAccountPresented = true
    }

    private func openAccountForAuthCallback() {
        // Keep the current tab and reveal the recovery/account callback as a sheet.
        accountDetent = .large
        isAccountPresented = true
    }
}

private struct FirstLaunchGateView: View {
    private enum Decision {
        case checking
        case show
    }

    // First production release that contains this onboarding.
    // Existing App Store customers purchased before this cutoff should not be
    // treated as first-time users, even if an earlier version never wrote library.json.
    private static let onboardingReleaseCutoff = Date(timeIntervalSince1970: 1_791_417_600)

    @State private var decision: Decision = .checking
    let onComplete: () -> Void

    var body: some View {
        Group {
            switch decision {
            case .checking:
                ProgressView("Preparing Recipe Pals…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RecipeTheme.canvas)
                    .task {
                        await resolveExistingInstall()
                    }

            case .show:
                FirstLaunchFlowView(onComplete: onComplete)
            }
        }
    }

    private func resolveExistingInstall() async {
        do {
            let result = try await AppTransaction.shared
            guard case .verified(let appTransaction) = result else {
                decision = .show
                return
            }

            // appVersionID is nil for local/sandbox transactions. Apply the release
            // cutoff only to verified production App Store history.
            if appTransaction.appVersionID != nil,
                appTransaction.originalPurchaseDate < Self.onboardingReleaseCutoff
            {
                onComplete()
                return
            }
        } catch {
            // AppTransaction may be unavailable offline. Prefer skippable onboarding
            // over blocking a genuine new user from the app.
        }

        decision = .show
    }
}

private enum RecipeTab: String, CaseIterable, Identifiable {
    case recipes
    case plan
    case groceries
    case profile

    var id: Self {
        self
    }

    func neighbor(in direction: RecipeHorizontalSwipe) -> Self? {
        let tabs = Self.allCases
        guard let index = tabs.firstIndex(of: self) else {
            return nil
        }
        let adjacentIndex = index + (direction == .next ? 1 : -1)
        guard tabs.indices.contains(adjacentIndex) else {
            return nil
        }
        return tabs[adjacentIndex]
    }

    var title: LocalizedStringKey {
        switch self {
        case .recipes: "Recipes"
        case .plan: "Plan"
        case .groceries: "Groceries"
        case .profile: "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .recipes: "book.closed"
        case .plan: "calendar"
        case .groceries: "basket"
        case .profile: "person.crop.circle"
        }
    }
}
