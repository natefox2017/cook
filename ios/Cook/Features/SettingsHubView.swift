import CookCore
import SwiftUI

struct SettingsHubView: View {
    var body: some View {
        List {
            Section("Account") {
                NavigationLink {
                    AccountView()
                } label: {
                    SettingsRow("Cook Account", "person.crop.circle")
                }

                NavigationLink {
                    SubscriptionView()
                } label: {
                    SettingsRow("Subscription", "sparkles")
                }

                NavigationLink {
                    CloudSyncSettingsView()
                } label: {
                    SettingsRow("Cloud Sync", "arrow.triangle.2.circlepath.icloud")
                }
            }

            Section("Learn") {
                NavigationLink {
                    GettingStartedGuideView()
                } label: {
                    SettingsRow("Getting Started", "lightbulb")
                }

                NavigationLink {
                    HelpCenterView()
                } label: {
                    SettingsRow("Help & Support", "questionmark.circle")
                }
            }

            Section("App preferences") {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    SettingsRow("Appearance", "circle.lefthalf.filled")
                }

                NavigationLink {
                    NotificationPreferencesView()
                } label: {
                    SettingsRow("Notifications", "bell")
                }

                NavigationLink {
                    CookingSettingsView()
                } label: {
                    SettingsRow("Cooking", "frying.pan")
                }

                NavigationLink {
                    GrocerySettingsView()
                } label: {
                    SettingsRow("Groceries", "basket")
                }

                NavigationLink {
                    MealPlanSettingsView()
                } label: {
                    SettingsRow("Meal Plan", "calendar")
                }
            }

            Section("Data & about") {
                NavigationLink {
                    DataPrivacySettingsView()
                } label: {
                    SettingsRow("Data & Privacy", "hand.raised")
                }

                NavigationLink {
                    AboutSettingsView()
                } label: {
                    SettingsRow("About Cook", "info.circle")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(CookTheme.canvas)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsRow: View {
    let title: String
    let icon: String

    init(_ title: String, _ icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 32)
                .foregroundStyle(CookTheme.accentForeground)
            Text(title)
        }
        .frame(minHeight: 50)
    }
}

@MainActor
struct CloudSyncSettingsView: View {
    @State private var auth = CookAuthService.shared
    @AppStorage("cook.sync.mode") private var mode = "Automatic"

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Account", value: accountStatus)
                LabeledContent("Last synced", value: "Never")
                LabeledContent("Cloud data", value: cloudStatus)
            }

            Section("Sync behavior") {
                Picker("Update", selection: $mode) {
                    Text("Automatic").tag("Automatic")
                    Text("Wi-Fi Only").tag("Wi-Fi Only")
                    Text("Manually").tag("Manually")
                }
            } footer: {
                Text("Cloud sync remains unavailable until the production Supabase sync service is connected. Account sign-in and cloud data sync are separate steps.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(CookTheme.canvas)
        .navigationTitle("Cloud Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var accountStatus: String {
        switch auth.state {
        case .signedIn(_, let email):
            return email ?? "Signed in"
        case .authenticating, .loading:
            return "Checking…"
        default:
            return "Not connected"
        }
    }

    private var cloudStatus: String {
        if case .signedIn = auth.state {
            return "Not configured"
        }
        return "Local only"
    }
}

struct AppearanceSettingsView: View {
    @Environment(CookStore.self) private var store
    @State private var error: String?

    var body: some View {
        Form {
            Section("Theme") {
                Picker(
                    "Appearance",
                    selection: Binding(
                        get: { store.settings.appearance },
                        set: { value in update { $0.appearance = value } }
                    )
                ) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.rawValue).tag(appearance)
                    }
                }
            }

            Section("Recipe display") {
                LabeledContent("Recipe image placeholders", value: "On")
            }
        }
        .navigationTitle("Appearance")
        .alert(
            "Couldn’t save",
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )
        ) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func update(_ body: (inout CookSettings) -> Void) {
        var settings = store.settings
        body(&settings)
        do {
            try store.updateSettings(settings)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct CookingSettingsView: View {
    @Environment(CookStore.self) private var store
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("Keep Screen Awake", isOn: binding(\.keepScreenAwake))
                Toggle("Timer Notifications", isOn: binding(\.timerNotifications))
            }

            Section("During cooking") {
                LabeledContent("Navigation", value: "Full screen")
                LabeledContent("Ingredient checkoff", value: "Remembered per session")
                LabeledContent("Interrupted session", value: "Restored")
            }
        }
        .navigationTitle("Cooking")
    }

    private func binding(_ key: WritableKeyPath<CookSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.settings[keyPath: key] },
            set: { value in
                var settings = store.settings
                settings[keyPath: key] = value
                do {
                    try store.updateSettings(settings)
                } catch {
                    error = error.localizedDescription
                }
            }
        )
    }
}

struct GrocerySettingsView: View {
    @AppStorage("cook.grocery.consolidate") private var consolidate = true
    @AppStorage("cook.grocery.sources") private var sources = true

    var body: some View {
        Form {
            Section {
                Toggle("Consolidate compatible ingredients", isOn: $consolidate)
                Toggle("Show recipe names", isOn: $sources)
            }

            Section("Organization") {
                LabeledContent("Grouping", value: "Grocery category")
                LabeledContent("Bought items", value: "Can be hidden or cleared")
            }
        }
        .navigationTitle("Groceries")
    }
}

struct MealPlanSettingsView: View {
    @AppStorage("cook.meal.weekStart") private var weekStart = "System Default"

    var body: some View {
        Form {
            Section {
                Picker("Week Starts On", selection: $weekStart) {
                    Text("System Default").tag("System Default")
                    Text("Sunday").tag("Sunday")
                    Text("Monday").tag("Monday")
                }
            }

            Section("Meal types") {
                ForEach(["Breakfast", "Lunch", "Dinner"], id: \.self) { meal in
                    Text(meal)
                }
            }
        }
        .navigationTitle("Meal Plan")
    }
}
