import SwiftUI
import UIKit

enum CookTheme {
    static let green = Color(red: 0.13, green: 0.40, blue: 0.27)
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.secondarySystemBackground :
        UIColor(red: 0.98, green: 0.975, blue: 0.955, alpha: 1)
    })
    // Claude's proprietary font files are not bundled. System serif is a licensed native fallback.
    static func heading(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .serif, weight: .semibold)
    }
}

struct CookActionStyle: ViewModifier {
    var prominent = true
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent).tint(CookTheme.green) }
            else { content.buttonStyle(.glass).tint(CookTheme.green) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent).tint(CookTheme.green) }
            else { content.buttonStyle(.bordered).tint(CookTheme.green) }
        }
    }
}

extension View {
    func cookAction(prominent: Bool = true) -> some View { modifier(CookActionStyle(prominent: prominent)) }
}

struct RecipeCover: View {
    var data: Data?
    var height: CGFloat = 150
    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    CookTheme.paper
                    Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                }
                .accessibilityLabel("No recipe photo")
            }
        }
        .frame(maxWidth: .infinity).frame(height: height).clipped()
    }
}

struct InlineFailure: View {
    var message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.callout).foregroundStyle(.red).accessibilityAddTraits(.isStaticText)
    }
}
