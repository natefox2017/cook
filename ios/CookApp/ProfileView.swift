import SwiftUI

struct ProfileView: View {
    @Environment(CookStore.self) private var store
    var body: some View {
        List {
            Section {
                Text("Your personal cookbook").font(CookTheme.heading(.title2))
                Text("\(store.snapshot.recipes.count) recipes saved on this device")
                    .foregroundStyle(.secondary)
            }
            Section("Account") {
                Label("Local collection", systemImage: "person.crop.circle")
                Text("No account is connected. Your recipes stay on this device.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Import help") {
                Text("Paste a link or save a photo in Add a Recipe. Cook keeps the original source.")
                Text("Automatic processing and the system share extension aren't connected in this build.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Data") {
                Text("Recipes, grocery items and saved sources are stored locally.")
                Text("Deleting the app removes this local collection. Cloud backup, export and account deletion aren't connected yet.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Label("Follows your device", systemImage: "circle.lefthalf.filled")
                Text("Cook supports your system appearance, text size and transparency settings.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Profile").scrollContentBackground(.hidden).background(CookTheme.paper)
    }
}
