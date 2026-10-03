import SwiftUI
import UIKit

struct CookingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var recipe: RecipeRecord
    @State private var index = 0
    @State private var timers: [UUID: CookingTimer] = [:]
    @State private var showingIngredients = false
    @State private var priorIdleSetting = false

    private var step: StepRecord { recipe.steps[index] }
    private var currentTimer: CookingTimer? { timers[step.id] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(recipe.title).font(CookTheme.heading(.title2))
                Text("Step \(index + 1) of \(recipe.steps.count)").foregroundStyle(.secondary)
                Text(step.instruction).font(.title2).fixedSize(horizontal: false, vertical: true)
                Button("View all ingredients", systemImage: "list.bullet") { showingIngredients = true }
                    .cookAction(prominent: false)
                if let seconds = step.durationSeconds, seconds > 0 {
                    timerControls(seconds: seconds)
                }
                HStack {
                    Button("Previous", systemImage: "arrow.left") { index -= 1 }
                        .cookAction(prominent: false).disabled(index == 0)
                    Spacer()
                    if index < recipe.steps.count - 1 {
                        Button("Next step", systemImage: "arrow.right") { index += 1 }.cookAction()
                    } else {
                        Button("Done cooking", systemImage: "checkmark") { dismiss() }.cookAction()
                    }
                }
                Text("Timers stay with their steps. A finished timer won't move you to the next step.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }
        .background(CookTheme.paper)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .sheet(isPresented: $showingIngredients) {
            NavigationStack {
                List(recipe.ingredients) { ingredient in
                    HStack {
                        Text(ingredient.name)
                        Spacer()
                        Text(ingredient.displayedAmount(for: recipe.servings ?? 1, originalServings: recipe.servings))
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Ingredients")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingIngredients = false } } }
            }
        }
        .onAppear {
            priorIdleSetting = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            for step in recipe.steps {
                if timers[step.id] == nil, let seconds = step.durationSeconds, seconds > 0 { timers[step.id] = CookingTimer(seconds: seconds) }
            }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = priorIdleSetting }
        .onChange(of: scenePhase) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = phase == .active ? true : priorIdleSetting
            refreshTimers()
        }
        .task {
            while !Task.isCancelled {
                refreshTimers()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    @ViewBuilder private func timerControls(seconds: Int) -> some View {
        if let timer = currentTimer {
            VStack(alignment: .leading, spacing: 16) {
                Text("Step timer").font(.headline)
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let remaining = Int(ceil(timer.remaining(at: context.date)))
                    Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                        .font(.system(.largeTitle, design: .serif)).monospacedDigit()
                        .accessibilityLabel("\(remaining / 60) minutes and \(remaining % 60) seconds remaining")
                }
                if timer.finished { Text("Time's up").font(.headline).foregroundStyle(CookTheme.green) }
                HStack {
                    if timer.running {
                        Button("Pause", systemImage: "pause") { timers[step.id]?.pause(at: .now) }.cookAction()
                    } else {
                        Button(timer.finished ? String(localized: "Start again") : (timer.pausedRemaining == timer.duration ? String(localized: "Start timer") : String(localized: "Resume")),
                               systemImage: "play") { timers[step.id]?.start(at: .now) }.cookAction()
                    }
                    Button("Reset", systemImage: "arrow.counterclockwise") { timers[step.id]?.reset() }
                        .cookAction(prominent: false)
                }
            }
            Text("Keep Cook open for timer feedback. Background notifications aren't enabled.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func refreshTimers() {
        for id in Array(timers.keys) { timers[id]?.tick(at: .now) }
    }
}
