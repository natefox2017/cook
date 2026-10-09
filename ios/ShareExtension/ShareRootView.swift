// Developer: gengyun
// Purpose: Shows the short-lived native share receipt confirmation or a retryable error.

import RecipeCore
import SwiftUI

// The share extension has a separate bundle, so these values match RecipeTheme
// without importing the main app target.
private enum ShareVisualStyle {
    static let accent = Color(red: 66.0 / 255, green: 168.0 / 255, blue: 90.0 / 255)
    static let body = Font.custom("Lora-Regular", size: 17, relativeTo: .body)
    static let headline = Font.custom("Lora-Regular", size: 17, relativeTo: .headline)
        .weight(.semibold)
    static let footnote = Font.custom("Lora-Regular", size: 13, relativeTo: .footnote)
}

enum SharePresentationState {
    case receiving
    case saved
    case failed(String)
}

/// The Share host closes immediately after its durable receipt is saved.
/// Parsing/AI and cloud acknowledgements belong to the main app/backend.
struct ShareRootView: View {
    let state: SharePresentationState
    let retry: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            switch state {
            case .receiving:
                ProgressView()
                Text("Saving source…")
                    .font(ShareVisualStyle.headline)

            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(ShareVisualStyle.accent)
                Text("Saved on this iPhone")
                    .font(ShareVisualStyle.headline)

            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text("Couldn’t save your source")
                    .font(ShareVisualStyle.headline)
                Text(message)
                    // Errors are actionable information, unlike decorative helper copy.
                    .lineLimit(3)
                    .font(ShareVisualStyle.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button("Cancel", role: .cancel, action: cancel)
                        .buttonStyle(.bordered)
                    Button("Try Again", action: retry)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .font(ShareVisualStyle.body)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .environment(\.locale, RecipeLanguage.active)
    }
}
