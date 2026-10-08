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
    @Environment(\.locale) private var locale
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

                Text("RecipePouch Premium")
                    .font(RecipeTheme.title(34))
                    .multilineTextAlignment(.center)
            }


            switch subscriptions.state {
            case .loading:
                ProgressView("Checking App Store plans…")
                    .frame(minHeight: 72)

            case .trial, .active, .gracePeriod:
                activeSubscription

            case .free, .billingRetry, .expired, .revoked, .unavailable:
                availablePlans
            }

            legalFooter

            if context == .onboarding {
                Button(subscriptions.state.hasEntitlement ? "Continue" : "Continue with Free") {
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

    @ViewBuilder
    private var activeSubscription: some View {
        VStack(spacing: 14) {
            Label(activeStatusTitle, systemImage: "checkmark.seal.fill")
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
            if let statusMessage {
                Text(statusMessage)
                    .font(RecipeTheme.text(15, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            if subscriptions.products.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "storefront")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Premium plans aren’t available right now.")
                        .font(RecipeTheme.text(17, weight: .semibold, relativeTo: .headline))
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
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            if subscriptions.isTrialEligible(for: product),
                               let offer = product.subscription?.introductoryOffer {
                                Text("Start \(periodLabel(offer.period, count: offer.periodCount)) free, then \(priceLine(for: product)).")
                                    .font(RecipeTheme.text(14, weight: .semibold, relativeTo: .subheadline))
                                    .foregroundStyle(RecipeTheme.accentForeground)
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

    private func priceLine(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return product.displayPrice
        }
        return "\(product.displayPrice) / \(periodLabel(period))"
    }

    private var activeStatusTitle: String {
        switch subscriptions.state {
        case .trial:
            String(localized: "Free trial active")
        case .gracePeriod:
            String(localized: "Subscription in billing grace period")
        default:
            String(localized: "Subscription active")
        }
    }

    private var statusMessage: String? {
        switch subscriptions.state {
        case .billingRetry:
            String(localized: "There is a billing issue with your previous subscription. Premium access is not currently active.")
        case .expired:
            String(localized: "Your previous subscription has expired. Your saved recipes remain available.")
        case .revoked:
            String(localized: "The App Store revoked your previous subscription. Your saved recipes remain available.")
        case .unavailable(let reason):
            reason
        default:
            nil
        }
    }

    private func periodLabel(_ period: Product.SubscriptionPeriod, count: Int) -> String {
        switch period.unit {
        case .day:
            return String(localized: LocalizedStringResource("\(count) day", locale: locale))
        case .week:
            return String(localized: LocalizedStringResource("\(count) week", locale: locale))
        case .month:
            return String(localized: LocalizedStringResource("\(count) month", locale: locale))
        case .year:
            return String(localized: LocalizedStringResource("\(count) year", locale: locale))
        @unknown default:
            return String(localized: "Subscription period")
        }
    }

    private func periodLabel(_ period: Product.SubscriptionPeriod) -> String {
        return switch period.unit {
        case .day:
            String(localized: LocalizedStringResource("\(period.value) day", locale: locale))
        case .week:
            String(localized: LocalizedStringResource("\(period.value) week", locale: locale))
        case .month:
            String(localized: LocalizedStringResource("\(period.value) month", locale: locale))
        case .year:
            String(localized: LocalizedStringResource("\(period.value) year", locale: locale))
        @unknown default:
            String(localized: "Subscription period")
        }
    }
}
