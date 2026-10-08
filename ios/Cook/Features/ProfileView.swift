import CookCore
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import UserNotifications
import UIKit

struct ProfileView: View {
    @Environment(CookStore.self) private var store
    @State private var editsProfile = false
    @State private var confirmsReset = false
    @State private var exportsData = false
    @State private var exportDocument = CookExportDocument(data: Data())
    @State private var errorMessage: String?

    private var displayName: String {
        let name = store.settings.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Your kitchen" : name
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(CookTheme.accentForeground)
                        .frame(width: 72, height: 72)
                        .background(CookTheme.accent.opacity(0.10), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(displayName).font(CookTheme.title(28))
                        if !store.settings.email.isEmpty {
                            Text(store.settings.email).font(CookTheme.text(15, weight: .regular, relativeTo: .subheadline)).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Button {
                            editsProfile = true
                        } label: {
                            Label("Edit Profile", systemImage: "pencil")
                                .font(CookTheme.text(15, weight: .semibold, relativeTo: .subheadline))
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("profile.edit")
                    }
                }
                .padding(.vertical, 12)
            }
            .listRowBackground(Color.clear)

            Section {
                NavigationLink { SettingsHubView() } label: { ProfileRowLabel(title: "Settings", systemImage: "gearshape") }
            }
            .listRowBackground(CookTheme.card)

            Section("Account & subscription") {
                NavigationLink { AccountView() } label: { ProfileRowLabel(title: "Cook Account", systemImage: "person.badge.key") }
                NavigationLink { SubscriptionView() } label: { ProfileRowLabel(title: "Cook Premium", systemImage: "sparkles") }
            }
            .listRowBackground(CookTheme.card)

            Section("Your kitchen") {
                NavigationLink {
                    RecipesView()
                } label: {
                    ProfileRowLabel(
                        title: "Saved Recipes",
                        systemImage: "bookmark"
                    )
                }
                NavigationLink {
                    CollectionsView()
                } label: {
                    ProfileRowLabel(title: "Collections", systemImage: "folder")
                }
                .accessibilityIdentifier("profile.collections")

                NavigationLink {
                    MealPlanView()
                } label: {
                    ProfileRowLabel(title: "Meal Plan", systemImage: "calendar")
                }
                .accessibilityIdentifier("profile.mealplan")
            }
            .listRowBackground(CookTheme.card)

            Section {
                NavigationLink {
                    NotificationPreferencesView()
                } label: {
                    ProfileRowLabel(title: "Notifications", systemImage: "bell")
                }
                Picker(selection: appearanceBinding) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.rawValue).tag(appearance)
                    }
                } label: {
                    ProfileRowLabel(title: "Appearance", systemImage: "circle.lefthalf.filled")
                }
                Toggle(isOn: keepAwakeBinding) {
                    ProfileRowLabel(title: "Keep Screen Awake", systemImage: "sun.max")
                }
                .accessibilityIdentifier("profile.keep-awake")
            } header: {
                Text("Preferences")
            }
            .listRowBackground(CookTheme.card)

            Section("Help & about") {
                NavigationLink {
                    CookHelpView()
                } label: {
                    ProfileRowLabel(title: "Using Cook", systemImage: "questionmark.circle")
                }
                NavigationLink {
                    CookAboutView()
                } label: {
                    ProfileRowLabel(title: "About & Your Data", systemImage: "info.circle")
                }
            }
            .listRowBackground(CookTheme.card)

            Section {
                Button(action: prepareExport) {
                    ProfileRowLabel(title: "Export All Data", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.export")
                Button(role: .destructive) { confirmsReset = true } label: {
                    Label("Delete All Local Data", systemImage: "trash")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("profile.delete-data")
            } header: {
                Text("On this iPhone")
            }
            .listRowBackground(CookTheme.card)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(CookSpacing.medium)
        .scrollContentBackground(.hidden)
        .background(CookTheme.canvas)
        .navigationTitle("Profile").navigationBarTitleDisplayMode(.large)
        .tint(CookTheme.accent)
        .sheet(isPresented: $editsProfile) { LocalProfileEditorView() }
        .fileExporter(
            isPresented: $exportsData,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Cook-Backup-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))"
        ) { result in
            if case let .failure(error) = result { errorMessage = error.localizedDescription }
        }
        .confirmationDialog("Delete all local data?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Delete All Local Data", role: .destructive) {
                do {
                    try CookLocalDataCleanup.reset(store: store)
                    exportDocument = CookExportDocument(data: Data())
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("This permanently deletes your recipes, grocery list, meal plan, local profile and preferences from this iPhone. Export a copy first if you want to keep them.")
        }
        .alert("Couldn’t update your data", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Please try again.") }
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(get: { store.settings.appearance }, set: { value in
            updateSettings { $0.appearance = value }
        })
    }

    private var keepAwakeBinding: Binding<Bool> {
        Binding(get: { store.settings.keepScreenAwake }, set: { value in
            updateSettings { $0.keepScreenAwake = value }
        })
    }

    private func updateSettings(_ update: (inout CookSettings) -> Void) {
        var settings = store.settings
        update(&settings)
        do { try store.updateSettings(settings) }
        catch { errorMessage = error.localizedDescription }
    }

    private func prepareExport() {
        do {
            exportDocument = CookExportDocument(data: try store.exportData())
            exportsData = true
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct ProfileRowLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: CookSpacing.small) {
            Image(systemName: systemImage)
                .font(.system(size: 19))
                .foregroundStyle(CookTheme.accentForeground)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(CookTheme.text(17, weight: .regular, relativeTo: .body)).foregroundStyle(.primary)
            }
        }
        .frame(minHeight: 44)
    }
}

private struct LocalProfileEditorView: View {
    @Environment(CookStore.self) private var store
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
            .background(CookTheme.canvas)
            .navigationTitle("Edit Profile").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var settings = store.settings
                        settings.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
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
            .alert("Couldn’t save profile", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Please try again.") }
        }
        .tint(CookTheme.accent)
    }
}

struct NotificationPreferencesView: View {
    @Environment(CookStore.self) private var store
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
        guard hasLoaded else { return "Checking…" }
        switch authorization {
        case .notDetermined: return "Not requested"
        case .denied: return "Off in iOS Settings"
        case .authorized: return "Allowed"
        case .provisional: return "Quiet delivery"
        case .ephemeral: return "Temporarily allowed"
        @unknown default: return "Check iOS Settings"
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("iOS permission", value: permissionDescription)
                if !hasLoaded || requestsPermission {
                    ProgressView("Checking notification access")
                } else if isAuthorized {
                    Toggle("Cooking timer reminders", isOn: Binding(
                        get: { store.settings.timerNotifications },
                        set: { value in setTimerReminders(value) }
                    ))
                } else if authorization == .notDetermined {
                    Button("Allow Timer Reminders") {
                        Task { await requestPermission() }
                    }
                } else {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            } header: {
                Text("Cooking reminders")
            }
        }
        .scrollContentBackground(.hidden)
        .background(CookTheme.canvas)
        .navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline)
        .tint(CookTheme.accent)
        .task { await refreshPermission() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshPermission() } }
        }
        .alert("Couldn’t update reminders", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Please try again.") }
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
        } catch { errorMessage = error.localizedDescription }
    }

    private func setTimerReminders(_ enabled: Bool) {
        guard !enabled || isAuthorized else { return }
        var settings = store.settings
        settings.timerNotifications = enabled
        do {
            try store.updateSettings(settings)
            if !enabled { Task { await CookNotificationCleanup.removeTimerReminders() } }
        } catch { errorMessage = error.localizedDescription }
    }
}

@MainActor
enum CookLocalDataCleanup {
    static func reset(store: CookStore) throws {
        // Commit the destructive library reset first. If persistence fails,
        // keep sessions/preferences intact so the user can retry safely.
        try store.resetLibrary()

        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("cook.cookingSession.") {
            defaults.removeObject(forKey: key)
        }

        // Remove legacy or still-UserDefaults-backed local preferences owned by
        // this app. Account credentials and App Store purchases are separate.
        for key in [
            "cook.collections",
            "cook.grocery.consolidate",
            "cook.grocery.sources",
            "cook.meal.weekStart",
            "cook.sync.mode"
        ] {
            defaults.removeObject(forKey: key)
        }

        Task {
            await CookNotificationCleanup.removeTimerReminders()
        }
    }
}

@MainActor
enum CookNotificationCleanup {
    static func removeTimerReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("cook.timer.") })
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.request.identifier).filter { $0.hasPrefix("cook.timer.") })
    }
}

private struct CookHelpView: View {
    var body: some View {
        List {
            Section("Getting started") {
                NavigationLink("Save your first recipe") {
                    GettingStartedGuideView()
                }
            }
            Section("Save a recipe") {
                Text("From a recipe or social app, use Share and choose RecipePouch. The share extension receives it quickly and you can return to the source app. If sharing is unavailable, use Add Recipe to paste a link, add text or an image, or create a recipe manually.")
            }
            Section("Make it yours") {
                Text("Open any recipe to edit its ingredients, instructions and notes. The original source stays with the recipe so you can return to it.")
            }
            Section("Shop for a meal") {
                Text("Use Add to Groceries in a recipe, choose the servings and ingredients, then add them to your list. In Groceries, tap a circle to mark an item bought, tap its name to edit, or swipe for more actions.")
            }
            Section("Cook step by step") {
                Text("Start Cooking opens one step at a time. You can move between steps and use timers where a duration is available. Keep Screen Awake in Profile controls whether your screen stays on during cooking.")
            }
            Section("Plan your week") {
                Text("Open Meal Plan from Profile, choose a day and meal, then select a saved recipe. Swipe a planned meal to remove it. Your saved recipe stays in your library.")
            }
            Section("Keep a copy") {
                Text("Export All Data in Profile saves a JSON copy of your library and local preferences. Keep the exported file somewhere you trust. This version does not offer an in-app backup restore flow.")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(CookSpacing.medium)
        .scrollContentBackground(.hidden)
        .background(CookTheme.canvas)
        .navigationTitle("Using Cook").navigationBarTitleDisplayMode(.inline)
    }
}

private struct CookAboutView: View {
    var body: some View {
        List {
            Section("Cook") {
                LabeledContent("Version", value: CookVersion.display)
                LabeledContent("Storage", value: "On this iPhone")
            }
            Section("Your local data") {
                Text("This version stores your recipes, recipe images, source information, grocery list, meal plan and preferences on this iPhone. Your local profile is optional and does not create an online account.")
                Text("Cook does not upload this library to a cloud account. Opening a source link takes you to the source website, where that site’s own practices apply.")
            }
            Section("Exporting and deleting") {
                Text("An exported JSON file contains a copy of your local Cook data, including any name, email, source text or notes you saved. You choose where the file is saved.")
                Text("Delete All Local Data removes the Cook library and preferences from this iPhone after confirmation. Copies you exported separately are not deleted.")
            }
            Section("Recipe sources") {
                Text("Keep the original source with recipes you save. Check the source for its terms and any cooking or ingredient information you need.")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(CookSpacing.medium)
        .scrollContentBackground(.hidden)
        .background(CookTheme.canvas)
        .navigationTitle("About & Your Data").navigationBarTitleDisplayMode(.inline)
    }
}

enum CookVersion {
    static var display: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

private struct CookExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

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
