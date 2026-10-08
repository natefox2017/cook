import SwiftUI
@main struct RecipeApp: App {
 @State private var store = AppStore()
 init(){let defaults=UserDefaults.standard;for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("cook."){let recipeKey="recipe."+key.dropFirst("cook.".count);if defaults.object(forKey:recipeKey)==nil,let value=defaults.object(forKey:key){defaults.set(value,forKey:recipeKey)}}}
 var body: some Scene { WindowGroup { RootView().environment(store).tint(RecipeTheme.green) } }
}
struct RootView: View {
 @State private var tab=0; @State private var add=false
 var body: some View {
  TabView(selection:$tab) {
   NavigationStack { RecipeLibraryView(showingAdd:$add) }.tabItem{Label("Recipes",systemImage:"book.closed")}.tag(0)
   NavigationStack { GroceriesView() }.tabItem{Label("Groceries",systemImage:"cart")}.tag(1)
   NavigationStack { ProfileView() }.tabItem{Label("Me",systemImage:"person.crop.circle")}.tag(2)
  }.sheet(isPresented:$add){NavigationStack{AddRecipeView()}}
 }
}
