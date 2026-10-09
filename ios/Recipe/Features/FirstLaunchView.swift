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
                        FirstLaunchStoryPage(
                            imageName: "OnboardingAI",
                            imageAccessibilityLabel:
                                "A finished lemon and herb roast chicken recipe.",
                            title: "Create with AI",
                            subtitle:
                                "Tell AI what you’re craving or list the ingredients you have. Start with a recipe idea.",
                            actionTitle: "Next",
                            page: 0,
                            onNext: advance,
                            onSkip: showPaywall
                        )
                    case 1:
                        FirstLaunchStoryPage(
                            imageName: "OnboardingShrimpPasta",
                            imageAccessibilityLabel: "A bowl of shrimp pasta saved as a recipe.",
                            title: "Save recipe links",
                            subtitle:
                                "Paste a recipe link to bring its ingredients and steps into your collection.",
                            actionTitle: "Next",
                            page: 1,
                            onNext: advance,
                            onSkip: showPaywall
                        )
                    case 2:
                        FirstLaunchStoryPage(
                            imageName: "OnboardingSocial",
                            imageAccessibilityLabel: "A cook sharing a recipe video from a phone.",
                            title: "Import social recipes",
                            subtitle:
                                "Share a recipe from Instagram, TikTok, or YouTube to save it.",
                            actionTitle: "See Plans",
                            page: 2,
                            onNext: advance,
                            onSkip: showPaywall
                        )
                    default:
                        PremiumPaywallContent(
                            context: .onboarding,
                            onContinue: onComplete,
                            onManageSubscription: nil
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(RecipeTheme.accent)
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.2)) {
            step += 1
        }
    }

    private func showPaywall() {
        withAnimation(.easeInOut(duration: 0.2)) {
            step = 3
        }
    }
}

private struct FirstLaunchStoryPage: View {
    let imageName: String
    let imageAccessibilityLabel: LocalizedStringKey
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    let page: Int
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                GeometryReader { imageGeometry in
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: imageGeometry.size.width,
                            height: imageGeometry.size.height
                        )
                        .clipped()
                        .overlay {
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0.32), location: 0),
                                    .init(color: .clear, location: 0.30),
                                    .init(color: .black.opacity(0.10), location: 0.48),
                                    .init(color: .black.opacity(0.84), location: 1),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .accessibilityLabel(Text(imageAccessibilityLabel))
                }
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .trailing, spacing: RecipeSpacing.small) {
                        Button("Skip", action: onSkip)
                            .font(RecipeTheme.text(15, weight: .semibold, relativeTo: .subheadline))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .background(.black.opacity(0.28), in: Capsule())
                            .accessibilityIdentifier("onboarding.skip")

                        pageProgress
                            .frame(maxWidth: .infinity)
                    }

                    Spacer(minLength: 24)

                    VStack(alignment: .leading, spacing: RecipeSpacing.small) {
                        Text(title)
                            .font(RecipeTheme.heading(.title))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.25), radius: 12, y: 2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(subtitle)
                            .font(RecipeTheme.body())
                            .foregroundStyle(.white.opacity(0.94))
                            .shadow(color: .black.opacity(0.4), radius: 8, y: 1)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(action: onNext) {
                            Text(actionTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, RecipeSpacing.small)
                        .accessibilityIdentifier("onboarding.primary")
                    }
                    .padding(.bottom, RecipeSpacing.small)
                }
                .padding(.horizontal, RecipeSpacing.pageInset)
                .padding(.top, max(8, geometry.safeAreaInsets.top))
                .padding(.bottom, max(12, geometry.safeAreaInsets.bottom))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.black)
        .preferredColorScheme(.dark)
    }

    private var pageProgress: some View {
        HStack(spacing: RecipeSpacing.xSmall) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(index <= page ? 1 : 0.38))
                    .frame(height: 3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Onboarding page \(page + 1) of 3"))
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

    private func guideStep(_ number: Int, icon: String, title: String, detail: String) -> some View
    {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(RecipeTheme.accentForeground)
                .frame(width: 42, height: 42)
                .background(
                    RecipeTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12)
                )
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
