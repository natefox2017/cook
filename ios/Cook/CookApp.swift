import SwiftUI
import CookCore

@main
@MainActor
struct CookApp: App {
    @State private var store: CookStore
    @State private var subscriptions = SubscriptionStore()

    init() {
        CookTheme.installUIKitTypography()
        _ = CookAuthService.shared
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let localStore = CookStore(fileURL: isUITesting ? nil : CookStore.defaultFileURL())
        if isUITesting {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("cook.cookingSession.") {
                UserDefaults.standard.removeObject(forKey: key)
            }
            do { try localStore.loadSampleRecipes() }
            catch { assertionFailure("UI test fixtures could not be loaded: \(error)") }
        }
        _store = State(initialValue: localStore)
    }

    var body: some Scene {
        WindowGroup {
            CookRootView()
                .environment(store)
                .onOpenURL { CookAuthService.shared.handleAuthCallback($0) }
                .tint(CookTheme.accent)
                .font(CookTheme.body())
                .preferredColorScheme(colorScheme)
                .environment(\.locale, appLocale)
        }
    }

    private var appLocale: Locale {
        Locale(identifier: "en")
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
    @State private var selectedTab: CookTab = .recipes

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
        } else {
            TabView(selection: $selectedTab) {
                NavigationStack { RecipesView().toolbar(.hidden, for: .tabBar) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { CookTabBar(selection: $selectedTab) }
                    .tag(CookTab.recipes)
                NavigationStack { MealPlanView().toolbar(.hidden, for: .tabBar) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { CookTabBar(selection: $selectedTab) }
                    .tag(CookTab.plan)
                NavigationStack { GroceriesView().toolbar(.hidden, for: .tabBar) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { CookTabBar(selection: $selectedTab) }
                    .tag(CookTab.groceries)
                NavigationStack { ProfileView().toolbar(.hidden, for: .tabBar) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { CookTabBar(selection: $selectedTab) }
                    .tag(CookTab.profile)
            }
        }
    }
}

private enum CookTab: String, CaseIterable, Identifiable {
    case recipes, plan, groceries, profile

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

private struct CookTabBar: View {
    @Binding var selection: CookTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CookTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 20))
                        Text(tab.title)
                            .font(CookTheme.text(10, relativeTo: .caption2))
                    }
                    .foregroundStyle(selection == tab ? CookTheme.accent : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background {
                        if selection == tab {
                            Capsule().fill(Color.primary.opacity(0.08))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("tab.\(tab.rawValue)")
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(5)
        .background(CookTheme.canvas, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
        .padding(.horizontal, CookSpacing.pageInset)
        .padding(.bottom, 4)
    }
}
