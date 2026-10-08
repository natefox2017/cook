// Developer: gengyun
// Purpose: Receives URL/text from third-party Share hosts and durably stores a local receipt.

import RecipeCore
import UIKit
import UniformTypeIdentifiers
import SwiftUI

/// Share Extension entry point; it never contacts Supabase or waits for AI.
@MainActor
final class ShareViewController: UIViewController {
    private var hostedView: UIHostingController<ShareRootView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        installShareView()
        beginReceiving()
    }

    private func installShareView() {
        let host = UIHostingController(
            rootView: ShareRootView(
                state: .receiving,
                retry: { [weak self] in self?.beginReceiving() },
                cancel: { [weak self] in self?.cancelSharing() }
            )
        )
        hostedView = host
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }

    private func display(_ state: SharePresentationState) {
        hostedView?.rootView = ShareRootView(
            state: state,
            retry: { [weak self] in self?.beginReceiving() },
            cancel: { [weak self] in self?.cancelSharing() }
        )
    }

    private func beginReceiving() {
        display(.receiving)

        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            display(.failed("The source app did not provide a readable link or text."))
            return
        }

        let providers = items.flatMap { $0.attachments ?? [] }
        if let urlProvider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) {
            read(urlProvider, type: .url, identifier: UTType.url.identifier)
            return
        }

        if let textProvider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) {
            read(
                textProvider,
                type: .text,
                identifier: UTType.plainText.identifier
            )
            return
        }

        // Some host apps supply an attributed text item without a provider.
        if let content = items.compactMap({ $0.attributedContentText?.string })
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            save(content, as: .text)
        } else {
            display(.failed("Only public recipe links and readable text are supported right now."))
        }
    }

    private func read(
        _ provider: NSItemProvider,
        type: RecipeShareInputType,
        identifier: String
    ) {
        provider.loadItem(forTypeIdentifier: identifier, options: nil) {
            [weak self] item, error in

            // Item provider callbacks are not main-actor isolated. Copy only
            // Sendable values before returning to the UIKit controller.
            let source: String?
            if let url = item as? URL {
                source = url.absoluteString
            } else if let string = item as? String {
                source = string
            } else if let attributed = item as? NSAttributedString {
                source = attributed.string
            } else if let data = item as? Data {
                source = String(data: data, encoding: .utf8)
            } else {
                source = nil
            }
            let failure = error?.localizedDescription

            Task { @MainActor [weak self] in
                guard let self else { return }
                if let source, !source.isEmpty {
                    self.save(source, as: type)
                } else {
                    self.display(.failed(
                        failure ?? "The shared item could not be read. Try copying the link or text."
                    ))
                }
            }
        }
    }

    private func save(_ source: String, as type: RecipeShareInputType) {
        do {
            let inbox = try RecipeShareInbox.shared()
            try inbox.receive(source, as: type)
            display(.saved)
            // Local storage was committed. Do not claim backend queue or
            // parsed-recipe success. Return promptly to Safari/Notes/etc.
            extensionContext?.completeRequest(
                returningItems: [],
                completionHandler: nil
            )
        } catch {
            display(.failed(error.localizedDescription))
        }
    }

    private func cancelSharing() {
        extensionContext?.cancelRequest(
            withError: NSError(
                domain: "RecipePouch.ShareExtension",
                code: NSUserCancelledError,
                userInfo: [NSLocalizedDescriptionKey: "Share cancelled."]
            )
        )
    }
}
