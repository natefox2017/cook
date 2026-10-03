import SwiftUI

@main
struct CookApp: App {
    @State private var store = CookStore()
    var body: some Scene {
        WindowGroup { CookRootView().environment(store).tint(CookTheme.green) }
    }
}

struct CookRootView: View {
    var body: some View {
        // Native iOS 26 TabView supplies the floating Liquid Glass capsule and safe-area behavior.
        // iOS 18 uses its standard tab bar, not a handcrafted glass imitation.
        TabView {
            Tab("Recipes", systemImage: "book") { NavigationStack { RecipeLibraryView() } }
            Tab("Groceries", systemImage: "cart") { NavigationStack { GroceriesView() } }
            Tab("Profile", systemImage: "person") { NavigationStack { ProfileView() } }
        }
    }
}
