// Developer: gengyun
// Purpose: Shows the short-lived native share receipt confirmation or a retryable error.

import SwiftUI

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
        VStack(spacing: 18) {
            switch state {
            case .receiving:
                ProgressView()
                Text("Saving source…")
                    .font(.headline)

            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.green)
                Text("Saved on this iPhone")
                    .font(.headline)
                Text("Your recipe will be processed when RecipePouch can connect.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text("Couldn’t save your source")
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 14) {
                    Button("Cancel", role: .cancel, action: cancel)
                        .buttonStyle(.bordered)
                    Button("Try Again", action: retry)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}
