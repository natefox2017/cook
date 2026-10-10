// Developer: gengyun
// Purpose: Implements the focused cooking workspace, session persistence, ingredients, and timers.

import AVFoundation
import Combine
import RecipeCore
import Speech
import SwiftUI
import UIKit
import UserNotifications

struct CookingView: View {
    let recipeID: UUID
    let servings: Int?
    let startStepID: UUID?
    let onServingsChanged: ((Int) -> Void)?

    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @StateObject private var voice = CookingVoiceController()
    @State private var session = PersistedCookingSession()
    @State private var didRestoreSession = false
    @State private var requiresSessionRecovery = false
    @State private var isConfirmingSessionRecovery = false
    @State private var isReplacingSession = false
    @State private var isShowingIngredients = false
    @State private var parameterInfo: RecipeParameterInfo?
    @State private var isShowingTimers = false
    @State private var isAddingManualTimer = false
    @State private var isRenamingManualTimer = false
    @State private var isConfirmingFinish = false
    @State private var pendingFinishStepID: UUID?
    @State private var manualTimerLabel = ""
    @State private var manualTimerRenameID: UUID?
    @State private var manualTimerRenameDraft = ""
    @State private var manualTimerMinutes = 5
    @State private var errorMessage: String?
    @State private var originalIdleTimerDisabled: Bool?
    @AppStorage("recipe.timer.warningLeadSeconds") private var warningLeadSeconds = 30
    @AppStorage("recipe.timer.finishSound") private var completionSoundEnabled = true

    private var recipe: Recipe? { store.recipe(id: recipeID) }
    private var sessionKey: String {
        RecipeUITestNamespace.preferenceKey(
            "recipe.cookingSession.\(recipeID.uuidString)"
        )
    }

    init(
        recipeID: UUID,
        servings: Int? = nil,
        startStepID: UUID? = nil,
        onServingsChanged: ((Int) -> Void)? = nil
    ) {
        self.recipeID = recipeID
        self.servings = servings
        self.startStepID = startStepID
        self.onServingsChanged = onServingsChanged
    }

    var body: some View {
        NavigationStack {
            Group {
                if let recipe, !recipe.steps.isEmpty {
                    if requiresSessionRecovery {
                        sessionRecoveryContent
                    } else if session.isComplete {
                        completionContent(recipe)
                    } else {
                        cookingContent(recipe)
                    }
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
            .background(RecipeTheme.canvas)
            .navigationTitle("Cooking Mode")
            .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
            .toolbar { cookingToolbar }
            .onChange(of: voice.commandRevision) { _, _ in
                if let command = voice.lastCommand { handleVoiceCommand(command) }
            }
            .onChange(of: session.isComplete) { _, complete in
                if complete { voice.stop() }
            }
            .sheet(isPresented: $isShowingIngredients) { ingredientSheet }
            .sheet(item: $parameterInfo) { info in RecipeParameterSheet(info: info) }
            .sheet(isPresented: $isShowingTimers) { timersSheet }
            .confirmationDialog(
                "Finish and stop active timers?",
                isPresented: $isConfirmingFinish,
                titleVisibility: .visible
            ) {
                Button("Finish Cooking", action: finishCooking)
                    .accessibilityIdentifier("confirmFinishCooking")
                Button("Keep Cooking", role: .cancel) {
                    pendingFinishStepID = nil
                }
            } message: {
                Text("Your running timers will stop when you finish this recipe.")
            }
            .confirmationDialog(
                "Replace saved cooking progress?",
                isPresented: $isConfirmingSessionRecovery,
                titleVisibility: .visible
            ) {
                Button("Start a New Session") { replaceUnreadableSession() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This replaces the unreadable cooking progress for this recipe. The recipe itself is kept."
                )
            }
            .alert(
                "Cooking",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled()
        .onAppear(perform: appear)
        .onDisappear(perform: disappear)
        .onChange(of: scenePhase) { _, phase in
            updateScreenAwake()
            if phase != .active {
                voice.stop()
                persistSession()
            }
        }
        .onChange(of: store.settings.keepScreenAwake) { _, _ in updateScreenAwake() }
        .onChange(of: store.settings.timerNotifications) { _, _ in synchronizeNotifications() }
        .onChange(of: warningLeadSeconds) { _, _ in synchronizeNotifications() }
        .onChange(of: completionSoundEnabled) { _, _ in synchronizeNotifications() }
        .onChange(of: recipe?.id) { _, id in
            if id == nil {
                voice.stop()
                for timerID in session.timers.keys { cancelNotification(for: timerID) }
                Self.discardSession(recipeID: recipeID)
                if let originalIdleTimerDisabled {
                    UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled
                }
            }
        }
    }

    private func cookingContent(_ recipe: Recipe) -> some View {
        let index = stepIndex(in: recipe)
        let step = recipe.steps[index]

        return ScrollView {
            VStack(alignment: .leading, spacing: RecipeSpacing.large) {
                if !dynamicTypeSize.isAccessibilitySize {
                    RecipeImage(recipe: recipe, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                }

                Text(
                    recipe.title.isEmpty
                        ? String(
                            localized: LocalizedStringResource(
                                "Untitled Recipe", locale: RecipeLanguage.active)) : recipe.title
                )
                .font(RecipeTheme.text(17, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(.secondary)

                progress(index: index, count: recipe.steps.count)

                if voice.isListening {
                    Label("Listening for Next, Previous or Repeat", systemImage: "waveform")
                        .font(RecipeTheme.text(13, relativeTo: .footnote))
                        .foregroundStyle(RecipeTheme.accentForeground)
                        .accessibilityIdentifier("cookingVoiceListening")
                } else if !voice.status.isEmpty {
                    Text(voice.status)
                        .font(RecipeTheme.text(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: RecipeSpacing.small) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(
                            step.title.isEmpty
                                ? String(
                                    localized: LocalizedStringResource(
                                        "Step \(index + 1)", locale: RecipeLanguage.active))
                                : step.title
                        )
                        .font(RecipeTheme.heading(.hero))
                        .accessibilityAddTraits(.isHeader)
                        Spacer()
                        if session.completedStepIDs.contains(step.id) {
                            Label("Done", systemImage: "checkmark.circle.fill")
                                .font(
                                    RecipeTheme.text(13, weight: .semibold, relativeTo: .footnote)
                                )
                                .foregroundStyle(RecipeTheme.accentForeground)
                        }
                    }

                    Text(step.instruction)
                        .font(RecipeTheme.body(25))
                        .lineSpacing(RecipeSpacing.readingLine)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("cookingStepInstruction")
                }
                .contentShape(Rectangle())
                // Match the Previous / Done & Next buttons, including finish confirmation.
                // Attach to the step text only; timers and ingredient controls retain their drags.
                .gesture(
                    DragGesture(minimumDistance: 55)
                        .onEnded { value in
                            guard let direction = RecipeHorizontalSwipe(translation: value.translation)
                            else {
                                return
                            }
                            switch direction {
                            case .previous:
                                moveToPreviousStep(recipe)
                            case .next:
                                moveToNextStep(recipe)
                            }
                        }
                )
                .accessibilityIdentifier("cookingStepSwipeSurface")

                if let temperature = step.temperature, !temperature.text.isEmpty {
                    Button {
                        parameterInfo = .temperature(temperature)
                    } label: {
                        Label(temperature.text, systemImage: "thermometer.medium")
                            .font(RecipeTheme.text(16, weight: .semibold, relativeTo: .headline))
                            .foregroundStyle(RecipeTheme.accentForeground)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(RecipeTheme.accent.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Show temperature conversion")
                    .accessibilityIdentifier("cookingStepTemperatureInfo")
                }

                stepIngredients(step, recipe: recipe)

                if !step.timers.isEmpty {
                    VStack(alignment: .leading, spacing: RecipeSpacing.small) {
                        Text(
                            step.timers.count == 1
                                ? LocalizedStringKey("Timer")
                                : LocalizedStringKey("Timers for this step")
                        )
                        .font(RecipeTheme.text(15, weight: .semibold, relativeTo: .subheadline))
                        ForEach(step.timers) { definition in
                            CookingStepTimerPanel(
                                label: definition.label,
                                timer: timerState(for: definition),
                                notificationsEnabled: store.settings.timerNotifications,
                                onStart: { startTimer(definition, stepID: step.id) },
                                onPause: { pauseTimer(definition.id) },
                                onReset: { resetTimer(definition, stepID: step.id) },
                                onInfo: { parameterInfo = .timer(definition) }
                            )
                        }
                    }
                }

                otherTimerLinks(currentStepID: step.id, recipe: recipe)

                Button {
                    isShowingIngredients = true
                } label: {
                    Label("View All Ingredients", systemImage: "carrot")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .recipePageContentInsets()
        }
        .accessibilityIdentifier("cookingScroll")
        .safeAreaInset(edge: .bottom) {
            stepControls(recipe, index: index)
        }
    }

    private func progress(index: Int, count: Int) -> some View {
        let completed = session.completedStepIDs.count
        return VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
            HStack {
                Text("Step \(index + 1) of \(count)")
                    .font(RecipeTheme.text(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(RecipeTheme.accentForeground)
                    .accessibilityIdentifier("cookingStepProgress")
                Spacer()
                Text("\(completed) done")
                    .font(RecipeTheme.text(13, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(completed), total: Double(max(1, count)))
                .tint(RecipeTheme.accent)
                .accessibilityLabel("Cooking progress")
                .accessibilityValue(
                    count == 1
                        ? LocalizedStringKey("\(completed) of \(count) step completed")
                        : LocalizedStringKey("\(completed) of \(count) steps completed")
                )
        }
    }

    @ViewBuilder
    private func stepIngredients(_ step: RecipeStep, recipe: Recipe) -> some View {
        let linked = recipe.ingredients.filter { step.linkedIngredientIDs.contains($0.id) }
        if !linked.isEmpty {
            VStack(alignment: .leading, spacing: RecipeSpacing.small) {
                HStack {
                    Label("For this step", systemImage: "carrot")
                        .font(RecipeTheme.text(15, weight: .semibold, relativeTo: .subheadline))
                    Spacer()
                    if let servings = session.servings {
                        Text("\(servings) servings")
                            .font(RecipeTheme.text(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(linked) { ingredient in
                    HStack(spacing: 6) {
                        Button {
                            toggleIngredient(ingredient.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(
                                    systemName: session.usedIngredientIDs.contains(ingredient.id)
                                        ? "checkmark.circle.fill" : "circle"
                                )
                                .foregroundStyle(
                                    session.usedIngredientIDs.contains(ingredient.id)
                                        ? RecipeTheme.accentForeground : Color.secondary
                                )
                                Text(ingredient.name).foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                let amount = ingredient.displayAmount(
                                    servings: session.servings,
                                    originalServings: recipe.servings
                                )
                                if !amount.isEmpty { Text(amount).foregroundStyle(.secondary) }
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            session.usedIngredientIDs.contains(ingredient.id)
                                ? LocalizedStringKey("\(ingredient.name), used")
                                : LocalizedStringKey("\(ingredient.name), not used")
                        )
                        Button {
                            parameterInfo = .ingredient(
                                ingredient, servings: session.servings,
                                originalServings: recipe.servings)
                        } label: {
                            Image(systemName: "info.circle")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show ingredient amount details")
                        .accessibilityIdentifier("cookingIngredientInfo.\(ingredient.id.uuidString)")
                    }
                }
            }
            .padding(16)
            .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private func stepControls(_ recipe: Recipe, index: Int) -> some View {
        let step = recipe.steps[index]
        let isDone = session.completedStepIDs.contains(step.id)
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 14))

        return layout {
            Button {
                moveToPreviousStep(recipe)
            } label: {
                Label("Previous", systemImage: "arrow.left")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(index == 0)
            .accessibilityIdentifier("previousStep")

            Button {
                moveToNextStep(recipe)
            } label: {
                HStack {
                    Text(
                        LocalizedStringKey(
                            index + 1 == recipe.steps.count
                                ? "Finish Cooking"
                                : (isDone ? "Next Step" : "Done & Next")
                        )
                    )
                    Image(
                        systemName: index + 1 == recipe.steps.count
                            ? "checkmark"
                            : "arrow.right"
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("nextStep")
        }
        .padding(.horizontal, RecipeSpacing.pageInset)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func otherTimerLinks(currentStepID: UUID, recipe: Recipe) -> some View {
        let others = session.timers.values
            .filter { $0.isManual || $0.stepID != currentStepID }
            .filter {
                $0.timer.isRunning || $0.timer.remaining(at: .now) < $0.timer.durationSeconds
            }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }

        if !others.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
                    HStack {
                        Text("Other Timers")
                            .font(RecipeTheme.text(15, weight: .semibold, relativeTo: .subheadline))
                        Spacer()
                        Button("Manage") { isShowingTimers = true }
                            .font(RecipeTheme.text(13, weight: .semibold, relativeTo: .footnote))
                    }

                    ForEach(others) { active in
                        let remaining = active.timer.remaining(at: context.date)
                        Button {
                            if let stepID = active.stepID,
                                recipe.steps.contains(where: { $0.id == stepID })
                            {
                                selectStep(stepID)
                            } else {
                                isShowingTimers = true
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: RecipeSpacing.xxSmall) {
                                    Label(active.label, systemImage: "timer")
                                    Text(
                                        remaining == 0
                                            ? String(
                                                localized: LocalizedStringResource(
                                                    "Time’s up", locale: RecipeLanguage.active
                                                )
                                            )
                                            : String(
                                                localized: LocalizedStringResource(
                                                    "\(CookingClockFormatter.text(remaining)) remaining",
                                                    locale: RecipeLanguage.active))
                                    )
                                    .font(RecipeTheme.text(12, relativeTo: .caption))
                                    .monospacedDigit()
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.success, trigger: remaining == 0)
                    }
                }
                .padding(16)
                .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 22))
            }
        }
    }

    private func completionContent(_ recipe: Recipe) -> some View {
        ScrollView {
            VStack(spacing: RecipeSpacing.large) {
                RecipeImage(recipe: recipe, height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(RecipeTheme.accentForeground)
                    .accessibilityHidden(true)

                Text("Ready to enjoy")
                    .font(RecipeTheme.heading(.hero))
                    .accessibilityAddTraits(.isHeader)

                Text(
                    String(
                        localized: LocalizedStringResource(
                            "\(session.completedStepIDs.count) of \(recipe.steps.count) steps completed.",
                            locale: RecipeLanguage.active
                        )
                    )
                )
                .lineLimit(1)
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
        VStack(spacing: RecipeSpacing.medium) {
            EmptyStateView(
                title: "Your cooking progress needs attention",
                message:
                    "The saved session could not be read. Its original data has been kept. Start a new session to cook this recipe again.",
                systemImage: "clock.badge.exclamationmark",
                actionTitle: "Start a New Session",
                action: { isConfirmingSessionRecovery = true },
                messageLineLimit: nil
            )
            .disabled(isReplacingSession)

            if isReplacingSession {
                ProgressView("Starting a fresh session…")
            }
        }
    }

    @ToolbarContentBuilder
    private var cookingToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark") { dismiss() }
                .accessibilityIdentifier("closeCookingButton")
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                if voice.isListening {
                    voice.stop()
                } else {
                    Task { await voice.start() }
                }
            } label: {
                Label(
                    voice.isListening ? "Stop voice control" : "Hands-free voice control",
                    systemImage: voice.isListening ? "mic.fill" : "mic.slash")
            }
            .disabled(recipe?.steps.isEmpty != false || session.isComplete || requiresSessionRecovery)
            .accessibilityIdentifier("cookingVoiceToggle")

            Button {
                isShowingTimers = true
            } label: {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let runningCount = session.runningTimerCount(at: context.date)
                    Label {
                        if runningCount > 0 {
                            Text("\(runningCount) timer")
                        } else {
                            Text("Timers")
                        }
                    } icon: {
                        Image(systemName: "timer")
                    }
                }
            }
            .disabled(recipe == nil)
            .accessibilityIdentifier("cookingTimersButton")

            Button("Ingredients", systemImage: "list.bullet") {
                isShowingIngredients = true
            }
            .disabled(recipe == nil)
        }
    }

    private var ingredientSheet: some View {
        NavigationStack {
            List {
                if let recipe {
                    Section {
                        if let original = recipe.servings, original > 0 {
                            Stepper(
                                "\(session.servings ?? original) servings",
                                value: cookingServings(original: original),
                                in: 1...max(100, max(original, session.servings ?? original))
                            )
                        }

                        if recipe.ingredients.isEmpty {
                            Text("This recipe has no ingredients yet.")
                                .foregroundStyle(.secondary)
                        }

                        ForEach(recipe.ingredients) { ingredient in
                            Button {
                                toggleIngredient(ingredient.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(
                                        systemName: session.usedIngredientIDs.contains(
                                            ingredient.id)
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                    )
                                    .foregroundStyle(
                                        session.usedIngredientIDs.contains(ingredient.id)
                                            ? RecipeTheme.accentForeground
                                            : Color.secondary
                                    )

                                    VStack(alignment: .leading, spacing: RecipeSpacing.xxSmall) {
                                        Text(ingredient.name)
                                            .font(
                                                RecipeTheme.text(
                                                    17, weight: .semibold, relativeTo: .headline))

                                        let amount = ingredient.displayAmount(
                                            servings: session.servings,
                                            originalServings: recipe.servings
                                        )
                                        if !amount.isEmpty {
                                            Text(amount)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                session.usedIngredientIDs.contains(ingredient.id)
                                    ? LocalizedStringKey("\(ingredient.name), used")
                                    : LocalizedStringKey("\(ingredient.name), not used")
                            )
                        }
                    } header: {
                        Text(
                            recipe.servings.map {
                                $0 > 0 ? "Cooking portions" : "Original recipe amounts"
                            } ?? "Original recipe amounts"
                        )
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(RecipeTheme.canvas)
            .navigationTitle("Ingredients")
            .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isShowingIngredients = false }
                }
            }
        }
    }

    private var timersSheet: some View {
        NavigationStack {
            Group {
                if session.timers.isEmpty {
                    EmptyStateView(
                        title: "No timers yet",
                        message: "Start a timer from a cooking step, or add a kitchen timer here.",
                        systemImage: "timer",
                        actionTitle: "Add Timer",
                        action: { isAddingManualTimer = true }
                    )
                } else {
                    List {
                        Section("Kitchen timers") {
                            ForEach(
                                session.timers.values.sorted {
                                    $0.label.localizedCaseInsensitiveCompare($1.label)
                                        == .orderedAscending
                                }
                            ) { active in
                                timerManagerRow(active)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(RecipeTheme.canvas)
            .navigationTitle("Timers")
            .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Add", systemImage: "plus") {
                        isAddingManualTimer = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isShowingTimers = false }
                }
            }
            .sheet(isPresented: $isAddingManualTimer) {
                manualTimerSheet
            }
            .alert("Rename Timer", isPresented: $isRenamingManualTimer) {
                TextField("Timer label", text: $manualTimerRenameDraft)
                Button("Cancel", role: .cancel) {
                    resetManualTimerRenameDraft()
                }
                Button("Save", action: saveManualTimerRename)
                    .disabled(
                        manualTimerRenameDraft.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
            }
        }
    }

    private func timerManagerRow(_ active: PersistedActiveTimer) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = active.timer.remaining(at: context.date)
            let running = active.timer.isRunning && remaining > 0

            VStack(alignment: .leading, spacing: RecipeSpacing.xSmall) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: RecipeSpacing.xxSmall) {
                        if active.isManual {
                            Button {
                                beginManualTimerRename(active)
                            } label: {
                                Text(active.label)
                                    .font(
                                        RecipeTheme.text(16, weight: .semibold, relativeTo: .headline)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Rename timer")
                            .accessibilityValue(active.label)
                            .accessibilityIdentifier("cookingTimerRename.\(active.id.uuidString)")
                        } else {
                            Text(active.label)
                                .font(RecipeTheme.text(16, weight: .semibold, relativeTo: .headline))
                        }
                        Text(
                            remaining == 0
                                ? String(
                                    localized: LocalizedStringResource(
                                        "Time’s up", locale: RecipeLanguage.active))
                                : CookingClockFormatter.text(remaining)
                        )
                        .font(RecipeTheme.text(20, weight: .semibold, relativeTo: .title3))
                        .monospacedDigit()
                    }
                    Spacer()
                    if active.isManual {
                        Text("Manual")
                            .font(RecipeTheme.text(11, relativeTo: .caption2))
                            .foregroundStyle(.secondary)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        timerManagerButtons(active, running: running, remaining: remaining)
                    }
                    VStack(spacing: RecipeSpacing.xSmall) {
                        timerManagerButtons(active, running: running, remaining: remaining)
                    }
                }
            }
            .padding(.vertical, 6)
            .sensoryFeedback(.success, trigger: remaining == 0)
        }
    }

    @ViewBuilder
    private func timerManagerButtons(
        _ active: PersistedActiveTimer,
        running: Bool,
        remaining: Int
    ) -> some View {
        Button(
            LocalizedStringKey(running ? "Pause" : (remaining == 0 ? "Start Again" : "Start"))
        ) {
            if running {
                pauseTimer(active.id)
            } else {
                startActiveTimer(active.id)
            }
        }
        .buttonStyle(.borderedProminent)

        Button("Reset") {
            resetActiveTimer(active.id)
        }
        .buttonStyle(.bordered)

        Button("Delete", role: .destructive) {
            deleteTimer(active.id)
        }
        .buttonStyle(.bordered)
    }

    private var manualTimerSheet: some View {
        NavigationStack {
            Form {
                Section("Timer") {
                    TextField("Name", text: $manualTimerLabel)
                    Stepper(
                        "\(manualTimerMinutes) minute",
                        value: $manualTimerMinutes,
                        in: 1...720
                    )
                }
            }
            .navigationTitle("Add Timer")
            .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        resetManualTimerDraft()
                        isAddingManualTimer = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        addManualTimer()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func toggleIngredient(_ id: UUID) {
        if session.usedIngredientIDs.contains(id) {
            session.usedIngredientIDs.remove(id)
        } else {
            session.usedIngredientIDs.insert(id)
        }
        persistSession()
    }

    private func appear() {
        if originalIdleTimerDisabled == nil {
            originalIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        }

        guard !didRestoreSession else {
            updateScreenAwake()
            return
        }

        didRestoreSession = true
        // Session recovery is conservative: missing or edited recipe steps are reconciled below.
        if let data = UserDefaults.standard.data(forKey: sessionKey) {
            do {
                session = try JSONDecoder().decode(PersistedCookingSession.self, from: data)
            } catch {
                requiresSessionRecovery = true
                errorMessage = String(
                    localized: LocalizedStringResource(
                        "Your previous cooking session could not be restored. \(error.localizedDescription)",
                        locale: RecipeLanguage.active))
            }
        }

        if let recipe {
            if !recipe.steps.contains(where: { $0.id == session.stepID }) {
                session.stepID = recipe.steps.first?.id
            }

            if session.needsLegacyCompletedStepMigration {
                session.completedStepIDs = Set(recipe.steps.map(\.id))
                session.needsLegacyCompletedStepMigration = false
            } else {
                session.completedStepIDs = Set(
                    session.completedStepIDs.filter { completedID in
                        recipe.steps.contains(where: { $0.id == completedID })
                    })
            }

            if let original = recipe.servings, original > 0 {
                session.servings = max(1, servings ?? session.servings ?? original)
            } else {
                session.servings = nil
            }

            reconcileTimers(with: recipe)

            if let startStepID,
                recipe.steps.contains(where: { $0.id == startStepID })
            {
                applyRequestedStartStep(startStepID, in: recipe)
            }
        }

        updateScreenAwake()
        synchronizeNotifications()
        persistSession()
    }

    private func disappear() {
        voice.stop()
        persistSession()

        if !requiresSessionRecovery, let currentServings = session.servings {
            onServingsChanged?(currentServings)
        }

        if let originalIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled
        }
        originalIdleTimerDisabled = nil
    }

    private func updateScreenAwake() {
        guard let originalIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled =
            recipe?.steps.isEmpty == false
                && !requiresSessionRecovery
                && !session.isComplete
                && scenePhase == .active
                && store.settings.keepScreenAwake
            ? true
            : originalIdleTimerDisabled
    }

    private func stepIndex(in recipe: Recipe) -> Int {
        recipe.steps.firstIndex(where: { $0.id == session.stepID }) ?? 0
    }

    private func selectStep(_ id: UUID) {
        session.stepID = id
        persistSession()
    }

    // Physical buttons and voice use exactly the same navigation/persistence semantics.
    private func moveToPreviousStep(_ recipe: Recipe) {
        let index = stepIndex(in: recipe)
        if index > 0 { selectStep(recipe.steps[index - 1].id) }
    }

    private func moveToNextStep(_ recipe: Recipe) {
        let index = stepIndex(in: recipe)
        let step = recipe.steps[index]
        if index + 1 < recipe.steps.count {
            session.completedStepIDs.insert(step.id)
            selectStep(recipe.steps[index + 1].id)
        } else {
            requestFinish(stepID: step.id)
        }
    }

    private func handleVoiceCommand(_ command: CookingVoiceCommand) {
        guard let recipe, !recipe.steps.isEmpty, !session.isComplete,
            !requiresSessionRecovery
        else { return }
        switch command {
        case .next:
            moveToNextStep(recipe)
        case .previous:
            moveToPreviousStep(recipe)
        case .repeatStep:
            voice.readAloud(recipe.steps[stepIndex(in: recipe)].instruction)
        case .stop:
            voice.stop()
        }
    }

    private func timerState(for definition: RecipeStepTimer) -> CookingTimer {
        session.timers[definition.id]?.timer
            ?? CookingTimer(durationSeconds: definition.durationSeconds)
    }

    private func startTimer(_ definition: RecipeStepTimer, stepID: UUID) {
        var active =
            session.timers[definition.id]
            ?? PersistedActiveTimer(
                id: definition.id,
                stepID: stepID,
                label: definition.label.isEmpty ? "Step timer" : definition.label,
                timer: CookingTimer(durationSeconds: definition.durationSeconds),
                isManual: false
            )

        if active.timer.remaining(at: .now) == 0 {
            active.timer.reset()
        }
        active.timer.start()
        active.label = definition.label.isEmpty ? "Step timer" : definition.label
        active.stepID = stepID
        session.timers[definition.id] = active
        persistSession()
        scheduleNotification(for: active)
    }

    private func startActiveTimer(_ id: UUID) {
        guard var active = session.timers[id] else { return }
        if active.timer.remaining(at: .now) == 0 {
            active.timer.reset()
        }
        active.timer.start()
        session.timers[id] = active
        persistSession()
        scheduleNotification(for: active)
    }

    private func pauseTimer(_ id: UUID) {
        guard var active = session.timers[id] else { return }
        active.timer.pause()
        session.timers[id] = active
        cancelNotification(for: id)
        persistSession()
    }

    private func resetTimer(_ definition: RecipeStepTimer, stepID: UUID) {
        let active = PersistedActiveTimer(
            id: definition.id,
            stepID: stepID,
            label: definition.label.isEmpty ? "Step timer" : definition.label,
            timer: CookingTimer(durationSeconds: definition.durationSeconds),
            isManual: false
        )
        session.timers[definition.id] = active
        cancelNotification(for: definition.id)
        persistSession()
    }

    private func resetActiveTimer(_ id: UUID) {
        guard var active = session.timers[id] else { return }
        active.timer.reset()
        session.timers[id] = active
        cancelNotification(for: id)
        persistSession()
    }

    private func deleteTimer(_ id: UUID) {
        session.timers.removeValue(forKey: id)
        cancelNotification(for: id)
        persistSession()
    }

    private func addManualTimer() {
        let id = UUID()
        let label = manualTimerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        var timer = CookingTimer(durationSeconds: manualTimerMinutes * 60)
        timer.start()

        let active = PersistedActiveTimer(
            id: id,
            stepID: session.stepID,
            label: label.isEmpty ? "Kitchen timer" : label,
            timer: timer,
            isManual: true
        )

        session.timers[id] = active
        persistSession()
        scheduleNotification(for: active)
        resetManualTimerDraft()
        isAddingManualTimer = false
    }

    private func resetManualTimerDraft() {
        manualTimerLabel = ""
        manualTimerMinutes = 5
    }

    private func beginManualTimerRename(_ active: PersistedActiveTimer) {
        guard active.isManual else {
            return
        }
        manualTimerRenameID = active.id
        manualTimerRenameDraft = active.label
        isRenamingManualTimer = true
    }

    private func saveManualTimerRename() {
        let label = manualTimerRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty,
            let id = manualTimerRenameID,
            var active = session.timers[id],
            active.isManual
        else {
            resetManualTimerRenameDraft()
            return
        }

        active.label = label
        session.timers[id] = active
        persistSession()
        if active.timer.isRunning { scheduleNotification(for: active) }
        resetManualTimerRenameDraft()
    }

    private func resetManualTimerRenameDraft() {
        manualTimerRenameID = nil
        manualTimerRenameDraft = ""
    }

    private func requestFinish(stepID: UUID) {
        pendingFinishStepID = stepID
        if session.timers.values.contains(where: {
            $0.timer.isRunning && $0.timer.remaining(at: .now) > 0
        }) {
            isConfirmingFinish = true
        } else {
            finishCooking()
        }
    }

    private func finishCooking() {
        if let pendingFinishStepID {
            session.completedStepIDs.insert(pendingFinishStepID)
        }
        self.pendingFinishStepID = nil

        for id in Array(session.timers.keys) {
            if var active = session.timers[id] {
                active.timer.pause()
                session.timers[id] = active
            }
            cancelNotification(for: id)
        }

        session.isComplete = true
        persistSession()

        if let originalIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled
        }
    }

    private func restartCooking(_ recipe: Recipe) {
        for id in session.timers.keys {
            cancelNotification(for: id)
        }
        session = PersistedCookingSession(
            stepID: recipe.steps.first?.id,
            servings: session.servings
        )
        persistSession()
        updateScreenAwake()
    }

    private func persistSession() {
        guard didRestoreSession, !requiresSessionRecovery, recipe != nil else { return }
        do {
            UserDefaults.standard.set(
                try JSONEncoder().encode(session),
                forKey: sessionKey
            )
        } catch {
            errorMessage = String(
                localized: LocalizedStringResource(
                    "Your cooking progress could not be saved. \(error.localizedDescription)",
                    locale: RecipeLanguage.active))
        }
    }

    private func cookingServings(original: Int) -> Binding<Int> {
        Binding(
            get: { session.servings ?? original },
            set: {
                session.servings = $0
                persistSession()
            }
        )
    }

    private func applyRequestedStartStep(_ requestedStepID: UUID, in recipe: Recipe) {
        guard let startIndex = recipe.steps.firstIndex(where: { $0.id == requestedStepID }) else {
            return
        }

        let wasComplete = session.isComplete
        session.stepID = requestedStepID
        session.isComplete = false

        let earlierStepIDs = Set(recipe.steps.prefix(startIndex).map(\.id))
        session.completedStepIDs.formIntersection(earlierStepIDs)

        if wasComplete {
            for timerID in session.timers.keys {
                cancelNotification(for: timerID)
            }
            session.timers.removeAll()
            session.usedIngredientIDs.removeAll()
            return
        }

        let resetStepIDs = Set(recipe.steps.dropFirst(startIndex).map(\.id))
        for (timerID, active) in Array(session.timers) {
            guard !active.isManual,
                let stepID = active.stepID,
                resetStepIDs.contains(stepID)
            else { continue }
            session.timers.removeValue(forKey: timerID)
            cancelNotification(for: timerID)
        }
    }

    private func reconcileTimers(with recipe: Recipe) {
        let definitions = recipe.steps.flatMap { step in
            step.timers.map { timer in
                (timer.id, step.id, timer)
            }
        }

        let definitionsByID = Dictionary(
            uniqueKeysWithValues: definitions.map { ($0.0, ($0.1, $0.2)) }
        )

        var valid: [UUID: PersistedActiveTimer] = [:]

        for (id, active) in session.timers {
            if active.isManual {
                valid[id] = active
                continue
            }

            guard let (stepID, definition) = definitionsByID[id],
                definition.durationSeconds == active.timer.durationSeconds
            else {
                cancelNotification(for: id)
                continue
            }

            var refreshed = active
            refreshed.stepID = stepID
            refreshed.label = definition.label.isEmpty ? "Step timer" : definition.label
            valid[id] = refreshed
        }

        session.timers = valid
    }

    private func notificationID(for timerID: UUID) -> String {
        RecipeUITestNamespace.timerNotificationID(
            recipeID: recipeID,
            timerID: timerID,
            isUITesting: RecipeUITestNamespace.isUITesting
        )
    }

    private func cancelNotification(for timerID: UUID) {
        TimerNotifications.cancel(id: notificationID(for: timerID))
    }

    private func scheduleNotification(for active: PersistedActiveTimer) {
        guard store.settings.timerNotifications,
            active.timer.isRunning,
            active.timer.remaining(at: .now) > 0
        else { return }

        let id = notificationID(for: active.id)
        guard let deadline = active.timer.deadline else { return }
        let scheduleTask = TimerNotifications.schedule(
            id: id,
            title: active.label.isEmpty ? "Cooking timer" : active.label,
            deadline: deadline,
            warningSeconds: warningLeadSeconds,
            completionSoundEnabled: completionSoundEnabled
        )
        Task { @MainActor in
            do {
                try await scheduleTask.value
            } catch {
                if !Task.isCancelled
                    && store.settings.timerNotifications
                {
                    errorMessage = String(
                        localized: LocalizedStringResource(
                            "The timer is running, but its notification could not be scheduled. \(error.localizedDescription)",
                            locale: RecipeLanguage.active))
                }
            }
        }
    }

    private func synchronizeNotifications() {
        for (id, active) in session.timers {
            if !session.isComplete
                && store.settings.timerNotifications
                && active.timer.isRunning
                && active.timer.remaining(at: .now) > 0
            {
                scheduleNotification(for: active)
            } else {
                cancelNotification(for: id)
            }
        }
    }

    static func discardSession(recipeID: UUID) {
        let defaults = UserDefaults.standard
        defaults.removeObject(
            forKey: RecipeUITestNamespace.preferenceKey(
                "recipe.cookingSession.\(recipeID.uuidString)"
            )
        )
        if !RecipeUITestNamespace.isUITesting {
            defaults.removeObject(
                forKey: "cook.cookingSession.\(recipeID.uuidString)"
            )
        }
        Task { @MainActor in
            await removeSessionNotifications(recipeID: recipeID)
        }
    }

    private static func removeSessionNotifications(recipeID: UUID) async {
        let prefix = RecipeUITestNamespace.timerNotificationPrefix(
            recipeID: recipeID,
            isUITesting: RecipeUITestNamespace.isUITesting
        )
        await TimerNotifications.cancelAll(matchingPrefixes: [prefix])
    }

    private func replaceUnreadableSession() {
        guard let recipe, !isReplacingSession else { return }
        isReplacingSession = true

        Task { @MainActor in
            await Self.removeSessionNotifications(recipeID: recipeID)
            let initialServings = recipe.servings.flatMap {
                $0 > 0 ? max(1, servings ?? $0) : nil
            }
            session = PersistedCookingSession(
                stepID: startStepID ?? recipe.steps.first?.id,
                servings: initialServings
            )
            requiresSessionRecovery = false
            isReplacingSession = false
            persistSession()
            updateScreenAwake()
        }
    }

}

private struct PersistedActiveTimer: Identifiable, Codable {
    var id: UUID
    var stepID: UUID?
    var label: String
    var timer: CookingTimer
    var isManual: Bool
}

private struct PersistedCookingSession: Codable {
    var stepID: UUID?
    var timers: [UUID: PersistedActiveTimer]
    var isComplete: Bool
    var servings: Int?
    var usedIngredientIDs: Set<UUID>
    var completedStepIDs: Set<UUID>
    var needsLegacyCompletedStepMigration: Bool

    init(
        stepID: UUID? = nil,
        timers: [UUID: PersistedActiveTimer] = [:],
        isComplete: Bool = false,
        servings: Int? = nil,
        usedIngredientIDs: Set<UUID> = [],
        completedStepIDs: Set<UUID> = []
    ) {
        self.stepID = stepID
        self.timers = timers
        self.isComplete = isComplete
        self.servings = servings
        self.usedIngredientIDs = usedIngredientIDs
        self.completedStepIDs = completedStepIDs
        self.needsLegacyCompletedStepMigration = false
    }

    func runningTimerCount(at date: Date = .now) -> Int {
        timers.values.filter {
            $0.timer.isRunning && $0.timer.remaining(at: date) > 0
        }.count
    }

    private enum CodingKeys: String, CodingKey {
        case stepID
        case timers
        case isComplete
        case servings
        case usedIngredientIDs
        case completedStepIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stepID = try container.decodeIfPresent(UUID.self, forKey: .stepID)
        isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false
        servings = try container.decodeIfPresent(Int.self, forKey: .servings)
        usedIngredientIDs =
            try container.decodeIfPresent(Set<UUID>.self, forKey: .usedIngredientIDs) ?? []
        needsLegacyCompletedStepMigration = isComplete && !container.contains(.completedStepIDs)
        completedStepIDs =
            try container.decodeIfPresent(Set<UUID>.self, forKey: .completedStepIDs) ?? []

        if let current = try? container.decode([UUID: PersistedActiveTimer].self, forKey: .timers) {
            timers = current
        } else if let legacy = try? container.decode([UUID: CookingTimer].self, forKey: .timers) {
            // Older sessions stored only timer values keyed by step ID; restore them as step timers.
            timers = legacy.reduce(into: [:]) { result, entry in
                result[entry.key] = PersistedActiveTimer(
                    id: entry.key,
                    stepID: entry.key,
                    label: "Step timer",
                    timer: entry.value,
                    isManual: false
                )
            }
        } else {
            timers = [:]
        }
    }
}

private struct CookingStepTimerPanel: View {
    let label: String
    let timer: CookingTimer
    let notificationsEnabled: Bool
    let onStart: () -> Void
    let onPause: () -> Void
    let onReset: () -> Void
    let onInfo: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = timer.remaining(at: context.date)

            VStack(alignment: .leading, spacing: RecipeSpacing.small) {
                HStack {
                    Button(action: onInfo) {
                        Label {
                            if remaining == 0 {
                                Text("Time’s up")
                            } else {
                                Text(label)
                            }
                        } icon: {
                            Image(systemName: remaining == 0 ? "bell.badge" : "timer")
                        }
                        .font(RecipeTheme.text(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(RecipeTheme.accentForeground)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Show timer details")
                    .accessibilityIdentifier("cookingTimerInfo")
                    Spacer()
                    Text(durationText(timer.durationSeconds))
                        .font(RecipeTheme.text(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }

                Text(CookingClockFormatter.text(remaining))
                    .font(RecipeTheme.title(48))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityLabel("Time remaining")
                    .accessibilityValue(spokenDuration(remaining))
                    .accessibilityIdentifier("cookingTimerValue")
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                timerControls(remaining: remaining)

                Text(
                    remaining == 0
                        ? LocalizedStringKey(
                            "Continue when you’re ready. The next step is still up to you.")
                        : notificationMessage
                )
                .font(RecipeTheme.text(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
            }
            .padding(RecipeSpacing.pageInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 24))
            .sensoryFeedback(.success, trigger: remaining == 0)
        }
    }

    private var notificationMessage: LocalizedStringKey {
        notificationsEnabled
            ? "Your timer keeps time when you leave this screen."
            : "Your timer progress is saved. Keep Recipe Pals open to see when time is up."
    }

    private func timerControls(remaining: Int) -> some View {
        let running = timer.isRunning && remaining > 0
        let title: LocalizedStringKey
        if running {
            title = "Pause"
        } else if remaining == 0 {
            title = "Start Again"
        } else if remaining < timer.durationSeconds {
            title = "Resume"
        } else {
            title = "Start Timer"
        }
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))

        return layout {
            Button(action: running ? onPause : onStart) {
                Label(
                    title,
                    systemImage: running ? "pause.fill" : "play.fill"
                )
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

    private func durationText(_ seconds: Int) -> String {
        return Duration.seconds(seconds).formatted(
            .units(width: .abbreviated, maximumUnitCount: 2).locale(locale)
        )
    }

    private func spokenDuration(_ seconds: Int) -> String {
        if seconds == 0 {
            return String(localized: LocalizedStringResource("Time’s up", locale: locale))
        }
        return Duration.seconds(seconds).formatted(
            .units(width: .wide, maximumUnitCount: 3).locale(locale)
        )
    }
}

// A single clock format keeps the main cooking flow and timer panel consistent.
private enum CookingClockFormatter {
    static func text(_ seconds: Int) -> String {
        if seconds >= 3_600 {
            return String(
                format: "%d:%02d:%02d",
                seconds / 3_600,
                seconds / 60 % 60,
                seconds % 60
            )
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}


/// Opt-in foreground-only on-device speech control. No recording is stored/uploaded.
@MainActor
private final class CookingVoiceController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isListening = false
    @Published private(set) var status = ""
    @Published private(set) var commandRevision = 0
    private(set) var lastCommand: CookingVoiceCommand?

    private var recognition: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var pendingCandidate: Task<Void, Never>?
    private var cycle: UUID?
    private var tapInstalled = false
    private var wantsListening = false
    private let speaker = AVSpeechSynthesizer()

    override init() {
        super.init()
        speaker.delegate = self
    }

    func start() async {
        guard !wantsListening else { return }
        let authorization = await withCheckedContinuation {
            (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization {
                continuation.resume(returning: $0)
            }
        }
        guard authorization == .authorized else {
            status = "Enable speech recognition in iOS Settings to use hands-free control."
            return
        }
        let micGranted = await withCheckedContinuation {
            (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
        guard micGranted else {
            status = "Microphone access is off. Step buttons still work."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
            recognizer.isAvailable, recognizer.supportsOnDeviceRecognition
        else {
            status = "On-device English voice control is unavailable on this iPhone."
            return
        }
        recognition = recognizer
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .measurement,
                options: [.defaultToSpeaker, .duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            wantsListening = true
            isListening = true
            status = ""
            try beginCycle()
        } catch {
            stop()
            status = "Could not start voice control. Use the step buttons."
        }
    }

    private func beginCycle() throws {
        guard wantsListening, let recognition else { return }
        let token = UUID()
        cycle = token
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) {
            [weak request] buffer, _ in
            request?.append(buffer)
        }
        tapInstalled = true
        recognitionTask = recognition.recognitionTask(with: request) {
            [weak self] result, error in
            if let result {
                let transcript = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                Task { @MainActor [weak self] in
                    self?.receiveCycleResult(
                        token: token, transcript: transcript, isFinal: isFinal)
                }
            } else if error != nil {
                Task { @MainActor [weak self] in
                    guard self?.cycle == token else { return }
                    self?.stop()
                    self?.status = "Voice control stopped. Tap the microphone to restart."
                }
            }
        }
        engine.prepare()
        try engine.start()
    }

    // A stable partial command is useful for speech recognition that never
    // marks a continuous microphone request as final. A subsequent longer
    // utterance cancels this candidate before it changes the cooking step.
    private func receiveCycleResult(
        token: UUID, transcript: String, isFinal: Bool
    ) {
        guard cycle == token, wantsListening else { return }
        pendingCandidate?.cancel()
        pendingCandidate = nil
        guard isFinal || CookingVoiceCommandParser.parse(transcript) != nil else {
            return
        }
        if isFinal {
            completeCycle(token: token, transcript: transcript)
            return
        }
        pendingCandidate = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.completeCycle(token: token, transcript: transcript)
        }
    }

    private func endCycle() {
        pendingCandidate?.cancel()
        pendingCandidate = nil
        cycle = nil
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func completeCycle(token: UUID, transcript: String) {
        guard cycle == token, wantsListening else { return }
        endCycle()
        if let command = CookingVoiceCommandParser.parse(transcript) {
            lastCommand = command
            commandRevision += 1
            if command == .stop { stop(); return }
            if command == .repeatStep { return }  // Wait for the TTS delegate.
        }
        resumeAfterShortPause()
    }

    private func resumeAfterShortPause() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard wantsListening, !speaker.isSpeaking, cycle == nil else { return }
            do {
                try beginCycle()
            } catch {
                stop()
                status = "Voice control interrupted. Use the step buttons."
            }
        }
    }

    func readAloud(_ text: String) {
        guard wantsListening, !text.isEmpty else { return }
        endCycle()
        isListening = true
        status = ""
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speaker.speak(utterance)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            if wantsListening { resumeAfterShortPause() }
        }
    }

    func stop() {
        wantsListening = false
        isListening = false
        endCycle()
        if speaker.isSpeaking { speaker.stopSpeaking(at: .immediate) }
        recognition = nil
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation)
        status = ""
    }
}
