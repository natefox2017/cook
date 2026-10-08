import StoreKit
import SwiftUI
import RecipeCore

@main
@MainActor
struct RecipeApp: App {
    @State private var store: RecipeStore
    @State private var subscriptions = SubscriptionStore()
    private let isUITesting: Bool

    init() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("cook.") {
            let recipeKey = "recipe." + key.dropFirst("cook.".count)
            if defaults.object(forKey: recipeKey) == nil, let value = defaults.object(forKey: key) {
                defaults.set(value, forKey: recipeKey)
            }
        }

        RecipeTheme.installUIKitTypography()

        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("--uitesting")
        self.isUITesting = isUITesting

        _ = RecipeAuthService.shared

        let libraryURL = RecipeStore.defaultFileURL()
        if !isUITesting,
           FileManager.default.fileExists(atPath: libraryURL.path),
           UserDefaults.standard.object(forKey: FirstLaunchFlowView.completionKey) == nil {
            // Existing installs with a persisted library should not be mistaken for new users
            // when this onboarding key is introduced for the first time.
            UserDefaults.standard.set(true, forKey: FirstLaunchFlowView.completionKey)
        }

        let localStore = RecipeStore(fileURL: isUITesting ? nil : libraryURL)
        if isUITesting {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("recipe.cookingSession.") || key.hasPrefix("cook.cookingSession.") {
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

    var body: some Scene {
        WindowGroup {
            RecipeRootView(bypassOnboarding: isUITesting)
                .environment(store)
                .environment(subscriptions)
                .onOpenURL { RecipeAuthService.shared.handleAuthCallback($0) }
                .tint(RecipeTheme.accent)
                .font(RecipeTheme.body())
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

private struct RecipeRootView: View {
    @Environment(RecipeStore.self) private var store
    @AppStorage(FirstLaunchFlowView.completionKey) private var hasCompletedOnboarding = false
    @State private var selectedTab: RecipeTab = .recipes

    let bypassOnboarding: Bool

    var body: some View {
        if let message = store.loadError {
            NavigationStack {
                EmptyStateView(
                    title: "Your saved library needs attention",
                    message: "Recipe couldn't read your saved library. The file has been left unchanged.\n\n\(message)",
                    systemImage: "externaldrive.badge.exclamationmark",
                    actionTitle: "Try again",
                    action: { store.reload() }
                )
                .padding()
                .navigationTitle("Recipe")
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
                }
                .tabItem {
                    Label(RecipeTab.recipes.title, systemImage: RecipeTab.recipes.symbol)
                        .accessibilityIdentifier("tab.\(RecipeTab.recipes.rawValue)")
                }
                .tag(RecipeTab.recipes)

                NavigationStack {
                    MealPlanView()
                }
                .tabItem {
                    Label(RecipeTab.plan.title, systemImage: RecipeTab.plan.symbol)
                        .accessibilityIdentifier("tab.\(RecipeTab.plan.rawValue)")
                }
                .tag(RecipeTab.plan)

                NavigationStack {
                    GroceriesView()
                }
                .tabItem {
                    Label(RecipeTab.groceries.title, systemImage: RecipeTab.groceries.symbol)
                        .accessibilityIdentifier("tab.\(RecipeTab.groceries.rawValue)")
                }
                .tag(RecipeTab.groceries)

                NavigationStack {
                    ProfileView()
                }
                .tabItem {
                    Label(RecipeTab.profile.title, systemImage: RecipeTab.profile.symbol)
                        .accessibilityIdentifier("tab.\(RecipeTab.profile.rawValue)")
                }
                .tag(RecipeTab.profile)
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
                    .background(RecipeTheme.canvas)
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

private enum RecipeTab: String, Identifiable {
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
