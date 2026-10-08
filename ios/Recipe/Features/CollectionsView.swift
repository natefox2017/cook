import SwiftUI
import RecipeCore

struct CollectionsView:View{
 @Environment(RecipeStore.self)private var store
 @AppStorage("recipe.collections")private var encoded="Favorites"
 @State private var newName=""
 private var names:[String]{get{encoded.split(separator:"|").map(String.init)}}
 var body:some View{List{Section{HStack{TextField("New collection",text:$newName);Button("Add"){add()}.disabled(newName.trimmingCharacters(in:.whitespaces).isEmpty)}};ForEach(names,id:\.self){name in NavigationLink{nameView(name)}label:{HStack{Image(systemName:name=="Favorites" ? "heart.fill":"folder");Text(name);Spacer();Text("\(count(name))").foregroundStyle(.secondary)}}}}.navigationTitle("Collections").navigationBarTitleDisplayMode(.inline).toolbar(.hidden,for:.tabBar)}
 func count(_ n:String)->Int{n=="Favorites" ? store.recipes.filter(\.isFavorite).count:0}
 @ViewBuilder func nameView(_ n:String)->some View{List{if n=="Favorites"{ForEach(store.recipes.filter(\.isFavorite)){r in NavigationLink(r.title){RecipeDetailView(recipeID:r.id)}}}else{ContentUnavailableView("No recipes yet",systemImage:"folder",description:Text("Collection membership will sync with the Recipe account when cloud collections are enabled."))}}.navigationTitle(n).navigationBarTitleDisplayMode(.inline)}
 func add(){let v=newName.trimmingCharacters(in:.whitespacesAndNewlines);guard !v.isEmpty,!names.contains(v)else{return};encoded=(names+[v]).joined(separator:"|");newName=""}
}
