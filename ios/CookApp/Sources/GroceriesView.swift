// Developer: gengyun
// Purpose: Prototype grocery list screen.

import SwiftUI
struct GroceriesView:View{
 @Environment(AppStore.self)private var store;@State private var hideChecked=false;@State private var newItem=""
 var items:[GroceryItem]{hideChecked ? store.groceries.filter{!$0.checked}:store.groceries}
 var groups:[String:[GroceryItem]]{Dictionary(grouping:items,by:{$0.aisle})}
 var body:some View{List{
  Section{HStack{TextField("Add an item",text:$newItem).submitLabel(.done).onSubmit{add()};Button{add()}label:{Image(systemName:"plus.circle.fill")}.disabled(newItem.trimmingCharacters(in:.whitespaces).isEmpty)}}
  if items.isEmpty{ContentUnavailableView("Your list is empty",systemImage:"cart",description:Text("Add an item or ingredients from a recipe."))}
  else{ForEach(groups.keys.sorted(),id:\.self){aisle in Section(aisle){ForEach(groups[aisle] ?? []){x in Button{store.toggleGrocery(x.id)}label:{HStack{Image(systemName:x.checked ? "checkmark.circle.fill":"circle").foregroundStyle(CookTheme.green);VStack(alignment:.leading){Text(x.name).foregroundStyle(.primary);HStack{if !x.amount.isEmpty{Text(x.amount)};if let rid=x.recipeID,let r=store.recipes.first(where:{$0.id==rid}){Text("· \(r.title)")}}.font(.caption).foregroundStyle(.secondary)};Spacer()}}}}}}
 }.navigationTitle("Groceries").toolbar{Menu{Toggle("Hide checked",isOn:$hideChecked);Button("Add this week’s meal plan"){store.addPlannedGroceries()};Button("Clear checked",role:.destructive){store.clearChecked()}}label:{Image(systemName:"line.3.horizontal.decrease.circle")}}}
 func add(){store.addManualGrocery(newItem);newItem=""}
}
