// Developer: gengyun
// Purpose: Implements RecipePouch data, privacy, help, and about settings screens.

import RecipeCore
import SwiftUI
import UniformTypeIdentifiers

struct DataPrivacySettingsView: View {
    @Environment(RecipeStore.self) private var store
    @Environment(CloudSyncCoordinator.self) private var cloudSync
    @State private var auth = RecipeAuthService.shared

    @State private var exportsData = false
    @State private var choosesExportFormat = false
    @State private var exportDocument = RecipeExportDocument(data: Data())
    @State private var confirmsLocalDelete = false
    @State private var isDeletingLocalData = false
    @State private var confirmsAccountDelete = false
    @State private var message: String?

    var body: some View {
        List {
            Section("Your data") {
                Button("Export Data") {
                    choosesExportFormat = true
                }

                NavigationLink("What RecipePouch Stores") {
                    StoredDataView()
                }

                NavigationLink("Privacy Summary") {
                    PrivacySummaryView()
                }
            }

            Section("Delete") {
                Button("Delete All Local Data", role: .destructive) {
                    confirmsLocalDelete = true
                }

                if isSignedIn {
                    Button(
                        "Delete RecipePouch Account & Cloud Data",
                        role: .destructive
                    ) {
                        confirmsAccountDelete = true
                    }
                } else {
                    HStack {
                        Text("Delete RecipePouch Account & Cloud Data")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Sign in required")
                            .font(
                                RecipeTheme.text(
                                    12,
                                    weight: .regular,
                                    relativeTo: .caption
                                )
                            )
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listSectionSpacing(RecipeSpacing.medium)
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .navigationTitle("Data & Privacy")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
        .toolbar(.hidden, for: .tabBar)
        .fileExporter(
            isPresented: $exportsData,
            document: exportDocument,
            contentType: exportDocument.contentType,
            defaultFilename: exportDocument.filename
        ) { result in
            if let feedback = RecipeExportFormat.feedback(for: result) {
                message = feedback
            }
        }
        .confirmationDialog(
            "Choose export format",
            isPresented: $choosesExportFormat,
            titleVisibility: .visible
        ) {
            Button("Recipes (JSON)") { prepareExport(.recipesJSON) }
            Button("Recipes (HTML)") { prepareExport(.recipesHTML) }
            Button("All Local Library Data (JSON)") { prepareExport(.allLibraryJSON) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Recipe JSON/HTML includes source text and Collections but not photos. Full library JSON includes groceries, meal plan and local preferences. No in-app restore is available."
            )
        }
        .confirmationDialog(
            "Delete all local RecipePouch data?",
            isPresented: $confirmsLocalDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Local Data", role: .destructive) {
                guard !isDeletingLocalData else { return }
                isDeletingLocalData = true
                Task {
                    defer { isDeletingLocalData = false }
                    do {
                        try await RecipeLocalDataDeletion.erase(
                            store: store,
                            cloudSync: cloudSync
                        )
                        exportDocument = RecipeExportDocument(data: Data())
                        message = "Local RecipePouch data deleted."
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
            .disabled(isDeletingLocalData)
        } message: {
            Text(
                "Sign out first to erase only this iPhone's data. Cloud data and your subscription are not deleted; signing in again may restore synced recipes."
            )
        }
        .confirmationDialog(
            "Delete RecipePouch account?",
            isPresented: $confirmsAccountDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Account & Cloud Data", role: .destructive) {
                Task {
                    do {
                        try await cloudSync.deleteAccountAndCloudData()
                        message = String(localized: LocalizedStringResource("RecipePouch account and cloud data deleted. Local data on this iPhone was kept.", locale: RecipeLanguage.active))
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
        } message: {
            Text(
                String(localized: LocalizedStringResource("This deletes the signed-in RecipePouch account and cloud data. Local data on this iPhone stays until you delete it separately. This does not cancel an App Store subscription.", locale: RecipeLanguage.active)))
        }
        .alert(
            "Data & Privacy",
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var isSignedIn: Bool {
        if case .signedIn = auth.state { return true }
        return false
    }

    private func prepareExport(_ format: RecipeExportFormat) {
        do {
            exportDocument = try format.makeDocument(from: store)
            exportsData = true
        } catch {
            message = String(localized: LocalizedStringResource("Export failed: \(error.localizedDescription)", locale: RecipeLanguage.active))
        }
    }
}

struct StoredDataView: View {
    var body: some View {
        List {
            Label("Recipes, notes and original sources", systemImage: "book")
            Label("Groceries and recipe references", systemImage: "basket")
            Label("Meal plan", systemImage: "calendar")
            Label(
                "Local preferences and cooking sessions",
                systemImage: "gearshape"
            )
        }
        .listSectionSpacing(RecipeSpacing.medium)
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .navigationTitle("What RecipePouch Stores")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct PrivacySummaryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RecipeSpacing.medium) {
                Text(
                    String(localized: LocalizedStringResource("RecipePouch is designed as a private recipe utility. It does not publish your recipes to a public feed.", locale: RecipeLanguage.active)))

                Text(
                    String(localized: LocalizedStringResource("Automated imports may send source material to RecipePouch’s backend only when processing is required. Provider secrets remain server-side.", locale: RecipeLanguage.active)))

                Text(
                    String(localized: LocalizedStringResource("App Store purchases are managed by Apple. Your App Store purchase identity and RecipePouch account are treated as separate identities.", locale: RecipeLanguage.active)))

                Text(
                    String(localized: LocalizedStringResource("You can export local data and request deletion of your RecipePouch account data from Settings.", locale: RecipeLanguage.active)))
            }
            .padding(RecipeSpacing.pageInset)
        }
        .background(RecipeTheme.canvas)
        .navigationTitle("Privacy Summary")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct HelpCenterView: View {
    var body: some View {
        List {
            Section("Getting started") {
                NavigationLink("Add or import a recipe") {
                    HelpArticleView(
                        title: "Add or import a recipe",
                        articleBody: "Share a link or add a photo to save a recipe."
                    )
                }
                NavigationLink("Cook with timers") {
                    HelpArticleView(
                        title: "Cook with timers",
                        articleBody: "Open a recipe and start cooking with timers."
                    )
                }
                NavigationLink("Plan meals and shop") {
                    HelpArticleView(
                        title: "Plan meals and shop",
                        articleBody: "Plan meals and add ingredients to Groceries."
                    )
                }
            }

            Section("Troubleshooting") {
                NavigationLink("Subscription not showing") {
                    HelpArticleView(
                        title: "Subscription not showing",
                        articleBody: "Restore purchases from the Subscription screen."
                    )
                }
                NavigationLink("Sync problems") {
                    HelpArticleView(
                        title: "Sync problems",
                        articleBody: "Check your account and Cloud Sync status."
                    )
                }
                NavigationLink("Import needs review") {
                    HelpArticleView(
                        title: "Import needs review",
                        articleBody: "Review missing details using the original source."
                    )
                }
            }
        }
        .listSectionSpacing(RecipeSpacing.medium)
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct HelpArticleView: View {
    let title: String
    let articleBody: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RecipeSpacing.medium) {
                Text(LocalizedStringKey(articleBody))
                    .font(
                        RecipeTheme.text(
                            17,
                            weight: .regular,
                            relativeTo: .body
                        )
                    )
            }
            .padding(RecipeSpacing.pageInset)
        }
        .background(RecipeTheme.canvas)
        .navigationTitle(Text(LocalizedStringKey(title)))
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct AboutSettingsView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(RecipeTheme.accentForeground)
                    Text("RecipePouch")
                        .font(RecipeTheme.heading(.title))
                }
            }

            Section("App") {
                LabeledContent("Version", value: RecipeVersion.display)

                NavigationLink("Open Source Licenses") {
                    LicensesView()
                }

                NavigationLink("Acknowledgements") {
                    AcknowledgementsView()
                }
            }

            Section("Legal") {
                Link(
                    "Apple Standard EULA",
                    destination: URL(
                        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
                    )!
                )
            }
        }
        .listSectionSpacing(RecipeSpacing.medium)
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .navigationTitle("About RecipePouch")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct LicensesView: View {
    var body: some View {
        List {
            Section("Lora") {
                Text(
                    String(localized: LocalizedStringResource("Copyright The Lora Project Authors. Licensed under the SIL Open Font License 1.1.", locale: RecipeLanguage.active)))
            }

            Section("System frameworks") {
                Text(
                    String(localized: LocalizedStringResource("SwiftUI, StoreKit, AuthenticationServices, Vision, and related Apple frameworks are used under Apple platform terms.", locale: RecipeLanguage.active)))
            }
        }
        .listSectionSpacing(RecipeSpacing.medium)
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct AcknowledgementsView: View {
    var body: some View {
        ScrollView {
            Text(
                String(localized: LocalizedStringResource("RecipePouch’s interaction model is informed by established private recipe managers: collect recipes, organize them, cook step-by-step, plan meals, and shop from ingredients. RecipePouch’s implementation and visual system remain its own.", locale: RecipeLanguage.active))
            )
            .padding(RecipeSpacing.pageInset)
        }
        .background(RecipeTheme.canvas)
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
        .toolbar(.hidden, for: .tabBar)
    }
}
