// Developer: gengyun
// Purpose: Implements RecipePouch subscription status, purchase, restore, and management UI.

import Foundation
import StoreKit
import SwiftUI

enum PremiumPaywallContext {
    case onboarding
    case settings
}

struct SubscriptionView: View {
    @Environment(SubscriptionStore.self) private var subscriptions
    @State private var isManagingSubscriptions = false

    var body: some View {
        ScrollView {
            PremiumPaywallContent(
                context: .settings,
                onContinue: nil,
                onManageSubscription: { isManagingSubscriptions = true }
            )
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .background(RecipeTheme.canvas)
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .manageSubscriptionsSheet(isPresented: $isManagingSubscriptions)
    }
}

struct PremiumPaywallContent: View {
    @Environment(SubscriptionStore.self) private var subscriptions

    let context: PremiumPaywallContext
    let onContinue: (() -> Void)?
    let onManageSubscription: (() -> Void)?

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 62))
                    .foregroundStyle(RecipeTheme.accentForeground)
                    .accessibilityHidden(true)

                Text("Recipe Premium")
                    .font(RecipeTheme.title(34))
                    .multilineTextAlignment(.center)

                Text(context == .onboarding
                     ? "Choose a plan if Premium fits your kitchen. You can also continue with the free app."
                     : "Your App Store plan and purchase status live here.")
                    .font(RecipeTheme.body())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            premiumValueSummary

            switch subscriptions.state {
            case .loading:
                ProgressView("Checking App Store plans…")
                    .frame(minHeight: 72)

            case .active:
                activeSubscription

            case .free, .unavailable:
                availablePlans
            }

            legalFooter

            if context == .onboarding {
                Button(subscriptions.state == .active ? "Continue" : "Continue with Free") {
                    onContinue?()
                }
                .frame(minHeight: 50)
                .accessibilityIdentifier("onboarding.continueFree")
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .task { await subscriptions.load() }
        .alert(
            "Subscription",
            isPresented: Binding(
                get: { subscriptions.message != nil },
                set: { if !$0 { subscriptions.message = nil } }
            )
        ) {
            Button("OK", role: .cancel) { subscriptions.message = nil }
        } message: {
            Text(subscriptions.message ?? "")
        }
    }

    private var premiumValueSummary: some View {
        VStack(spacing: 0) {
            premiumRow(
                icon: "sparkles",
                title: "Plans come from the App Store",
                detail: "Names, descriptions, prices, and billing periods are loaded from your current storefront."
            )
            Divider().padding(.leading, 54)
            premiumRow(
                icon: "lock.shield",
                title: "No locked-in recipe data",
                detail: "Your saved recipes stay readable even if Premium is not active."
            )
            Divider().padding(.leading, 54)
            premiumRow(
                icon: "arrow.clockwise",
                title: "Restore anytime",
                detail: "Already subscribed with this App Store account? Restore Purchases checks the verified entitlement."
            )
        }
        .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private var activeSubscription: some View {
        VStack(spacing: 14) {
            Label("Subscription active", systemImage: "checkmark.seal.fill")
                .font(RecipeTheme.text(17, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(RecipeTheme.accentForeground)

            if let onManageSubscription {
                Button("Manage Subscription", action: onManageSubscription)
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private var availablePlans: some View {
        VStack(spacing: 12) {
            if subscriptions.products.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "storefront")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Premium plans aren’t available right now.")
                        .font(RecipeTheme.text(17, weight: .semibold, relativeTo: .headline))
                    Text("You can keep using Recipe for free and check again later.")
                        .font(RecipeTheme.text(15, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 22))

                Button("Try Again") {
                    Task { await subscriptions.load(force: true) }
                }
                .buttonStyle(.bordered)
                .disabled(subscriptions.isWorking)
                .accessibilityIdentifier("subscription.retry")
            } else {
                ForEach(subscriptions.products, id: \.id) { product in
                    Button {
                        Task { await subscriptions.purchase(product) }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(product.displayName)
                                    .font(RecipeTheme.text(18, weight: .semibold, relativeTo: .headline))
                                Spacer()
                                Text(priceLine(for: product))
                                    .font(RecipeTheme.text(16, weight: .semibold, relativeTo: .subheadline))
                            }

                            if !product.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(product.description)
                                    .font(RecipeTheme.text(14, relativeTo: .subheadline))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(RecipeTheme.accent.opacity(0.28))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(subscriptions.isWorking)
                    .accessibilityIdentifier("subscription.plan.\(product.id)")
                }
            }

            Button("Restore Purchases") {
                Task { await subscriptions.restore() }
            }
            .frame(minHeight: 44)
            .disabled(subscriptions.isWorking)
            .accessibilityIdentifier("subscription.restore")

            if subscriptions.isWorking {
                ProgressView()
                    .accessibilityLabel("Working with the App Store")
            }
        }
    }

    private var legalFooter: some View {
        VStack(spacing: 10) {
            Text("App Store subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Billing and cancellation are managed by Apple.")
                .font(RecipeTheme.text(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 18) {
                Link(
                    "Terms of Use",
                    destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
                )
                NavigationLink("Privacy") {
                    PrivacySummaryView()
                }
            }
            .font(RecipeTheme.text(13, weight: .semibold, relativeTo: .footnote))
        }
    }

    private func premiumRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(RecipeTheme.accentForeground)
                .frame(width: 38, height: 38)
                .background(RecipeTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(RecipeTheme.text(16, weight: .semibold, relativeTo: .headline))
                Text(detail)
                    .font(RecipeTheme.text(14, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private func priceLine(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return product.displayPrice
        }
        return "\(product.displayPrice) / \(periodLabel(period))"
    }

    private func periodLabel(_ period: Product.SubscriptionPeriod) -> String {
        let singular: String
        let plural: String

        switch period.unit {
        case .day:
            singular = "day"; plural = "days"
        case .week:
            singular = "week"; plural = "weeks"
        case .month:
            singular = "month"; plural = "months"
        case .year:
            singular = "year"; plural = "years"
        @unknown default:
            return "period"
        }

        return period.value == 1 ? singular : "\(period.value) \(plural)"
    }
}
