import SwiftUI
import UIKit
import CookCore

enum CookSpacing {
    static let xSmall: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let pageInset: CGFloat = 20
}

enum CookTheme {
    static let accent = Color(red: 66.0 / 255, green: 168.0 / 255, blue: 90.0 / 255)
    static let accentForeground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 66.0 / 255, green: 168.0 / 255, blue: 90.0 / 255, alpha: 1)
            : UIColor(red: 0.13, green: 0.42, blue: 0.26, alpha: 1)
    })
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.09, blue: 0.078, alpha: 1)
            : UIColor(red: 0.97, green: 0.965, blue: 0.943, alpha: 1)
    })
    static let card = Color(uiColor: .secondarySystemGroupedBackground)

    static func text(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Lora-Regular", size: size, relativeTo: style).weight(weight)
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
        navigation.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: regular)]
        navigation.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: regular.withSize(34))]

        let tabItem = UITabBarItem.appearance()
        tabItem.setTitleTextAttributes([.font: UIFontMetrics(forTextStyle: .caption2).scaledFont(for: regular.withSize(10))], for: .normal)
        tabItem.setTitleTextAttributes([.font: UIFontMetrics(forTextStyle: .caption2).scaledFont(for: regular.withSize(10))], for: .selected)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CookTheme.text(18, weight: .semibold, relativeTo: .headline))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.white)
            .background(CookTheme.accent, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: CookSpacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(CookTheme.accentForeground)
                .accessibilityHidden(true)
            Text(title).font(CookTheme.title(27)).multilineTextAlignment(.center)
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, CookSpacing.large)
        .padding(.bottom, CookSpacing.large)
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
                        CookTheme.accent.opacity(0.09)
                        Image(systemName: "fork.knife")
                            .font(.system(size: 35, weight: .light))
                            .foregroundStyle(CookTheme.accentForeground)
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
           let crop = image.cropping(to: CGRect(x: 0, y: 145, width: 707, height: 325)) {
            return UIImage(cgImage: crop)
        }
        guard let image = UIImage(named: "SampleRecipeSheet")?.cgImage else { return nil }
        let rect: CGRect
        switch name {
        case "pasta": rect = CGRect(x: 40, y: 630, width: 302, height: 132)
        case "salmon": rect = CGRect(x: 363, y: 630, width: 302, height: 132)
        case "salad": rect = CGRect(x: 40, y: 919, width: 302, height: 137)
        case "pancakes": rect = CGRect(x: 363, y: 919, width: 302, height: 137)
        default: return nil
        }
        guard let crop = image.cropping(to: rect) else { return nil }
        return UIImage(cgImage: crop)
    }
}
