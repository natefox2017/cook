import SwiftUI

struct FirstLaunchFlowView: View {
    static let completionKey = "cook.onboarding.completed"

    @State private var step = 0
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                CookTheme.canvas.ignoresSafeArea()
                Group {
                    switch step {
                    case 0:
                        FirstLaunchWelcomePage()
                    case 1:
                        ScrollView {
                            GettingStartedGuideContent()
                                .padding(.horizontal, 22)
                                .padding(.top, 8)
                                .padding(.bottom, 28)
                        }
                    default:
                        ScrollView {
                            PremiumPaywallContent(
                                context: .onboarding,
                                onContinue: onComplete,
                                onManageSubscription: nil
                            )
                            .padding(.horizontal, 22)
                            .padding(.vertical, 16)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if step < 2 {
                    VStack(spacing: 10) {
                        Button(step == 0 ? "Get Started" : "See Plans") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                step += 1
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("onboarding.primary")

                        Text("\(step + 1) of 3")
                            .font(CookTheme.text(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(.ultraThinMaterial)
                }
            }
            .toolbar {
                if step < 2 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip") {\n                            withAnimation(.easeInOut(duration: 0.2)) { step = 2 }\n                        }
                            .accessibilityIdentifier("onboarding.skip")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(CookTheme.accent)
    }
}

private struct FirstLaunchWelcomePage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 18)

                ZStack {
                    Circle()
                        .fill(CookTheme.accent.opacity(0.12))
                        .frame(width: 116, height: 116)
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 50, weight: .light))
                        .foregroundStyle(CookTheme.accentForeground)
                }
                .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("Keep every recipe in one place")
                        .font(CookTheme.title(34))
                        .multilineTextAlignment(.center)
                    Text("Save recipes from links, photos, documents, or your own notes. Then cook, plan, and shop from the same library.")
                        .font(CookTheme.body())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 14) {
                    FirstLaunchValueRow(
                        icon: "link",
                        title: "Save from anywhere",
                        detail: "Paste a recipe link from the web or a social app."
                    )
                    FirstLaunchValueRow(
                        icon: "checklist",
                        title: "Cook without clutter",
                        detail: "Follow one step at a time and keep ingredient checks and timers together."
                    )
                    FirstLaunchValueRow(
                        icon: "calendar.badge.plus",
                        title: "Plan and shop",
                        detail: "Turn saved recipes into meal plans and grocery items."
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
    }
}

private struct FirstLaunchValueRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(CookTheme.accentForeground)
                .frame(width: 42, height: 42)
                .background(CookTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(CookTheme.text(17, weight: .semibold, relativeTo: .headline))
                Text(detail)
                    .font(CookTheme.text(15, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
        }
        .background(CookTheme.canvas)
        .navigationTitle("Getting Started")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GettingStartedGuideContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Save your first recipe")
                    .font(CookTheme.title(32))
                Text("The fastest path is a link. You can also use a photo, pasted text, a document, or create a recipe manually.")
                    .font(CookTheme.body())
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                guideStep(
                    1,
                    icon: "square.and.arrow.up",
                    title: "Copy a recipe link",
                    detail: "From Safari, TikTok, Instagram, YouTube, or another app, copy the recipe or post link. If Cook appears in the iOS share sheet, you can send the link directly to Cook."
                )
                Divider().padding(.leading, 56)
                guideStep(
                    2,
                    icon: "plus.circle",
                    title: "Open Add Recipe",
                    detail: "In Recipes, tap Add Recipe. Paste the link into “From a link,” then choose Import recipe."
                )
                Divider().padding(.leading, 56)
                guideStep(
                    3,
                    icon: "pencil.and.list.clipboard",
                    title: "Review before saving",
                    detail: "Cook keeps uncertain imports editable instead of inventing missing ingredients, quantities, or steps."
                )
                Divider().padding(.leading, 56)
                guideStep(
                    4,
                    icon: "fork.knife",
                    title: "Cook, plan, or shop",
                    detail: "Open the saved recipe to start cooking, add ingredients to Groceries, or place it on your Meal Plan."
                )
            }
            .background(CookTheme.card, in: RoundedRectangle(cornerRadius: 22))

            Text("Tip: private pages and social videos may not expose complete recipe text. Keep the source link and add text or screenshots when needed.")
                .font(CookTheme.text(13, relativeTo: .footnote))
                .foregroundStyle(.secondary)
        }
    }

    private func guideStep(_ number: Int, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(CookTheme.accent.opacity(0.09))
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(CookTheme.accentForeground)
            }
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(number). \(title)")
                    .font(CookTheme.text(17, weight: .semibold, relativeTo: .headline))
                Text(detail)
                    .font(CookTheme.text(15, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }
}
