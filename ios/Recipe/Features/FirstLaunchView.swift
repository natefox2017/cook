// Developer: gengyun
// Purpose: Implements first-launch onboarding, usage guidance, and optional Premium conversion.

import SwiftUI

struct FirstLaunchFlowView: View {
    static let completionKey = "recipe.onboarding.completed"

    @State private var step = 0
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                RecipeTheme.canvas.ignoresSafeArea()
                Group {
                    switch step {
                    case 0:
                        FirstLaunchWelcomePage()
                    case 1:
                        ScrollView {
                            GettingStartedGuideContent()
                                .padding(.horizontal, RecipeSpacing.pageInset)
                                .padding(.top, RecipeSpacing.xSmall)
                                .padding(.bottom, 28)
                        }
                    default:
                        ScrollView {
                            PremiumPaywallContent(
                                context: .onboarding,
                                onContinue: onComplete,
                                onManageSubscription: nil
                            )
                            .padding(.horizontal, RecipeSpacing.pageInset)
                            .padding(.vertical, 16)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if step < 2 {
                    VStack(spacing: RecipeSpacing.xSmall) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                step += 1
                            }
                        } label: {
                            Text(LocalizedStringKey(step == 0 ? "Get Started" : "See Plans"))
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("onboarding.primary")

                    }
                    .padding(.horizontal, RecipeSpacing.pageInset)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(.ultraThinMaterial)
                }
            }
            .toolbar {
                if step < 2 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip") { onComplete() }
                            .accessibilityIdentifier("onboarding.skip")
                    }
                }
            }
            .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
        }
        .tint(RecipeTheme.accent)
    }
}

private struct FirstLaunchWelcomePage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: RecipeSpacing.large) {
                Spacer(minLength: 18)

                ZStack {
                    Circle()
                        .fill(RecipeTheme.accent.opacity(0.12))
                        .frame(width: 116, height: 116)
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 50, weight: .light))
                        .foregroundStyle(RecipeTheme.accentForeground)
                }
                .accessibilityHidden(true)

                Text("Keep every recipe in one place")
                    .font(RecipeTheme.heading(.hero))
                    .multilineTextAlignment(.center)

                VStack(spacing: RecipeSpacing.small) {
                    FirstLaunchValueRow(icon: "link", title: "Save from anywhere")
                    FirstLaunchValueRow(icon: "checklist", title: "Cook without clutter")
                    FirstLaunchValueRow(icon: "calendar.badge.plus", title: "Plan and shop")
                }
            }
            .padding(.horizontal, RecipeSpacing.pageInset)
            .padding(.bottom, 30)
        }
    }
}

private struct FirstLaunchValueRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(RecipeTheme.accentForeground)
                .frame(width: 42, height: 42)
                .background(RecipeTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: RecipeSpacing.xxSmall) {
                Text(LocalizedStringKey(title))
                    .font(RecipeTheme.text(17, weight: .semibold, relativeTo: .headline))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GettingStartedGuideView: View {
    var body: some View {
        ScrollView {
            GettingStartedGuideContent()
                .padding(.horizontal, RecipeSpacing.pageInset)
                .padding(.vertical, RecipeSpacing.medium)
        }
        .background(RecipeTheme.canvas)
        .navigationTitle("Getting Started")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
    }
}

struct GettingStartedGuideContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: RecipeSpacing.medium) {
            Text("Save your first recipe")
                .font(RecipeTheme.heading(.hero))

            VStack(spacing: 0) {
                guideStep(
                    1, icon: "square.and.arrow.up",
                    title: "Share to RecipePouch",
                    detail: "Share a recipe from another app."
                )
                Divider().padding(.leading, 56)
                guideStep(
                    2, icon: "plus.circle",
                    title: "Use Add Recipe as fallback",
                    detail: "Paste a link or add a photo."
                )
                Divider().padding(.leading, 56)
                guideStep(
                    3, icon: "pencil.and.list.clipboard",
                    title: "Saved automatically",
                    detail: "Review any missing details."
                )
                Divider().padding(.leading, 56)
                guideStep(
                    4, icon: "fork.knife",
                    title: "Cook, plan, or shop",
                    detail: "Cook recipes or plan meals."
                )
            }
            .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private func guideStep(_ number: Int, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(RecipeTheme.accentForeground)
                .frame(width: 42, height: 42)
                .background(RecipeTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: RecipeSpacing.xxSmall) {
                HStack(spacing: 4) {
                    Text("\(number).")
                    Text(LocalizedStringKey(title))
                }
                .font(RecipeTheme.text(17, weight: .semibold, relativeTo: .headline))
                .lineLimit(1)

                Text(LocalizedStringKey(detail))
                    .font(RecipeTheme.text(14, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}
