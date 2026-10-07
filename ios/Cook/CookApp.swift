import SwiftUI
import CookCore

@main
struct CookApp: App {
    @State private var store: CookStore

    init() {
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
                .tint(CookTheme.accent)
                .font(CookTheme.body())
                .preferredColorScheme(colorScheme)
        }
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
            TabView {
                Tab("Recipes", systemImage: "book.closed") {
                    NavigationStack { RecipesView() }
                }
                Tab("Groceries", systemImage: "basket") {
                    NavigationStack { GroceriesView() }
                }
                Tab("Profile", systemImage: "person.crop.circle") {
                    NavigationStack { ProfileView() }
                }
            }
        }
    }
}
