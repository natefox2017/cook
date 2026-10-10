// Developer: gengyun
// Purpose: Defines Recipe Pals colors, typography, spacing, and shared UI helpers.

import RecipeCore
import SwiftUI
import UIKit

enum RecipeSpacing {
    static let xxSmall: CGFloat = 4
    static let xSmall: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let pageInset: CGFloat = 20
    static let pageTop: CGFloat = xSmall
    static let readingLine: CGFloat = 5
}

enum RecipeHeadingLevel {
    case hero
    case title
    case section
    case card
}

enum RecipeNavigation {
    static let rootTitleMode: NavigationBarItem.TitleDisplayMode = .large
    static let detailTitleMode: NavigationBarItem.TitleDisplayMode = .inline
}

// A scroll-aware final inset, not a hard-coded Tab Bar height. SwiftUI
// updates its safe area for each device, rotation and keyboard presentation.
private struct RecipeRootScrollClearance: ViewModifier {
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: RecipeSpacing.medium)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    func recipeRootScrollClearance() -> some View {
        modifier(RecipeRootScrollClearance())
    }

    // Use the same content start below the native navigation bar on scroll screens.
    func recipePageContentInsets(bottom: CGFloat = RecipeSpacing.large) -> some View {
        padding(.horizontal, RecipeSpacing.pageInset)
            .padding(.top, RecipeSpacing.pageTop)
            .padding(.bottom, bottom)
    }
}

enum RecipeTheme {
    static let accent = Color(red: 66.0 / 255, green: 168.0 / 255, blue: 90.0 / 255)
    static let accentForeground = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 66.0 / 255, green: 168.0 / 255, blue: 90.0 / 255, alpha: 1)
                : UIColor(red: 0.13, green: 0.42, blue: 0.26, alpha: 1)
        })
    static let canvas = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.075, green: 0.09, blue: 0.078, alpha: 1)
                : UIColor(red: 0.97, green: 0.965, blue: 0.943, alpha: 1)
        })
    static let card = Color(uiColor: .secondarySystemGroupedBackground)

    static func text(
        _ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body
    ) -> Font {
        .custom("Lora-Regular", size: size, relativeTo: style).weight(weight)
    }

    // Semantic levels keep headings consistent without constraining timer displays.
    static func heading(_ level: RecipeHeadingLevel) -> Font {
        switch level {
        case .hero: text(34, weight: .semibold, relativeTo: .largeTitle)
        case .title: text(28, weight: .semibold, relativeTo: .title)
        case .section: text(22, weight: .semibold, relativeTo: .title2)
        case .card: text(20, weight: .semibold, relativeTo: .title3)
        }
    }

    static func title(_ size: CGFloat = 32) -> Font {
        text(size, weight: .semibold, relativeTo: .title)
    }

    static func body(_ size: CGFloat = 17) -> Font {
        text(size, relativeTo: .body)
    }

    @MainActor
    static func installUIKitTypography() {
        guard let regular = UIFont(name: "Lora-Regular", size: 17) else { return }

        let navigation = UINavigationBar.appearance()
        navigation.prefersLargeTitles = true
        navigation.titleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: regular),
            .foregroundColor: UIColor.label,
        ]
        navigation.largeTitleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: regular.withSize(34)),
            .foregroundColor: UIColor.label,
        ]

        let tabItem = UITabBarItem.appearance()
        tabItem.setTitleTextAttributes(
            [.font: UIFontMetrics(forTextStyle: .caption2).scaledFont(for: regular.withSize(10))],
            for: .normal)
        tabItem.setTitleTextAttributes(
            [.font: UIFontMetrics(forTextStyle: .caption2).scaledFont(for: regular.withSize(10))],
            for: .selected)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RecipeTheme.text(17, weight: .semibold, relativeTo: .headline))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.white)
            .background(RecipeTheme.accent, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}


// Tiny native micro-interactions shared by the library and recipe detail.
// Animations are event-driven; no looping effects or timers run while scrolling.
enum RecipeInteractionFeedback {
    @MainActor
    static func favorite(isFavorite: Bool) {
        UIImpactFeedbackGenerator(style: isFavorite ? .soft : .light).impactOccurred()
    }

    @MainActor
    static func action() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

private struct FavoriteBurstFrame {
    // Invisible at rest. Each successful save resets the keyframes to the center.
    var reach: CGFloat = 1
    var opacity: CGFloat = 0
}

struct RecipeFavoriteArtwork: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isFavorite: Bool
    var symbolSize: CGFloat = 20

    @State private var celebrationCount = 0

    var body: some View {
        ZStack {
            if !reduceMotion {
                Color.clear
                    .keyframeAnimator(
                        initialValue: FavoriteBurstFrame(),
                        trigger: celebrationCount
                    ) { _, frame in
                        particles(reach: frame.reach, opacity: frame.opacity)
                    } keyframes: {
                        KeyframeTrack(\.reach) {
                            LinearKeyframe(0, duration: 0.01)
                            CubicKeyframe(1, duration: 0.44)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(1, duration: 0.01)
                            LinearKeyframe(0.85, duration: 0.14)
                            LinearKeyframe(0, duration: 0.30)
                        }
                    }
                    .allowsHitTesting(false)
            }

            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(RecipeTheme.accentForeground)
                .contentTransition(
                    reduceMotion ? .identity : .symbolEffect(.replace)
                )
                .symbolEffect(.bounce, value: isFavorite && !reduceMotion)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.31, dampingFraction: 0.67),
                    value: isFavorite
                )
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
        .onChange(of: isFavorite) { previous, current in
            // A leaf-and-sparkle burst celebrates saving, not opening a saved recipe.
            if current && !previous && !reduceMotion {
                celebrationCount += 1
            }
        }
    }

    private func particles(reach: CGFloat, opacity: CGFloat) -> some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                let angle = Double(index) * .pi / 4
                let isLeaf = index.isMultiple(of: 2)

                Image(systemName: isLeaf ? "leaf.fill" : "sparkle")
                    .font(.system(size: isLeaf ? 7 : 6, weight: .semibold))
                    .foregroundStyle(
                        isLeaf
                            ? RecipeTheme.accentForeground
                            : RecipeTheme.accent
                    )
                    .offset(
                        x: CGFloat(cos(angle)) * 20 * reach,
                        y: CGFloat(sin(angle)) * 20 * reach
                    )
            }
        }
        .opacity(opacity)
        .accessibilityHidden(true)
    }
}

/// Scoped to recipe-detail calls to action so existing app-wide buttons retain
/// their approved appearance. The short spring tracks the finger while pressing.
struct RecipeDetailActionButtonStyle: ButtonStyle {
    enum Variant {
        case primary
        case secondary
    }

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let variant: Variant

    func makeBody(configuration: Configuration) -> some View {
        let isPrimary = variant == .primary

        configuration.label
            .font(
                RecipeTheme.text(
                    isPrimary ? 17 : 15,
                    weight: .semibold,
                    relativeTo: isPrimary ? .headline : .subheadline
                )
            )
            .frame(
                maxWidth: isPrimary ? .infinity : nil,
                minHeight: isPrimary ? 52 : 44
            )
            .padding(.horizontal, isPrimary ? 0 : 16)
            .foregroundStyle(
                isPrimary ? Color.white : RecipeTheme.accentForeground
            )
            .background {
                Capsule()
                    .fill(
                        isPrimary
                            ? RecipeTheme.accent
                            : RecipeTheme.accent.opacity(0.10)
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                isPrimary
                                    ? Color.white.opacity(0.22)
                                    : RecipeTheme.accent.opacity(0.23),
                                lineWidth: 1
                            )
                    }
            }
            .shadow(
                color: RecipeTheme.accent.opacity(
                    isPrimary && isEnabled ? (configuration.isPressed ? 0.08 : 0.18) : 0
                ),
                radius: configuration.isPressed ? 3 : 9,
                y: configuration.isPressed ? 1 : 4
            )
            .scaleEffect(
                reduceMotion || !isEnabled ? 1 : (configuration.isPressed ? 0.967 : 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.94 : 1) : 0.45)
            .animation(
                reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.64),
                value: configuration.isPressed
            )
    }
}

struct EmptyStateView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var messageLineLimit: Int? = 1

    var body: some View {
        VStack(spacing: RecipeSpacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(RecipeTheme.accentForeground)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(title))
                .font(RecipeTheme.heading(.title))
                .multilineTextAlignment(.center)
            Text(LocalizedStringKey(message))
                .font(RecipeTheme.text(15, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : messageLineLimit)
            if let actionTitle, let action {
                Button(action: action) { Text(LocalizedStringKey(actionTitle)) }.buttonStyle(
                    PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, RecipeSpacing.large)
        .padding(.bottom, RecipeSpacing.large)
        .frame(maxWidth: .infinity)
    }
}

struct RecipeImage: View {
    let recipe: Recipe
    var height: CGFloat = 180

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let data = recipe.coverData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let name = recipe.coverAsset, let image = samplePhoto(name) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        RecipeTheme.accent.opacity(0.09)
                        Image(systemName: "fork.knife")
                            .font(.system(size: 35, weight: .light))
                            .foregroundStyle(RecipeTheme.accentForeground)
                    }
                }
            }
            .frame(width: proxy.size.width, height: height)
            .clipped()
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    // Reuses food photography from the user's existing design reference. Only
    // the photo region is drawn; the complete mockup is never displayed as UI.
    private func samplePhoto(_ name: String) -> UIImage? {
        if name == "pasta", let image = UIImage(named: "SamplePastaReference")?.cgImage,
            let crop = image.cropping(to: CGRect(x: 0, y: 145, width: 707, height: 325))
        {
            return UIImage(cgImage: crop)
        }
        guard let image = UIImage(named: "SampleRecipeSheet")?.cgImage else {
            return nil
        }
        let rect: CGRect
        switch name {
        case "pasta":
            rect = CGRect(x: 40, y: 630, width: 302, height: 132)
        case "salmon":
            rect = CGRect(x: 363, y: 630, width: 302, height: 132)
        case "salad":
            rect = CGRect(x: 40, y: 919, width: 302, height: 137)
        case "pancakes":
            rect = CGRect(x: 363, y: 919, width: 302, height: 137)
        case "chicken":
            rect = CGRect(x: 363, y: 1205, width: 302, height: 123)
        default:
            return nil
        }
        guard let crop = image.cropping(to: rect) else {
            return nil
        }
        return UIImage(cgImage: crop)
    }
}
