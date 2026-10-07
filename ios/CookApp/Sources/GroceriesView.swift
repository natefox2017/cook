import SwiftUI
struct GroceriesView:View{
 @Environment(AppStore.self)private var store;@State private var hideChecked=false
 var items:[GroceryItem]{hideChecked ? store.groceries.filter{!$0.checked}:store.groceries}
 var body:some View{List{if items.isEmpty{ContentUnavailableView("Your list is empty",systemImage:"cart",description:Text("Add ingredients from a recipe."))}else{ForEach(items){x in Button{store.toggleGrocery(x.id)}label:{HStack{Image(systemName:x.checked ? "checkmark.circle.fill":"circle").foregroundStyle(CookTheme.green);VStack(alignment:.leading){Text(x.name).foregroundStyle(.primary);Text(x.amount).font(.caption).foregroundStyle(.secondary)};Spacer()}}}}}.navigationTitle("Groceries").toolbar{Menu{Toggle("Hide checked",isOn:$hideChecked);Button("Clear checked",role:.destructive){store.clearChecked()}}label:{Image(systemName:"line.3.horizontal.decrease.circle")}}}
}
