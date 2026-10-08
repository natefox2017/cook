import StoreKit
import SwiftUI
import CookCore

@main
@MainActor
struct CookApp: App {
    @State private var store: CookStore
    @State private var subscriptions = SubscriptionStore()
    private let isUITesting: Bool

    init() {
        CookTheme.installUIKitTypography()

        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("--uitesting")
        self.isUITesting = isUITesting

        _ = CookAuthService.shared

        let libraryURL = CookStore.defaultFileURL()
        if !isUITesting,
           FileManager.default.fileExists(atPath: libraryURL.path),
           UserDefaults.standard.object(forKey: FirstLaunchFlowView.completionKey) == nil {
            // Existing installs with a persisted library should not be mistaken for new users
            // when this onboarding key is introduced for the first time.
            UserDefaults.standard.set(true, forKey: FirstLaunchFlowView.completionKey)
        }

        let localStore = CookStore(fileURL: isUITesting ? nil : libraryURL)
        if !isUITesting {
            Self.migrateLegacyPreferences(into: localStore)
        }

        if isUITesting {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("cook.cookingSession.") {
                UserDefaults.standard.removeObject(forKey: key)
            }
            do {
                try localStore.loadSampleRecipes()
            } catch {
                assertionFailure("UI test fixtures could not be loaded: \(error)")
            }
        }

        _store = State(initialValue: localStore)
    }

    private static func migrateLegacyPreferences(into store: CookStore) {
        let defaults = UserDefaults.standard
        let migrationKey = "cook.settings.snapshotPreferencesMigrated"
        guard !defaults.bool(forKey: migrationKey) else { return }

        var settings = store.settings
        var hasLegacyValue = false

        if defaults.object(forKey: "cook.grocery.consolidate") != nil {
            settings.consolidateCompatibleGroceries = defaults.bool(
                forKey: "cook.grocery.consolidate"
            )
            hasLegacyValue = true
        }

        if defaults.object(forKey: "cook.grocery.sources") != nil {
            settings.showGroceryRecipeNames = defaults.bool(
                forKey: "cook.grocery.sources"
            )
            hasLegacyValue = true
        }

        if let raw = defaults.string(forKey: "cook.meal.weekStart"),
           let value = MealPlanWeekStart(rawValue: raw) {
            settings.mealPlanWeekStart = value
            hasLegacyValue = true
        }

        do {
            if hasLegacyValue {
                try store.updateSettings(settings)
            } else if store.loadError != nil {
                // Keep the migration retryable while the persisted library is unreadable.
                return
            }

            defaults.removeObject(forKey: "cook.grocery.consolidate")
            defaults.removeObject(forKey: "cook.grocery.sources")
            defaults.removeObject(forKey: "cook.meal.weekStart")
            defaults.set(true, forKey: migrationKey)
        } catch {
            // Keep legacy keys untouched so the next launch can retry after
            // persistence becomes available again.
        }
    }

    var body: some Scene {
        WindowGroup {
            CookRootView(bypassOnboarding: isUITesting)
                .environment(store)
                .environment(subscriptions)
                .onOpenURL { CookAuthService.shared.handleAuthCallback($0) }
                .tint(CookTheme.accent)
                .font(CookTheme.body())
                .preferredColorScheme(colorScheme)
                .environment(\.locale, appLocale)
        }
    }

    private var appLocale: Locale {
        isUITesting ? Locale(identifier: "en") : .autoupdatingCurrent
    }

    private var colorScheme: ColorScheme? {
        switch store.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct CookRootView: View {
    @Environment(CookStore.self) private var store
    @AppStorage(FirstLaunchFlowView.completionKey) private var hasCompletedOnboarding = false
    @State private var selectedTab: CookTab = .recipes

    let bypassOnboarding: Bool

    var body: some View {
        if let message = store.loadError {
            NavigationStack {
                EmptyStateView(
                    title: "Your saved library needs attention",
                    message: "Cook couldn't read your saved library. The file has been left unchanged.\n\n\(message)",
                    systemImage: "externaldrive.badge.exclamationmark",
                    actionTitle: "Try again",
                    action: { store.reload() }
                )
                .padding()
                .navigationTitle("Cook")
                .background(CookTheme.canvas)
            }
        } else if !hasCompletedOnboarding && !bypassOnboarding {
            FirstLaunchGateView {
                hasCompletedOnboarding = true
            }
        } else {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    RecipesView()
                }
                .tabItem {
                    Label(CookTab.recipes.title, systemImage: CookTab.recipes.symbol)
                        .accessibilityIdentifier("tab.\(CookTab.recipes.rawValue)")
                }
                .tag(CookTab.recipes)

                NavigationStack {
                    MealPlanView()
                }
                .tabItem {
                    Label(CookTab.plan.title, systemImage: CookTab.plan.symbol)
                        .accessibilityIdentifier("tab.\(CookTab.plan.rawValue)")
                }
                .tag(CookTab.plan)

                NavigationStack {
                    GroceriesView()
                }
                .tabItem {
                    Label(CookTab.groceries.title, systemImage: CookTab.groceries.symbol)
                        .accessibilityIdentifier("tab.\(CookTab.groceries.rawValue)")
                }
                .tag(CookTab.groceries)

                NavigationStack {
                    ProfileView()
                }
                .tabItem {
                    Label(CookTab.profile.title, systemImage: CookTab.profile.symbol)
                        .accessibilityIdentifier("tab.\(CookTab.profile.rawValue)")
                }
                .tag(CookTab.profile)
            }
        }
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
                ProgressView("Preparing RecipePouch…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CookTheme.canvas)
                    .task { await resolveExistingInstall() }

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
               appTransaction.originalPurchaseDate < Self.onboardingReleaseCutoff {
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

private enum CookTab: String, Identifiable {
    case recipes
    case plan
    case groceries
    case profile

    var id: Self { self }

    var title: String {
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
