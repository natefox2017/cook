// Developer: gengyun
// Purpose: Defines RecipePouch colors, typography, spacing, and shared UI helpers.

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
