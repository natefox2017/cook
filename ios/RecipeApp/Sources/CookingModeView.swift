// Developer: gengyun
// Purpose: Provides the legacy RecipeApp focused step-by-step cooking screen.

import SwiftUI
import UIKit

struct CookingModeView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("recipe.keepAwake") private var keepAwake = true

    let recipe: Recipe

    @State private var index = 0
    @State private var remaining = 0
    @State private var isRunning = false

    private let ticker = Timer.publish(
        every: 1,
        on: .main,
        in: .common
    ).autoconnect()

    private var step: RecipeStep {
        recipe.steps[index]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 26) {
                HStack {
                    Text("Step \(index + 1) of \(recipe.steps.count)")
                        .font(.headline)

                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                }

                ProgressView(
                    value: Double(index + 1),
                    total: Double(recipe.steps.count)
                )

                Spacer()

                Text(step.text)
                    .font(RecipeTheme.title(30))
                    .multilineTextAlignment(.center)

                if step.seconds != nil {
                    Text(clock)
                        .font(
                            .system(
                                size: 54,
                                weight: .medium,
                                design: .rounded
                            )
                            .monospacedDigit()
                        )

                    HStack {
                        Button(isRunning ? "Pause" : "Start") {
                            if remaining == 0 {
                                remaining = step.seconds ?? 0
                            }
                            isRunning.toggle()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Reset") {
                            isRunning = false
                            remaining = step.seconds ?? 0
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Spacer()

                HStack {
                    Button("Previous") {
                        move(by: -1)
                    }
                    .disabled(index == 0)

                    Spacer()

                    Button(
                        index == recipe.steps.count - 1
                            ? "Finish"
                            : "Next Step"
                    ) {
                        if index == recipe.steps.count - 1 {
                            dismiss()
                        } else {
                            move(by: 1)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .background(RecipeTheme.paper)
            .navigationBarBackButtonHidden()
        }
        .onAppear {
            remaining = step.seconds ?? 0
            if keepAwake {
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(ticker) { _ in
            guard isRunning, remaining > 0 else { return }
            remaining -= 1
            if remaining == 0 {
                isRunning = false
            }
        }
    }

    private var clock: String {
        String(
            format: "%02d:%02d",
            remaining / 60,
            remaining % 60
        )
    }

    private func move(by delta: Int) {
        index += delta
        isRunning = false
        remaining = step.seconds ?? 0
    }
}
