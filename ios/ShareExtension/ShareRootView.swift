import SwiftUI
import UniformTypeIdentifiers

/// Share Extension UI: receive a URL/text payload, persist it to the App Group
/// inbox, then finish immediately. Parsing/AI belongs to the main app/backend.
struct ShareRootView: View {
    let payload: String
    let complete: () -> Void
    @State private var status = "Saving…"

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle").font(.system(size: 44))
            Text(status).font(.headline)
        }
        .padding()
        .task {
            do {
                try ShareInbox.save(payload)
                status = "Saved to Cook"
                try? await Task.sleep(for: .milliseconds(350))
                complete()
            } catch {
                status = "Couldn’t save to Cook"
            }
        }
    }
}

enum ShareInbox {
    static let suite = "group.com.modelhub.cook"
    static func save(_ payload: String) throws {
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.fileNoSuchFile) }
        var inbox = defaults.stringArray(forKey: "cook.shareInbox") ?? []
        if !inbox.contains(payload) { inbox.append(payload) }
        defaults.set(inbox, forKey: "cook.shareInbox")
    }
}
