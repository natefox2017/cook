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
    @State private var choosingExport = false
    @State private var exportChoice: RecipeExportChoice = .allLocalJSON
    @State private var exportDocument = RecipeExportFileDocument(data: Data())
    @State private var confirmsLocalDelete = false
    @State private var isDeletingLocalData = false
    @State private var confirmsAccountDelete = false
    @State private var message: String?

    var body: some View {
        List {
            Section("Your data") {
                Button("Export Recipes & Data") {
                    choosingExport = true
                }
                .confirmationDialog(
                    "Choose export format",
                    isPresented: $choosingExport,
                    titleVisibility: .visible
                ) {
                    ForEach(RecipeExportChoice.allCases) { choice in
                        Button(choice.rawValue) { prepareExport(choice) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Full JSON includes local preferences and shopping data. Recipe exports include only recipes and collections; HTML does not include photos.")
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
        .navigationTitle("Data & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .fileExporter(
            isPresented: $exportsData,
            document: exportDocument,
            contentType: exportChoice.contentType,
            defaultFilename: exportChoice.filename
        ) { result in
            switch result {
            case .success:
                message = "Export saved to Files. This is not an in-app restore backup."
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    message = error.localizedDescription
                }
            }
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
                        exportDocument = RecipeExportFileDocument(data: Data())
                        message = "Local RecipePouch data deleted."
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
            .disabled(isDeletingLocalData)
        } message: {
            Text("Sign out first to erase only this iPhone's data. Cloud data and your subscription are not deleted; signing in again may restore synced recipes.")
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
                        message = "RecipePouch account and cloud data deleted. "
                            + "Local data on this iPhone was kept."
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
        } message: {
            Text(
                "This deletes the signed-in RecipePouch account and cloud data. "
                    + "Local data on this iPhone stays until you delete it separately. "
                    + "This does not cancel an App Store subscription."
            )
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

    private func prepareExport(_ choice: RecipeExportChoice) {
        do {
            let data = try choice.exportData(from: store)
            exportChoice = choice
            exportDocument = RecipeExportFileDocument(data: data)
            exportsData = true
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Shared choices for Profile and Data & Privacy; exporting is not a restore API.
enum RecipeExportChoice: String, CaseIterable, Identifiable {
    case allLocalJSON = "All Local Data (JSON)"
    case recipesJSON = "Recipes Only (JSON)"
    case recipesHTML = "Recipes Only (HTML)"

    var id: Self { self }

    var contentType: UTType {
        self == .recipesHTML ? .html : .json
    }

    var filename: String {
        switch self {
        case .allLocalJSON:
            "RecipePouch-All-Local-Data"
        case .recipesJSON, .recipesHTML:
            "RecipePouch-Recipes"
        }
    }

    @MainActor
    func exportData(from store: RecipeStore) throws -> Data {
        switch self {
        case .allLocalJSON:
            try store.exportData()
        case .recipesJSON:
            try RecipePortableExport.json(snapshot: store.exportCloudSnapshot())
        case .recipesHTML:
            RecipePortableExport.html(snapshot: try store.exportCloudSnapshot())
        }
    }
}

struct RecipeExportFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .html] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
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
        .navigationTitle("What RecipePouch Stores")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct PrivacySummaryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Privacy Summary")
                    .font(RecipeTheme.title(30))

                Text(
                    "RecipePouch is designed as a private recipe utility. "
                        + "It does not publish your recipes to a public feed."
                )

                Text(
                    "Automated imports may send source material to RecipePouch’s "
                        + "backend only when processing is required. "
                        + "Provider secrets remain server-side."
                )

                Text(
                    "App Store purchases are managed by Apple. "
                        + "Your App Store purchase identity and RecipePouch account "
                        + "are treated as separate identities."
                )

                Text(
                    "You can export local data and request deletion of your "
                        + "RecipePouch account data from Settings."
                )
            }
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
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
                        articleBody: "Use Add Recipe to paste a link, import text "
                            + "or a document, scan a photo, or create a recipe "
                            + "manually. Incomplete imports remain editable instead "
                            + "of inventing missing details."
                    )
                }

                NavigationLink("Cook with timers") {
                    HelpArticleView(
                        title: "Cook with timers",
                        articleBody: "Start Cooking opens a focused full-screen flow. "
                            + "Step timers can run independently, ingredients can be "
                            + "checked off, and RecipePouch restores the session when possible."
                    )
                }

                NavigationLink("Plan meals and shop") {
                    HelpArticleView(
                        title: "Plan meals and shop",
                        articleBody: "Add saved recipes to the Meal Plan, then add "
                            + "ingredients to Groceries. RecipePouch preserves recipe "
                            + "sources and only consolidates compatible quantities."
                    )
                }
            }

            Section("Troubleshooting") {
                NavigationLink("Subscription not showing") {
                    HelpArticleView(
                        title: "Subscription not showing",
                        articleBody: "Check that you are using the intended RecipePouch "
                            + "account and App Store account. Then open Subscription "
                            + "and choose Restore Purchases."
                    )
                }

                NavigationLink("Sync problems") {
                    HelpArticleView(
                        title: "Sync problems",
                        articleBody: "Open Cloud Sync to review account, last sync, "
                            + "and status. Your local library remains available while "
                            + "sync is unavailable."
                    )
                }

                NavigationLink("Import needs review") {
                    HelpArticleView(
                        title: "Import needs review",
                        articleBody: "RecipePouch keeps the original source and marks "
                            + "uncertain or missing recipe details for review rather "
                            + "than guessing quantities or steps."
                    )
                }
            }
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct HelpArticleView: View {
    let title: String
    let articleBody: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(RecipeTheme.title(30))
                Text(articleBody)
                    .font(
                        RecipeTheme.text(
                            17,
                            weight: .regular,
                            relativeTo: .body
                        )
                    )
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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
                        .font(RecipeTheme.title(28))
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
        .navigationTitle("About RecipePouch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct LicensesView: View {
    var body: some View {
        List {
            Section("Lora") {
                Text(
                    "Copyright The Lora Project Authors. "
                        + "Licensed under the SIL Open Font License 1.1."
                )
            }

            Section("System frameworks") {
                Text(
                    "SwiftUI, StoreKit, AuthenticationServices, Vision, "
                        + "and related Apple frameworks are used under Apple platform terms."
                )
            }
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct AcknowledgementsView: View {
    var body: some View {
        ScrollView {
            Text(
                "RecipePouch’s interaction model is informed by established "
                    + "private recipe managers: collect recipes, organize them, "
                    + "cook step-by-step, plan meals, and shop from ingredients. "
                    + "RecipePouch’s implementation and visual system remain its own."
            )
            .padding()
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}
