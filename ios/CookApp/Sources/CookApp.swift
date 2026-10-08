// Developer: gengyun
// Purpose: Prototype app entry point and root navigation.

import SwiftUI
@main struct CookApp: App {
 @State private var store = AppStore()
 var body: some Scene { WindowGroup { RootView().environment(store).tint(CookTheme.green) } }
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
