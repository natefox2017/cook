// Developer: gengyun
// Purpose: Implements RecipePouch subscription status, purchase, restore, and management UI.

import Foundation
import RecipeCore
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
                onManageSubscription: {
                    isManagingSubscriptions = true
                }
            )
            .recipePageContentInsets(bottom: RecipeSpacing.medium)
        }
        .background(RecipeTheme.canvas)
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(RecipeNavigation.detailTitleMode)
        .toolbar(.hidden, for: .tabBar)
        .manageSubscriptionsSheet(isPresented: $isManagingSubscriptions)
    }
}

struct PremiumPaywallContent: View {
    @Environment(\.locale) private var locale
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedPeriod: SubscriptionBillingPeriod? = .yearly

    let context: PremiumPaywallContext
    let onContinue: (() -> Void)?
    let onManageSubscription: (() -> Void)?

    var body: some View {
        Group {
            if context == .onboarding {
                onboardingPaywall
            } else {
                settingsPaywall
            }
        }
        .task {
            await subscriptions.load()
        }
        .alert(
            "Subscription",
            isPresented: Binding(
                get: {
                    subscriptions.message != nil
                },
                set: { isPresented in
                    if !isPresented {
                        subscriptions.message = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                subscriptions.message = nil
            }
        } message: {
            Text(subscriptions.message ?? "")
        }
    }

    private var settingsPaywall: some View {
        VStack(alignment: .leading, spacing: RecipeSpacing.medium) {
            premiumHero
            premiumFeatures

            switch subscriptions.state {
            case .loading:
                ProgressView("Checking App Store plans…")
                    .frame(maxWidth: .infinity, minHeight: 72)

            case .trial, .active, .gracePeriod:
                activeSubscription

            case .free, .billingRetry, .expired, .revoked, .unavailable:
                planPicker
            }

            if !subscriptions.state.hasEntitlement {
                freePlanChoice
            }
            legalFooter
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    private var onboardingPaywall: some View {
        GeometryReader { geometry in
            ScrollView {
                onboardingContent(imageHeight: min(160, max(120, geometry.size.height * 0.19)))
                    .padding(.horizontal, RecipeSpacing.pageInset)
                    .padding(.top, RecipeSpacing.pageTop)
                    .padding(.bottom, RecipeSpacing.large)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(RecipeTheme.canvas.ignoresSafeArea())
    }

    private func onboardingContent(imageHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: RecipeSpacing.medium) {
            HStack {
                Text("RecipePouch Premium")
                    .font(RecipeTheme.heading(.card))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Button {
                    onContinue?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
                .accessibilityIdentifier("onboarding.close")
            }

            Image("OnboardingAI")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 112 : imageHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityLabel(Text("A roast chicken dinner."))

            premiumFeatures

            if subscriptions.state.hasEntitlement {
                activeSubscription
            } else {
                planOptions
            }

            VStack(spacing: RecipeSpacing.small) {
                if !subscriptions.state.hasEntitlement, let selectedProduct {
                    if subscriptions.isTrialEligible(for: selectedProduct),
                        let offer = selectedProduct.subscription?.introductoryOffer
                    {
                        Text(
                            "Start \(periodLabel(offer.period, count: offer.periodCount)) free, then \(selectedProduct.displayPrice)."
                        )
                        .font(RecipeTheme.text(13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Auto-renews until canceled in the App Store.")
                        .font(RecipeTheme.text(13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: continueFromOnboardingPaywall) {
                    HStack(spacing: RecipeSpacing.xSmall) {
                        if subscriptions.isWorking {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(onboardingButtonTitle)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(
                    subscriptions.isWorking
                        || (!subscriptions.state.hasEntitlement && !isFreePlanSelected
                            && selectedProduct == nil)
                )
                .accessibilityIdentifier("onboarding.purchase")
            }

            if !subscriptions.state.hasEntitlement {
                freePlanChoice
            }

            legalFooter
        }
    }

    private var planOptions: some View {
        VStack(alignment: .leading, spacing: RecipeSpacing.small) {
            Text("Choose your plan")
                .font(RecipeTheme.heading(.card))

            paidPlanChoice(for: .monthly)
            paidPlanChoice(for: .yearly)

            if subscriptions.state == .loading {
                ProgressView("Checking App Store plans…")
            } else if eligibleProducts.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: RecipeSpacing.xSmall) {
                    Text("Premium plans aren’t available right now.")
                        .font(RecipeTheme.text(13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Try Again") {
                        Task {
                            await subscriptions.load(force: true)
                        }
                    }
                    .font(RecipeTheme.text(13, weight: .semibold, relativeTo: .footnote))
                    .frame(minHeight: 44)
                    .disabled(subscriptions.isWorking)
                    .accessibilityIdentifier("subscription.retry")
                }
            }
        }
    }

    private var isFreePlanSelected: Bool {
        selectedPeriod == nil
    }

    private var onboardingButtonTitle: LocalizedStringKey {
        if subscriptions.state.hasEntitlement {
            return "Continue"
        }
        if isFreePlanSelected {
            return "Continue with Free"
        }
        guard let selectedProduct else {
            return "Subscribe"
        }
        return subscriptions.isTrialEligible(for: selectedProduct)
            ? "Start Free Trial" : "Subscribe"
    }

    private var legalFooter: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: RecipeSpacing.xSmall))
            : AnyLayout(HStackLayout(spacing: RecipeSpacing.medium))

        return layout {
            Button("Restore Purchases") {
                Task {
                    await subscriptions.restore()
                }
            }
            .frame(minHeight: 44)
            .disabled(subscriptions.isWorking)
            .accessibilityIdentifier("subscription.restore")

            Link(
                "Terms",
                destination: URL(
                    string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
                )!
            )
            .frame(minHeight: 44)

            NavigationLink("Privacy") {
                PrivacySummaryView()
            }
            .frame(minHeight: 44)
        }
        .font(RecipeTheme.text(13, weight: .medium, relativeTo: .footnote))
        .foregroundStyle(RecipeTheme.accentForeground)
        .frame(maxWidth: .infinity)
    }

    private var premiumFeatures: some View {
        VStack(alignment: .leading, spacing: 10) {
            premiumFeature("bookmark", title: "Collect recipes on any plan")
            premiumFeature("link", title: "Links & social")
            premiumFeature("fork.knife", title: "Cook & plan")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, RecipeSpacing.xSmall)
    }

    private func premiumFeature(_ symbol: String, title: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: RecipeSpacing.small) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(RecipeTheme.accentForeground)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text(title)
                .font(RecipeTheme.text(15, weight: .medium, relativeTo: .subheadline))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func paidPlanChoice(for period: SubscriptionBillingPeriod) -> some View {
        let product = product(for: period)
        let isSelected = selectedPeriod == period

        return Button {
            selectedPeriod = period
        } label: {
            HStack(spacing: RecipeSpacing.small) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(
                        isSelected ? RecipeTheme.accentForeground : Color.secondary.opacity(0.5)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(period.title)
                        .font(RecipeTheme.text(17, weight: .semibold, relativeTo: .headline))
                    Text(period.billingCopy)
                        .font(RecipeTheme.text(13, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if dynamicTypeSize.isAccessibilitySize {
                        planPrice(product)
                    }
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: RecipeSpacing.small)
                    planPrice(product)
                }
            }
            .padding(RecipeSpacing.medium)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(
                isSelected ? RecipeTheme.accent.opacity(0.06) : RecipeTheme.card,
                in: RoundedRectangle(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        isSelected ? RecipeTheme.accent : Color.secondary.opacity(0.14),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(subscriptions.isWorking)
        .accessibilityIdentifier(
            product.map { product in
                "subscription.plan.\(product.id)"
            }
                ?? (period == .yearly
                    ? "subscription.plan.annual.unavailable"
                    : "subscription.plan.monthly.unavailable")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func planPrice(_ product: Product?) -> some View {
        if let product {
            Text(product.displayPrice)
                .font(RecipeTheme.text(20, weight: .semibold, relativeTo: .title3))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Unavailable")
                .font(RecipeTheme.text(13, relativeTo: .footnote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var freePlanChoice: some View {
        Button {
            selectedPeriod = nil
            if context == .onboarding {
                onContinue?()
            }
        } label: {
            Text("Continue with Free")
                .font(RecipeTheme.text(15, relativeTo: .subheadline))
                .foregroundStyle(RecipeTheme.accentForeground)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(subscriptions.isWorking)
        .accessibilityIdentifier(
            context == .onboarding ? "onboarding.plan.free" : "subscription.plan.free"
        )
        .accessibilityAddTraits(isFreePlanSelected ? .isSelected : [])
    }

    private func continueFromOnboardingPaywall() {
        if subscriptions.state.hasEntitlement {
            onContinue?()
        } else if let selectedProduct {
            Task {
                await subscriptions.purchase(selectedProduct)
            }
        } else if isFreePlanSelected {
            onContinue?()
        }
    }

    private var premiumHero: some View {
        VStack(alignment: .leading, spacing: RecipeSpacing.medium) {
            Text("RecipePouch Premium")
                .font(RecipeTheme.heading(.card))
            Image("OnboardingAI")
                .resizable()
                .scaledToFill()
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 112 : 160)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityLabel(Text("A roast chicken dinner."))
        }
    }

    @ViewBuilder
    private var activeSubscription: some View {
        VStack(spacing: RecipeSpacing.small) {
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
        .padding(RecipeSpacing.pageInset)
        .background(RecipeTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var planPicker: some View {
        VStack(alignment: .leading, spacing: RecipeSpacing.medium) {
            if let statusMessage {
                Text(statusMessage)
                    .font(RecipeTheme.text(15, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            planOptions

            if let selectedProduct {
                if subscriptions.isTrialEligible(for: selectedProduct),
                    let offer = selectedProduct.subscription?.introductoryOffer
                {
                    Text(
                        "Start \(periodLabel(offer.period, count: offer.periodCount)) free, then \(selectedProduct.displayPrice)."
                    )
                    .font(RecipeTheme.text(13, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Text("Auto-renews until canceled in the App Store.")
                    .font(RecipeTheme.text(13, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                guard let selectedProduct else {
                    return
                }
                Task {
                    await subscriptions.purchase(selectedProduct)
                }
            } label: {
                Text(purchaseButtonTitle)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selectedProduct == nil || subscriptions.isWorking)
            .accessibilityIdentifier("subscription.purchase")
        }
    }

    private var eligibleProducts: [Product] {
        subscriptions.products.filter {
            // Never label a multi-month product as the monthly plan.
            guard let period = $0.subscription?.subscriptionPeriod, period.value == 1 else {
                return false
            }
            return period.unit == .year || period.unit == .month
        }
    }

    private func product(for period: SubscriptionBillingPeriod) -> Product? {
        eligibleProducts.first {
            $0.subscription?.subscriptionPeriod.unit == period.storeKitUnit
        }
    }

    private var selectedProduct: Product? {
        guard let selectedPeriod else {
            return nil
        }
        return product(for: selectedPeriod)
    }

    private var purchaseButtonTitle: LocalizedStringKey {
        guard let selectedProduct else {
            return "Subscribe"
        }
        return subscriptions.isTrialEligible(for: selectedProduct)
            ? "Start Free Trial" : "Subscribe"
    }

    private var activeStatusTitle: String {
        switch subscriptions.state {
        case .trial:
            String(
                localized: LocalizedStringResource(
                    "Free trial active", locale: RecipeLanguage.active))
        case .gracePeriod:
            String(
                localized: LocalizedStringResource(
                    "Subscription in billing grace period", locale: RecipeLanguage.active))
        default:
            String(
                localized: LocalizedStringResource(
                    "Subscription active", locale: RecipeLanguage.active))
        }
    }

    private var statusMessage: String? {
        switch subscriptions.state {
        case .billingRetry:
            String(
                localized: LocalizedStringResource(
                    "Payment issue. Premium is inactive.", locale: RecipeLanguage.active))
        case .expired:
            String(
                localized: LocalizedStringResource(
                    "Subscription expired.", locale: RecipeLanguage.active))
        case .revoked:
            String(
                localized: LocalizedStringResource(
                    "Subscription revoked by App Store.", locale: RecipeLanguage.active))
        default:
            nil
        }
    }

    private func periodLabel(_ period: Product.SubscriptionPeriod, count: Int) -> String {
        let units = period.value * count
        switch period.unit {
        case .day:
            return String(localized: LocalizedStringResource("\(units) day", locale: locale))
        case .week:
            return String(localized: LocalizedStringResource("\(units) week", locale: locale))
        case .month:
            return String(localized: LocalizedStringResource("\(units) month", locale: locale))
        case .year:
            return String(localized: LocalizedStringResource("\(units) year", locale: locale))
        @unknown default:
            return String(
                localized: LocalizedStringResource(
                    "Subscription period", locale: RecipeLanguage.active))
        }
    }

}

private enum SubscriptionBillingPeriod: CaseIterable {
    case yearly
    case monthly

    var title: LocalizedStringKey {
        switch self {
        case .yearly:
            "Annual"
        case .monthly:
            "Monthly"
        }
    }

    var billingCopy: LocalizedStringKey {
        switch self {
        case .yearly:
            "Billed once a year."
        case .monthly:
            "Billed every month."
        }
    }

    var storeKitUnit: Product.SubscriptionPeriod.Unit {
        switch self {
        case .yearly:
            .year
        case .monthly:
            .month
        }
    }
}
