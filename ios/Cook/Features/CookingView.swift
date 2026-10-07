import SwiftUI
import UIKit
import UserNotifications
import CookCore

struct CookingView: View {
    let recipeID: UUID
    let servings: Int?
    let onServingsChanged: ((Int) -> Void)?
    @Environment(CookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var session = PersistedCookingSession()
    @State private var didRestoreSession = false
    @State private var requiresSessionRecovery = false
    @State private var isConfirmingSessionRecovery = false
    @State private var isReplacingSession = false
    @State private var isShowingIngredients = false
    @State private var isConfirmingFinish = false
    @State private var errorMessage: String?
    @State private var originalIdleTimerDisabled: Bool?
    @State private var notificationTasks: [UUID: Task<Void, Never>] = [:]

    private var recipe: Recipe? { store.recipe(id: recipeID) }
    private var sessionKey: String { "cook.cookingSession.\(recipeID.uuidString)" }

    init(recipeID: UUID, servings: Int? = nil, onServingsChanged: ((Int) -> Void)? = nil) {
        self.recipeID = recipeID
        self.servings = servings
        self.onServingsChanged = onServingsChanged
    }

    var body: some View {
        NavigationStack {
            Group {
                if let recipe, !recipe.steps.isEmpty {
                    if requiresSessionRecovery { sessionRecoveryContent }
                    else if session.isComplete { completionContent(recipe) }
                    else { cookingContent(recipe) }
                } else {
                    EmptyStateView(
                        title: "No cooking steps yet",
                        message: "Return to the recipe and add its steps to start cooking.",
                        systemImage: "list.bullet.clipboard",
                        actionTitle: "Back to Recipe",
                        action: { dismiss() }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CookTheme.canvas)
            .navigationTitle("Cooking Mode").navigationBarTitleDisplayMode(.inline)
            .toolbar { cookingToolbar }
            .sheet(isPresented: $isShowingIngredients) { ingredientSheet }
            .confirmationDialog("Finish and stop active timers?", isPresented: $isConfirmingFinish, titleVisibility: .visible) {
                Button("Finish Cooking", action: finishCooking)
                    .accessibilityIdentifier("confirmFinishCooking")
                Button("Keep Cooking", role: .cancel) {}
            } message: { Text("Your running timers will stop when you finish this recipe.") }
            .confirmationDialog("Replace saved cooking progress?", isPresented: $isConfirmingSessionRecovery, titleVisibility: .visible) {
                Button("Start a New Session") { replaceUnreadableSession() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This replaces the unreadable cooking progress for this recipe. The recipe itself is kept.") }
            .alert("Cooking", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .interactiveDismissDisabled()
        .onAppear(perform: appear)
        .onDisappear(perform: disappear)
        .onChange(of: scenePhase) { _, phase in
            updateScreenAwake()
            if phase != .active { persistSession() }
        }
        .onChange(of: store.settings.keepScreenAwake) { _, _ in updateScreenAwake() }
        .onChange(of: store.settings.timerNotifications) { _, _ in synchronizeNotifications() }
        .onChange(of: recipe?.id) { _, id in
            if id == nil {
                for stepID in session.timers.keys { cancelNotification(for: stepID) }
                Self.discardSession(recipeID: recipeID)
                if let originalIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled }
            }
        }
    }

    private func cookingContent(_ recipe: Recipe) -> some View {
        let index = stepIndex(in: recipe)
        let step = recipe.steps[index]
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !dynamicTypeSize.isAccessibilitySize {
                    RecipeImage(recipe: recipe, height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                }
                Text(recipe.title.isEmpty ? "Untitled Recipe" : recipe.title).font(CookTheme.text(17, weight: .semibold, relativeTo: .headline)).foregroundStyle(.secondary)
                progress(index: index, count: recipe.steps.count)
                VStack(alignment: .leading, spacing: 14) {
                    Text(step.title.isEmpty ? "Step \(index + 1)" : step.title)
                        .font(CookTheme.title(32))
                        .accessibilityAddTraits(.isHeader)
                    Text(step.instruction)
                        .font(CookTheme.body(25))
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("cookingStepInstruction")
                }
                if let duration = step.durationSeconds, duration > 0 {
                    CookingStepTimerPanel(
                        timer: session.timers[step.id] ?? CookingTimer(durationSeconds: duration),
                        notificationsEnabled: store.settings.timerNotifications,
                        onStart: { startTimer(step) },
                        onPause: { pauseTimer(step) },
                        onReset: { resetTimer(step) }
                    )
                }
                otherTimerLinks(recipe, excluding: step.id)
                Button { isShowingIngredients = true } label: {
                    Label("View All Ingredients", systemImage: "carrot")
                        .frame(minHeight: 44)
                }
            }
            .padding(20)
        }
        .accessibilityIdentifier("cookingScroll")
        .safeAreaInset(edge: .bottom) { stepControls(recipe, index: index) }
    }

    private func progress(index: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step \(index + 1) of \(count)")
                .font(CookTheme.text(15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(CookTheme.accent)
                .accessibilityIdentifier("cookingStepProgress")
            ProgressView(value: Double(index + 1), total: Double(count))
                .tint(CookTheme.accent)
                .accessibilityLabel("Recipe progress")
                .accessibilityValue("Step \(index + 1) of \(count)")
        }
    }

    private func stepControls(_ recipe: Recipe, index: Int) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 14))
        return layout {
            Button { if index > 0 { selectStep(recipe.steps[index - 1].id) } } label: {
                Label("Previous", systemImage: "arrow.left")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(index == 0)
            .accessibilityIdentifier("previousStep")
            Button {
                if index + 1 < recipe.steps.count { selectStep(recipe.steps[index + 1].id) }
                else { requestFinish() }
            } label: {
                HStack {
                    Text(index + 1 == recipe.steps.count ? "Finish Cooking" : "Next Step")
                    Image(systemName: index + 1 == recipe.steps.count ? "checkmark" : "arrow.right")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("nextStep")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func otherTimerLinks(_ recipe: Recipe, excluding currentID: UUID) -> some View {
        let otherSteps = recipe.steps.enumerated().filter { entry in
            entry.element.id != currentID && session.timers[entry.element.id]?.deadline != nil
        }
        if !otherSteps.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Other Step Timers").font(CookTheme.text(15, weight: .semibold, relativeTo: .subheadline))
                    ForEach(otherSteps, id: \.element.id) { index, step in
                        if let timer = session.timers[step.id] {
                            let remaining = timer.remaining(at: context.date)
                            Button { selectStep(step.id) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Step \(index + 1)\(step.title.isEmpty ? "" : ": \(step.title)")", systemImage: "timer")
                                    Text(remaining == 0 ? "Time’s up" : "\(remaining / 60)m \(remaining % 60)s remaining")
                                        .font(CookTheme.text(12, weight: .regular, relativeTo: .caption)).monospacedDigit()
                                }
                                .frame(minHeight: 44, alignment: .leading)
                            }
                            .sensoryFeedback(.success, trigger: remaining == 0)
                        }
                    }
                }
            }
        }
    }

    private func completionContent(_ recipe: Recipe) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                RecipeImage(recipe: recipe, height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(CookTheme.accent)
                    .accessibilityHidden(true)
                Text("Ready to enjoy")
                    .font(CookTheme.title(32))
                    .accessibilityAddTraits(.isHeader)
                Text("You’ve completed \(recipe.title). Enjoy what you made.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Back to Recipe") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("finishCookingButton")
                Button("Cook Again") { restartCooking(recipe) }
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }

    private var sessionRecoveryContent: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                title: "Your cooking progress needs attention",
                message: "The saved session could not be read. Its original data has been kept. Start a new session to cook this recipe again.",
                systemImage: "clock.badge.exclamationmark",
                actionTitle: "Start a New Session",
                action: { isConfirmingSessionRecovery = true }
            )
            .disabled(isReplacingSession)
            if isReplacingSession { ProgressView("Starting a fresh session…") }
        }
    }

    @ToolbarContentBuilder
    private var cookingToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark") { dismiss() }
                .accessibilityIdentifier("closeCookingButton")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Ingredients", systemImage: "list.bullet") { isShowingIngredients = true }
                .disabled(recipe == nil)
        }
    }

    private var ingredientSheet: some View {
        NavigationStack {
            List {
                if let recipe {
                    Section {
                        if let original = recipe.servings, original > 0 {
                            Stepper("\(session.servings ?? original) servings", value: cookingServings(original: original), in: 1...max(100, max(original, session.servings ?? original)))
                        }
                        if recipe.ingredients.isEmpty {
                            Text("This recipe has no ingredients yet.").foregroundStyle(.secondary)
                        }
                        ForEach(recipe.ingredients) { ingredient in
                            Button { toggleIngredient(ingredient.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: session.usedIngredientIDs.contains(ingredient.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(session.usedIngredientIDs.contains(ingredient.id) ? CookTheme.accent : Color.secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(ingredient.name).font(CookTheme.text(17, weight: .semibold, relativeTo: .headline))
                                        let amount = ingredient.displayAmount(servings: session.servings, originalServings: recipe.servings)
                                        if !amount.isEmpty { Text(amount).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(ingredient.name), \(session.usedIngredientIDs.contains(ingredient.id) ? "used" : "not used")")
                        }
                    } header: {
                        Text(recipe.servings.map { $0 > 0 ? "Cooking portions" : "Original recipe amounts" } ?? "Original recipe amounts")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CookTheme.canvas)
            .navigationTitle("Ingredients").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isShowingIngredients = false } } }
        }
    }

    private func toggleIngredient(_ id: UUID) {
        if session.usedIngredientIDs.contains(id) { session.usedIngredientIDs.remove(id) } else { session.usedIngredientIDs.insert(id) }
        persistSession()
    }

    private func appear() {
        if originalIdleTimerDisabled == nil { originalIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled }
        guard !didRestoreSession else { updateScreenAwake(); return }
        didRestoreSession = true
        if let data = UserDefaults.standard.data(forKey: sessionKey) {
            do { session = try JSONDecoder().decode(PersistedCookingSession.self, from: data) }
            catch {
                requiresSessionRecovery = true
                errorMessage = "Your previous cooking session could not be restored. \(error.localizedDescription)"
            }
        }
        if let recipe {
            if !recipe.steps.contains(where: { $0.id == session.stepID }) { session.stepID = recipe.steps.first?.id }
            if let original = recipe.servings, original > 0 {
                session.servings = max(1, servings ?? session.servings ?? original)
            } else {
                session.servings = nil
            }
            let validTimers = session.timers.filter { entry in
                recipe.steps.contains { $0.id == entry.key && $0.durationSeconds == entry.value.durationSeconds }
            }
            for id in session.timers.keys where validTimers[id] == nil { cancelNotification(for: id) }
            session.timers = validTimers
        }
        updateScreenAwake()
        synchronizeNotifications()
        persistSession()
    }

    private func disappear() {
        persistSession()
        if !requiresSessionRecovery, let currentServings = session.servings { onServingsChanged?(currentServings) }
        if let originalIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled }
        originalIdleTimerDisabled = nil
    }

    private func updateScreenAwake() {
        guard let originalIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled = recipe?.steps.isEmpty == false && !requiresSessionRecovery && !session.isComplete && scenePhase == .active && store.settings.keepScreenAwake ? true : originalIdleTimerDisabled
    }

    private func stepIndex(in recipe: Recipe) -> Int {
        recipe.steps.firstIndex(where: { $0.id == session.stepID }) ?? 0
    }

    private func selectStep(_ id: UUID) {
        session.stepID = id
        persistSession()
    }

    private func startTimer(_ step: RecipeStep) {
        guard let duration = step.durationSeconds, duration > 0 else { return }
        var timer = session.timers[step.id] ?? CookingTimer(durationSeconds: duration)
        if timer.remaining(at: .now) == 0 { timer.reset() }
        timer.start()
        session.timers[step.id] = timer
        persistSession()
        scheduleNotification(for: step.id, timer: timer)
    }

    private func pauseTimer(_ step: RecipeStep) {
        guard var timer = session.timers[step.id] else { return }
        timer.pause()
        session.timers[step.id] = timer
        cancelNotification(for: step.id)
        persistSession()
    }

    private func resetTimer(_ step: RecipeStep) {
        guard let duration = step.durationSeconds, duration > 0 else { return }
        session.timers[step.id] = CookingTimer(durationSeconds: duration)
        cancelNotification(for: step.id)
        persistSession()
    }

    private func requestFinish() {
        if session.timers.values.contains(where: { $0.isRunning && $0.remaining(at: .now) > 0 }) {
            isConfirmingFinish = true
        } else { finishCooking() }
    }

    private func finishCooking() {
        for id in Array(session.timers.keys) {
            if var timer = session.timers[id] { timer.pause(); session.timers[id] = timer }
            cancelNotification(for: id)
        }
        session.isComplete = true
        persistSession()
        if let originalIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled }
    }

    private func restartCooking(_ recipe: Recipe) {
        for id in session.timers.keys { cancelNotification(for: id) }
        session = PersistedCookingSession(stepID: recipe.steps.first?.id, servings: session.servings)
        persistSession()
        updateScreenAwake()
    }

    private func persistSession() {
        guard didRestoreSession, !requiresSessionRecovery, recipe != nil else { return }
        do { UserDefaults.standard.set(try JSONEncoder().encode(session), forKey: sessionKey) }
        catch { errorMessage = "Your cooking progress could not be saved. \(error.localizedDescription)" }
    }

    private func cookingServings(original: Int) -> Binding<Int> {
        Binding(get: { session.servings ?? original }, set: { session.servings = $0; persistSession() })
    }

    private func notificationID(for stepID: UUID) -> String { "cook.timer.\(recipeID.uuidString).\(stepID.uuidString)" }

    private func cancelNotification(for stepID: UUID) {
        notificationTasks[stepID]?.cancel()
        TimerNotifications.cancel(id: notificationID(for: stepID))
    }

    private func scheduleNotification(for stepID: UUID, timer: CookingTimer) {
        guard store.settings.timerNotifications, timer.isRunning, timer.remaining(at: .now) > 0 else { return }
        let previous = notificationTasks[stepID]
        previous?.cancel()
        let id = notificationID(for: stepID)
        let title = recipe?.steps.first(where: { $0.id == stepID })?.title ?? "Cooking timer"
        notificationTasks[stepID] = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            do {
                let seconds = timer.remaining(at: .now)
                guard seconds > 0 else { return }
                try await TimerNotifications.schedule(id: id, title: title.isEmpty ? "Cooking timer" : title, seconds: seconds)
                if Task.isCancelled || !store.settings.timerNotifications {
                    TimerNotifications.cancel(id: id)
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = "The timer is running, but its notification could not be scheduled. \(error.localizedDescription)"
                }
            }
        }
    }

    private func synchronizeNotifications() {
        for (id, timer) in session.timers {
            if !session.isComplete && store.settings.timerNotifications && timer.isRunning && timer.remaining(at: .now) > 0 {
                scheduleNotification(for: id, timer: timer)
            } else { cancelNotification(for: id) }
        }
    }

    static func discardSession(recipeID: UUID) {
        UserDefaults.standard.removeObject(forKey: "cook.cookingSession.\(recipeID.uuidString)")
        Task { @MainActor in await removeSessionNotifications(recipeID: recipeID) }
    }

    private static func removeSessionNotifications(recipeID: UUID) async {
        let prefix = "cook.timer.\(recipeID.uuidString)."
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter { $0.hasPrefix(prefix) })
    }

    private func replaceUnreadableSession() {
        guard let recipe, !isReplacingSession else { return }
        isReplacingSession = true
        Task { @MainActor in
            await Self.removeSessionNotifications(recipeID: recipeID)
            let initialServings = recipe.servings.flatMap { $0 > 0 ? max(1, servings ?? $0) : nil }
            session = PersistedCookingSession(stepID: recipe.steps.first?.id, servings: initialServings)
            requiresSessionRecovery = false
            isReplacingSession = false
            persistSession()
            updateScreenAwake()
        }
    }
}

private struct PersistedCookingSession: Codable {
    var stepID: UUID? = nil
    var timers: [UUID: CookingTimer] = [:]
    var isComplete = false
    var servings: Int? = nil
    var usedIngredientIDs: Set<UUID> = []
}

private struct CookingStepTimerPanel: View {
    let timer: CookingTimer
    let notificationsEnabled: Bool
    let onStart: () -> Void
    let onPause: () -> Void
    let onReset: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = timer.remaining(at: context.date)
            VStack(alignment: .leading, spacing: 14) {
                Label(remaining == 0 ? "Time’s up" : "Step Timer", systemImage: remaining == 0 ? "bell.badge" : "timer")
                    .font(CookTheme.text(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(CookTheme.accent)
                Text(clockText(remaining))
                    .font(CookTheme.title(52))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityLabel("Time remaining")
                    .accessibilityValue(spokenDuration(remaining))
                    .accessibilityIdentifier("cookingTimerValue")
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                timerControls(remaining: remaining)
                Text(remaining == 0 ? "Continue when you’re ready. The next step is up to you." : notificationMessage)
                    .font(CookTheme.text(12, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CookTheme.card, in: RoundedRectangle(cornerRadius: 24))
            .sensoryFeedback(.success, trigger: remaining == 0)
        }
    }

    private var notificationMessage: String {
        notificationsEnabled ? "Your timer keeps time when you leave this screen." : "Your timer progress is saved. Keep Cook open to see when time is up."
    }

    private func timerControls(remaining: Int) -> some View {
        let running = timer.isRunning && remaining > 0
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Button(action: running ? onPause : onStart) {
                Label(running ? "Pause" : (remaining == 0 ? "Start Again" : (remaining < timer.durationSeconds ? "Resume" : "Start Timer")),
                      systemImage: running ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier(running ? "timerPause" : "timerStart")
            Button(action: onReset) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(!timer.isRunning && remaining == timer.durationSeconds)
            .accessibilityIdentifier("cookingTimerResetButton")
        }
    }

    private func clockText(_ seconds: Int) -> String {
        if seconds >= 3_600 { return String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func spokenDuration(_ seconds: Int) -> String {
        if seconds == 0 { return "Time’s up" }
        if seconds >= 3_600 { return "\(seconds / 3_600) hours, \(seconds / 60 % 60) minutes, \(seconds % 60) seconds" }
        return "\(seconds / 60) minutes, \(seconds % 60) seconds"
    }
}
