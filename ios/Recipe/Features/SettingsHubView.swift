import SwiftUI
import RecipeCore

struct SettingsHubView: View {
    var body: some View {
        List {
            Section("Account") {
                NavigationLink { AccountView() } label: { SettingsRow("Recipe Account","person.crop.circle") }
                NavigationLink { SubscriptionView() } label: { SettingsRow("Subscription","sparkles") }
                NavigationLink { CloudSyncSettingsView() } label: { SettingsRow("Cloud Sync","arrow.triangle.2.circlepath.icloud") }
            }
            Section("App preferences") {
                NavigationLink { AppearanceSettingsView() } label: { SettingsRow("Appearance","circle.lefthalf.filled") }
                NavigationLink { NotificationPreferencesView() } label: { SettingsRow("Notifications","bell") }
                NavigationLink { CookingSettingsView() } label: { SettingsRow("Cooking","frying.pan") }
                NavigationLink { GrocerySettingsView() } label: { SettingsRow("Groceries","basket") }
                NavigationLink { MealPlanSettingsView() } label: { SettingsRow("Meal Plan","calendar") }
            }
            Section("Data & support") {
                NavigationLink { DataPrivacySettingsView() } label: { SettingsRow("Data & Privacy","hand.raised") }
                NavigationLink { HelpCenterView() } label: { SettingsRow("Help & Support","questionmark.circle") }
                NavigationLink { AboutSettingsView() } label: { SettingsRow("About Recipe","info.circle") }
            }
        }
        .listSectionSpacing(RecipeSpacing.medium)
        .navigationTitle("Settings").navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
    }
}
private struct SettingsRow:View{
 let title:String;let icon:String
 init(_ title:String,_ icon:String){self.title=title;self.icon=icon}
 var body:some View{HStack(spacing:14){Image(systemName:icon).frame(width:32).foregroundStyle(RecipeTheme.accentForeground);Text(title)}.frame(minHeight:50)}
}

struct CloudSyncSettingsView:View{
 @AppStorage("recipe.sync.mode")private var mode="Automatic"
 var body:some View{Form{Section("Status"){LabeledContent("Account",value:"Not connected");LabeledContent("Last synced",value:"Never");LabeledContent("Status",value:"Local only");LabeledContent("Manual Sync", value: "Available after sign in")};Section("Sync behavior"){Picker("Update",selection:$mode){Text("Automatic").tag("Automatic");Text("Wi-Fi Only").tag("Wi-Fi Only");Text("Manually").tag("Manually")}}}.navigationTitle("Cloud Sync").navigationBarTitleDisplayMode(.inline)}
}

struct AppearanceSettingsView:View{
 @Environment(RecipeStore.self)private var store
 @State private var error:String?
 var body:some View{Form{Section("Theme"){Picker("Appearance",selection:Binding(get:{store.settings.appearance},set:{v in update{ $0.appearance=v }})){ForEach(AppAppearance.allCases){Text($0.rawValue).tag($0)}}};Section("Recipe display"){LabeledContent("Recipe image placeholders", value: "On")}}.navigationTitle("Appearance").navigationBarTitleDisplayMode(.inline).alert("Couldn’t save",isPresented:.init(get:{error != nil},set:{if !$0{error=nil}})){Button("OK",role:.cancel){error=nil}}message:{Text(error ?? "")}}
 func update(_ body:(inout RecipeSettings)->Void){var s=store.settings;body(&s);do{try store.updateSettings(s)}catch{self.error=error.localizedDescription}}
}

struct CookingSettingsView:View{
 @Environment(RecipeStore.self)private var store;@State private var error:String?
 var body:some View{Form{Section{Toggle("Keep Screen Awake",isOn:binding(\.keepScreenAwake));Toggle("Timer Notifications",isOn:binding(\.timerNotifications))};Section("During cooking"){LabeledContent("Navigation",value:"Full screen");LabeledContent("Ingredient checkoff",value:"Remembered per session");LabeledContent("Interrupted session",value:"Restored")}}.navigationTitle("Cooking").navigationBarTitleDisplayMode(.inline)}
 func binding(_ key:WritableKeyPath<RecipeSettings,Bool>)->Binding<Bool>{Binding(get:{store.settings[keyPath:key]},set:{v in var s=store.settings;s[keyPath:key]=v;do{try store.updateSettings(s)}catch let saveError{error=saveError.localizedDescription}})}
}

struct GrocerySettingsView:View{
 @AppStorage("recipe.grocery.consolidate")private var consolidate=true
 @AppStorage("recipe.grocery.sources")private var sources=true
 var body:some View{Form{Section{Toggle("Consolidate compatible ingredients",isOn:$consolidate);Toggle("Show recipe names",isOn:$sources)};Section("Organization"){LabeledContent("Grouping",value:"Grocery category");LabeledContent("Bought items",value:"Can be hidden or cleared")}}.navigationTitle("Groceries").navigationBarTitleDisplayMode(.inline)}
}

struct MealPlanSettingsView:View{
 @AppStorage("recipe.meal.weekStart")private var weekStart="System Default"
 var body:some View{Form{Section{Picker("Week Starts On",selection:$weekStart){Text("System Default").tag("System Default");Text("Sunday").tag("Sunday");Text("Monday").tag("Monday")}};Section("Meal types"){ForEach(["Breakfast","Lunch","Dinner"],id:\.self){Text($0)}}}.navigationTitle("Meal Plan").navigationBarTitleDisplayMode(.inline)}
}
