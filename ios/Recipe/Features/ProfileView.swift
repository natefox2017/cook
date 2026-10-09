// Developer: gengyun
// Purpose: Implements ProfileView for the Recipe iOS app.

import RecipeCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers
@preconcurrency import UserNotifications

struct ProfileView: View {
    let onOpenAccount: () -> Void

    @Environment(RecipeStore.self) private var store
    @Environment(CloudSyncCoordinator.self) private var cloudSync
    @State private var editsProfile = false
    @State private var confirmsReset = false
    @State private var isDeletingLocalData = false
    @State private var exportsData = false
    @State private var choosesExportFormat = false
    @State private var exportDocument = RecipeExportDocument(data: Data())
    @State private var errorMessage: String?

    private var displayName: String {
        let name = store.settings.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty
            ? String(
                localized: LocalizedStringResource("Your kitchen", locale: RecipeLanguage.active))
            : name
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(RecipeTheme.accentForeground)
                        .frame(width: 72, height: 72)
                        .background(RecipeTheme.accent.opacity(0.10), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
                        Text(displayName)
                            .font(RecipeTheme.heading(.title))
                        if !store.settings.email.isEmpty {
                            Text(store.settings.email)
                                .font(
                                    RecipeTheme.text(
                                        15,
                                        weight: .regular,
                                        relativeTo: .subheadline
                                    )
                                )
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Button {
                            editsProfile = true
                        } label: {
                            Label("Edit Profile", systemImage: "pencil")
                                .font(
                                    RecipeTheme.text(
                                        15,
                                        weight: .semibold,
                                        relativeTo: .subheadline
                                    )
                                )
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("profile.edit")
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(
                EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
            )

            Section {
                NavigationLink {
                    SettingsHubView()
                } label: {
                    ProfileRowLabel(
                        title: "Settings",
                        systemImage: "gearshape"
                    )
                }
            }
            .listRowBackground(RecipeTheme.card)

            Section("Account & subscription") {
                Button(action: onOpenAccount) {
                    ProfileRowLabel(
                        title: "Account",
                        systemImage: "person.badge.key"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.account")
                NavigationLink {
                    SubscriptionView()
                } label: {
                    ProfileRowLabel(
                        title: "Premium",
                        systemImage: "sparkles"
                    )
                }
            }
            .listRowBackground(RecipeTheme.card)

            Section {
                NavigationLink {
                    RecipesView(titleDisplayMode: RecipeNavigation.detailTitleMode)
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    ProfileRowLabel(
                        title: "Saved Recipes",
                        systemImage: "bookmark"
                    )
                }
                NavigationLink {
                    CollectionsView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    ProfileRowLabel(
                        title: "Collections",
                        systemImage: "folder"
                    )
                }
                .accessibilityIdentifier("profile.collections")

                NavigationLink {
                    MealPlanView(titleDisplayMode: RecipeNavigation.detailTitleMode)
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    ProfileRowLabel(title: "Meal Plan", systemImage: "calendar")
                }
                .accessibilityIdentifier("profile.mealplan")
            }
            .listRowBackground(RecipeTheme.card)

            Section {
                NavigationLink {
                    NotificationPreferencesView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    ProfileRowLabel(
                        title: "Notifications",
                        systemImage: "bell"
                    )
                }
                Picker(selection: appearanceBinding) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(LocalizedStringKey(appearance.rawValue))
                            .tag(appearance)
                    }
                } label: {
                    ProfileRowLabel(
                        title: "Appearance",
                        systemImage: "circle.lefthalf.filled"
                    )
                }
                Toggle(isOn: keepAwakeBinding) {
                    ProfileRowLabel(
                        title: "Keep Screen Awake",
                        systemImage: "sun.max"
                    )
                }
                .accessibilityIdentifier("profile.keep-awake")
            } header: {
                Text("Preferences")
            }
            .listRowBackground(RecipeTheme.card)

            Section("Help & about") {
                NavigationLink {
                    RecipeHelpView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    ProfileRowLabel(
                        title: "Using RecipePouch",
                        systemImage: "questionmark.circle"
                    )
                }
                NavigationLink {
                    RecipeAboutView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    ProfileRowLabel(
                        title: "About & Your Data",
                        systemImage: "info.circle"
                    )
                }
            }
            .listRowBackground(RecipeTheme.card)

            Section {
                Button {
                    choosesExportFormat = true
                } label: {
                    ProfileRowLabel(
                        title: "Export Data",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.export")
                // Anchor the native popover to this row rather than the scrollable List.
                .confirmationDialog(
                    "Choose export format",
                    isPresented: $choosesExportFormat,
                    titleVisibility: .visible
                ) {
                    Button("Recipes (JSON)") {
                        prepareExport(.recipesJSON)
                    }
                    Button("Recipes (HTML)") {
                        prepareExport(.recipesHTML)
                    }
                    Button("All Local Library Data (JSON)") {
                        prepareExport(.allLibraryJSON)
                    }
                    Button("Cancel", role: .cancel) {
                    }
                } message: {
                    Text(
                        "Recipe JSON/HTML includes sources and Collections but not photos. Full library JSON also includes groceries, meal plan and local preferences. This app cannot restore these exports."
                    )
                }
                Button(role: .destructive) {
                    confirmsReset = true
                } label: {
                    Label("Delete All Local Data", systemImage: "trash")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("profile.delete-data")
            } header: {
                Text("On this iPhone")
            }
            .listRowBackground(RecipeTheme.card)
        }
        .recipeRootScrollClearance()
        .listStyle(.insetGrouped)
        .contentMargins(.top, RecipeSpacing.pageTop, for: .scrollContent)
        .listSectionSpacing(RecipeSpacing.medium)
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(RecipeNavigation.rootTitleMode)
        .tint(RecipeTheme.accent)
        .sheet(isPresented: $editsProfile) {
            LocalProfileEditorView()
        }
        .fileExporter(
            isPresented: $exportsData,
            document: exportDocument,
            contentType: exportDocument.contentType,
            defaultFilename: exportDocument.filename
        ) { result in
            if let feedback = RecipeExportFormat.feedback(for: result) {
                errorMessage = feedback
            }
        }
        .confirmationDialog(
            "Delete all local data?",
            isPresented: $confirmsReset,
            titleVisibility: .visible
        ) {
            Button("Delete All RecipePouch Data", role: .destructive) {
                guard !isDeletingLocalData else { return }
                isDeletingLocalData = true
                Task {
                    defer {
                        isDeletingLocalData = false
                    }
                    do {
                        try await RecipeLocalDataDeletion.erase(
                            store: store,
                            cloudSync: cloudSync
                        )
                        exportDocument = RecipeExportDocument(data: Data())
                        errorMessage = String(
                            localized: LocalizedStringResource(
                                "Local RecipePouch data deleted.",
                                locale: RecipeLanguage.active
                            )
                        )
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .disabled(isDeletingLocalData)
        } message: {
            Text(
                "This deletes only data on this iPhone. Sign out first; cloud data and your App Store subscription remain intact. Signing in again may restore cloud recipes. Export local data first if needed."
            )
        }
        .alert(
            "RecipePouch",
            isPresented: Binding(
                get: {
                    errorMessage != nil
                },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { store.settings.appearance },
            set: { value in
                updateSettings { $0.appearance = value }
            })
    }

    private var keepAwakeBinding: Binding<Bool> {
        Binding(
            get: { store.settings.keepScreenAwake },
            set: { value in
                updateSettings { $0.keepScreenAwake = value }
            })
    }

    private func updateSettings(_ update: (inout RecipeSettings) -> Void) {
        var settings = store.settings
        update(&settings)
        do { try store.updateSettings(settings) } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareExport(_ format: RecipeExportFormat) {
        do {
            exportDocument = try format.makeDocument(from: store)
            exportsData = true
        } catch {
            errorMessage = String(
                localized: LocalizedStringResource(
                    "Export failed: \(error.localizedDescription)", locale: RecipeLanguage.active))
        }
    }
}

private struct ProfileRowLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: RecipeSpacing.small) {
            Image(systemName: systemImage)
                .font(.system(size: 19))
                .foregroundStyle(RecipeTheme.accentForeground)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(title))
                .font(RecipeTheme.text(17, weight: .regular, relativeTo: .body))
                .foregroundStyle(.primary)
        }
        .frame(minHeight: 44)
    }
}

private struct LocalProfileEditorView: View {
    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var email = ""
    @State private var didLoad = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $displayName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("profile.editor.name")
                    TextField("Email (optional)", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Local profile")
                }
            }
            .scrollContentBackground(.hidden)
            .background(RecipeTheme.canvas)
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var settings = store.settings
                        settings.displayName = displayName.trimmingCharacters(
                            in: .whitespacesAndNewlines)
                        settings.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
                        do {
                            try store.updateSettings(settings)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("profile.editor.save")
                }
            }
            .onAppear {
                guard !didLoad else { return }
                displayName = store.settings.displayName
                email = store.settings.email
                didLoad = true
            }
            .alert(
                "Couldn’t save profile",
                isPresented: Binding(
                    get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
        .tint(RecipeTheme.accent)
    }
}

struct NotificationPreferencesView: View {
    @Environment(RecipeStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var hasLoaded = false
    @State private var requestsPermission = false
    @State private var errorMessage: String?

    private var isAuthorized: Bool {
        authorization == .authorized || authorization == .provisional || authorization == .ephemeral
    }

    private var permissionDescription: String {
        guard hasLoaded else {
            return String(
                localized: LocalizedStringResource("Checking…", locale: RecipeLanguage.active))
        }
        switch authorization {
        case .notDetermined:
            return String(
                localized: LocalizedStringResource("Not requested", locale: RecipeLanguage.active))
        case .denied:
            return String(
                localized: LocalizedStringResource(
                    "Off in iOS Settings", locale: RecipeLanguage.active))
        case .authorized:
            return String(
                localized: LocalizedStringResource("Allowed", locale: RecipeLanguage.active))
        case .provisional:
            return String(
                localized: LocalizedStringResource("Quiet delivery", locale: RecipeLanguage.active))
        case .ephemeral:
            return String(
                localized: LocalizedStringResource(
                    "Temporarily allowed", locale: RecipeLanguage.active))
        @unknown default:
            return String(
                localized: LocalizedStringResource(
                    "Check iOS Settings", locale: RecipeLanguage.active))
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("iOS permission", value: permissionDescription)
                if !hasLoaded || requestsPermission {
                    ProgressView("Checking notification access")
                } else if isAuthorized {
                    Toggle(
                        "Cooking timer reminders",
                        isOn: Binding(
                            get: { store.settings.timerNotifications },
                            set: { value in setTimerReminders(value) }
                        ))
                } else if authorization == .notDetermined {
                    Button("Allow Timer Reminders") {
                        Task { await requestPermission() }
                    }
                } else {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            } header: {
                Text("Cooking reminders")
            }
        }
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
        .tint(RecipeTheme.accent)
        .task { await refreshPermission() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshPermission() } }
        }
        .alert(
            "Couldn’t update reminders",
            isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    @MainActor
    private func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = settings.authorizationStatus
        hasLoaded = true
        if !isAuthorized && store.settings.timerNotifications {
            setTimerReminders(false)
        }
    }

    @MainActor
    private func requestPermission() async {
        guard !requestsPermission else { return }
        requestsPermission = true
        defer { requestsPermission = false }
        let center = UNUserNotificationCenter.current()
        let currentSettings = await center.notificationSettings()
        do {
            if currentSettings.authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            }
            await refreshPermission()
            if isAuthorized { setTimerReminders(true) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setTimerReminders(_ enabled: Bool) {
        guard !enabled || isAuthorized else { return }
        var settings = store.settings
        settings.timerNotifications = enabled
        do {
            try store.updateSettings(settings)
            if !enabled {
                Task {
                    await RecipeNotificationCleanup.removeTimerReminders(
                        isUITesting: RecipeUITestNamespace.isUITesting
                    )
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
enum RecipeNotificationCleanup {
    static func removeTimerReminders(isUITesting: Bool = false) async {
        let prefixes =
            isUITesting
            ? ["recipe.uitesting.timer."]
            : ["cook.timer.", "recipe.timer."]
        await TimerNotifications.cancelAll(matchingPrefixes: prefixes)
    }
}

/// Shared by both local-delete entry points. This does not call any remote
/// deletion API, delete the signed-in account, or cancel an App Store purchase.
@MainActor
enum RecipeLocalDataDeletion {
    static func erase(
        store: RecipeStore,
        cloudSync: CloudSyncCoordinator,
        authState: RecipeAuthState? = nil,
        isUITesting: Bool = RecipeUITestNamespace.isUITesting,
        defaults: UserDefaults = .standard
    ) async throws {
        let currentAuthState = authState ?? RecipeAuthService.shared.state
        guard case .signedOut = currentAuthState else {
            throw RecipeLocalResetError.requiresSignOut
        }

        #if DEBUG
            if isUITesting {
                try store.clearLocalLibraryOnly()
                RecipeUITestNamespace.clearPreferences(from: defaults)
                await RecipeNotificationCleanup.removeTimerReminders(isUITesting: true)
                return
            }
        #else
            _ = isUITesting
        #endif

        // A failed disk cleanup must never allow an empty local snapshot to
        // be uploaded as offline edits. Invalidate cloud lineage first, even
        // if the following local write fails or the process is interrupted.
        try cloudSync.prepareForLocalOnlyReset()

        // This atomic write has no cloud deletion tombstones.
        try store.clearLocalLibraryOnly()

        var cleanupError: Error?
        do {
            try store.removeLegacyLibraryCopyAfterLocalErase()
        } catch {
            cleanupError = error
        }

        do {
            try cloudSync.removeLocalSyncCacheFilesAfterReset()
        } catch {
            cleanupError = cleanupError ?? error
        }

        let prefixes = [
            "recipe.cookingSession.",
            "cook.cookingSession.",
        ]
        for key in defaults.dictionaryRepresentation().keys
        where prefixes.contains(where: { key.hasPrefix($0) }) {
            defaults.removeObject(forKey: key)
        }
        for key in [
            "recipe.grocery.consolidate",
            "cook.grocery.consolidate",
            "recipe.grocery.sources",
            "cook.grocery.sources",
            "recipe.meal.weekStart",
            "cook.meal.weekStart",
            "recipe.collections",
            "cook.collections",
            "recipe.shareInbox",
            "cook.shareInbox",
        ] {
            defaults.removeObject(forKey: key)
        }

        // Share receipts can contain private URLs. They live in the deployed
        // App Group, independently of the main app's defaults database.
        if let shareDefaults = UserDefaults(suiteName: "group.com.shopkivoo.recipe") {
            shareDefaults.removeObject(forKey: "recipe.shareInbox")
            shareDefaults.removeObject(forKey: "cook.shareInbox")
        }

        // Newly file-backed Share Extension receipts live outside both
        // RecipeStore and UserDefaults. Erase their original source bytes as
        // part of the same user-confirmed on-device deletion.
        do {
            try RecipeShareInbox.shared().eraseAllLocalReceipts()
        } catch {
            cleanupError = cleanupError ?? error
        }

        await RecipeNotificationCleanup.removeTimerReminders(isUITesting: isUITesting)

        // Clear independently stored personal data even if legacy file deletion
        // failed. The old sync lineage was invalidated before the library write.
        if let cleanupError {
            throw cleanupError
        }
    }
}

private struct RecipeHelpView: View {
    var body: some View {
        List {
            NavigationLink("Getting Started") {
                GettingStartedGuideView()
            }
            NavigationLink("Help & Support") {
                HelpCenterView()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .navigationTitle("Using RecipePouch")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
    }
}

private struct RecipeAboutView: View {
    var body: some View {
        List {
            Section("RecipePouch") {
                LabeledContent("Version", value: RecipeVersion.display)
            }
            Section("Data & Privacy") {
                NavigationLink("What RecipePouch Stores") {
                    StoredDataView()
                }
                NavigationLink("Privacy Summary") {
                    PrivacySummaryView()
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(RecipeTheme.canvas)
        .navigationTitle("About & Your Data")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
    }
}

enum RecipeVersion {
    static var display: String {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

/// Shared recipe export options. None are restorable device backups.
enum RecipeExportFormat {
    case recipesJSON
    case recipesHTML
    case allLibraryJSON

    var contentType: UTType {
        switch self {
        case .recipesHTML: .html
        case .recipesJSON, .allLibraryJSON: .json
        }
    }

    var filename: String {
        let date = Date().formatted(
            .iso8601.year().month().day().dateSeparator(.dash)
        )
        switch self {
        case .recipesJSON, .recipesHTML:
            return "RecipePouch-Recipes-\(date)"
        case .allLibraryJSON:
            return "RecipePouch-Local-Library-\(date)"
        }
    }

    @MainActor
    func makeDocument(from store: RecipeStore) throws -> RecipeExportDocument {
        let data: Data
        switch self {
        case .recipesJSON:
            data = try RecipePortableExport.json(
                snapshot: store.exportCloudSnapshot()
            )
        case .recipesHTML:
            data = RecipePortableExport.html(
                snapshot: try store.exportCloudSnapshot()
            )
        case .allLibraryJSON:
            data = try store.exportData()
        }

        return RecipeExportDocument(
            data: data,
            contentType: contentType,
            filename: filename
        )
    }

    /// Only the system exporter's completion callback can report a successful save.
    static func feedback(for result: Result<URL, Error>) -> String? {
        switch RecipeFileExportResult(result) {
        case .saved(let filename):
            return "Export saved as \(filename)."
        case .cancelled:
            return nil
        case .failed(let message):
            return "Export failed: \(message)"
        }
    }
}

struct RecipeExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .html] }

    var data: Data
    var contentType: UTType
    var filename: String

    init(
        data: Data,
        contentType: UTType = .json,
        filename: String = "RecipePouch-Recipes"
    ) {
        self.data = data
        self.contentType = contentType
        self.filename = filename
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
        contentType = configuration.contentType
        filename = "RecipePouch-Recipes"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
