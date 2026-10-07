import SwiftUI

struct SettingsHubView: View {
    var body: some View {
        List {
            Section("Account") {
                NavigationLink { AccountView() } label: { SettingsRow("Cook Account","Sign in, password and account data","person.crop.circle") }
                NavigationLink { SubscriptionView() } label: { SettingsRow("Subscription","Plan, restore purchases and manage billing","sparkles") }
                NavigationLink { CloudSyncSettingsView() } label: { SettingsRow("Cloud Sync","Sync status, local data and conflicts","arrow.triangle.2.circlepath.icloud") }
            }
            Section("App preferences") {
                NavigationLink { AppearanceSettingsView() } label: { SettingsRow("Appearance","Theme, text and recipe imagery","circle.lefthalf.filled") }
                NavigationLink { NotificationPreferencesView() } label: { SettingsRow("Notifications","Cooking timer reminders","bell") }
                NavigationLink { CookingSettingsView() } label: { SettingsRow("Cooking","Screen awake and cooking behavior","frying.pan") }
                NavigationLink { GrocerySettingsView() } label: { SettingsRow("Groceries","Consolidation and recipe sources","basket") }
                NavigationLink { MealPlanSettingsView() } label: { SettingsRow("Meal Plan","Week start and meal types","calendar") }
            }
            Section("Data & support") {
                NavigationLink { DataPrivacySettingsView() } label: { SettingsRow("Data & Privacy","Export, delete and privacy details","hand.raised") }
                NavigationLink { HelpCenterView() } label: { SettingsRow("Help & Support","Guides and troubleshooting","questionmark.circle") }
                NavigationLink { AboutSettingsView() } label: { SettingsRow("About Cook","Version, licenses and acknowledgements","info.circle") }
            }
        }
        .navigationTitle("Settings")
    }
}
private struct SettingsRow:View{
 let title:String;let subtitle:String;let icon:String
 init(_ title:String,_ subtitle:String,_ icon:String){self.title=title;self.subtitle=subtitle;self.icon=icon}
 var body:some View{HStack(spacing:14){Image(systemName:icon).frame(width:32).foregroundStyle(CookTheme.accent);VStack(alignment:.leading,spacing:3){Text(title);Text(subtitle).font(.caption).foregroundStyle(.secondary)}}.frame(minHeight:50)}
}

struct CloudSyncSettingsView:View{
 @AppStorage("cook.sync.mode")private var mode="Automatic"
 var body:some View{Form{Section("Status"){LabeledContent("Account",value:"Not connected");LabeledContent("Last synced",value:"Never");LabeledContent("Status",value:"Local only");Button("Sync Now"){}.disabled(true)};Section("Sync behavior"){Picker("Update",selection:$mode){Text("Automatic").tag("Automatic");Text("Wi-Fi Only").tag("Wi-Fi Only");Text("Manually").tag("Manually")}};Section{Text("Cloud Sync activates after a Cook account is connected. Existing local recipes are never silently overwritten.").foregroundStyle(.secondary)}}.navigationTitle("Cloud Sync")}
}

struct AppearanceSettingsView:View{
 @Environment(CookStore.self)private var store
 @State private var error:String?
 var body:some View{Form{Section("Theme"){Picker("Appearance",selection:Binding(get:{store.settings.appearance},set:{v in update{ $0.appearance=v }})){ForEach(AppAppearance.allCases){Text($0.rawValue).tag($0)}}};Section("Recipe display"){Toggle("Show image placeholders",isOn:.constant(true));Text("Cook uses Dynamic Type automatically. Text size follows iOS Settings → Display & Brightness → Text Size.").font(.footnote).foregroundStyle(.secondary)}}.navigationTitle("Appearance").alert("Couldn’t save",isPresented:.init(get:{error != nil},set:{if !$0{error=nil}})){Button("OK",role:.cancel){error=nil}}message:{Text(error ?? "")}}
 func update(_ body:(inout CookSettings)->Void){var s=store.settings;body(&s);do{try store.updateSettings(s)}catch{self.error=error.localizedDescription}}
}

struct CookingSettingsView:View{
 @Environment(CookStore.self)private var store;@State private var error:String?
 var body:some View{Form{Section{Toggle("Keep Screen Awake",isOn:binding(\.keepScreenAwake));Toggle("Timer Notifications",isOn:binding(\.timerNotifications))}footer:{Text("Timers never advance a recipe step automatically. You stay in control of when to continue.")};Section("During cooking"){LabeledContent("Navigation",value:"Full screen");LabeledContent("Ingredient checkoff",value:"Remembered per session");LabeledContent("Interrupted session",value:"Restored")}}.navigationTitle("Cooking")}
 func binding(_ key:WritableKeyPath<CookSettings,Bool>)->Binding<Bool>{Binding(get:{store.settings[keyPath:key]},set:{v in var s=store.settings;s[keyPath:key]=v;do{try store.updateSettings(s)}catch{error=error.localizedDescription}})}
}

struct GrocerySettingsView:View{
 @AppStorage("cook.grocery.consolidate")private var consolidate=true
 @AppStorage("cook.grocery.sources")private var sources=true
 var body:some View{Form{Section{Toggle("Consolidate compatible ingredients",isOn:$consolidate);Toggle("Show recipe names",isOn:$sources)}footer:{Text("Cook only consolidates compatible explicit quantities. “To taste”, ranges and incompatible units stay separate.")};Section("Organization"){LabeledContent("Grouping",value:"Grocery category");LabeledContent("Bought items",value:"Can be hidden or cleared")}}.navigationTitle("Groceries")}
}

struct MealPlanSettingsView:View{
 @AppStorage("cook.meal.weekStart")private var weekStart="System Default"
 var body:some View{Form{Section{Picker("Week Starts On",selection:$weekStart){Text("System Default").tag("System Default");Text("Sunday").tag("Sunday");Text("Monday").tag("Monday")}};Section("Meal types"){ForEach(["Breakfast","Lunch","Dinner"],id:\.self){Text($0)};Text("Custom meal types are reserved for a later release.").font(.footnote).foregroundStyle(.secondary)}}.navigationTitle("Meal Plan")}
}
