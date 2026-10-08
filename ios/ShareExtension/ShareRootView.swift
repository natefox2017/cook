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
        VStack(spacing: 16) {
            switch state {
            case .receiving:
                ProgressView()
                Text("Saving source…")
                    .font(.headline)

            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(Color(red: 66 / 255, green: 168 / 255, blue: 90 / 255))
                Text("Saved on this iPhone")
                    .font(.headline)

            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text("Couldn’t save your source")
                    .font(.headline)
                Text(message)
                    .lineLimit(1)
                    .font(.footnote)
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
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        // The share extension runs in its own process; pin its view locale too.
        .environment(\.locale, Locale(identifier: "en"))
    }
}
