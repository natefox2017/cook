// Developer: gengyun
// Purpose: Receives recipe links, text, images, and PDFs from Share hosts.

import RecipeCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
            display(
                .failed(
                    String(
                        localized: LocalizedStringResource(
                            "The source app did not provide a readable link or text.",
                            locale: RecipeLanguage.active))))
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

        if let imageProvider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }) {
            readAttachment(imageProvider, type: .image)
            return
        }

        if let pdfProvider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
        }) {
            readAttachment(pdfProvider, type: .file)
            return
        }

        // Some host apps supply an attributed text item without a provider.
        if let content = items.compactMap({ $0.attributedContentText?.string })
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        {
            save(content, as: .text)
        } else {
            display(
                .failed(
                    String(
                        localized: LocalizedStringResource(
                            "Share a public recipe link, readable text, image, or PDF.",
                            locale: RecipeLanguage.active))
                ))
        }
    }

    private func readAttachment(
        _ provider: NSItemProvider,
        type: RecipeShareInputType
    ) {
        let identifier = type == .image ? UTType.image.identifier : UTType.pdf.identifier
        provider.loadDataRepresentation(forTypeIdentifier: identifier) {
            [weak self] data, error in
            let mimeType = provider.registeredTypeIdentifiers
                .compactMap { UTType($0)?.preferredMIMEType }
                .first { value in
                    type == .image
                        ? value.hasPrefix("image/")
                        : value == "application/pdf"
                }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let data, let mimeType else {
                    self.display(
                        .failed(
                            error?.localizedDescription
                                ?? String(
                                    localized: LocalizedStringResource(
                                        "This attachment type is not supported.",
                                        locale: RecipeLanguage.active))
                        ))
                    return
                }
                self.save(data, as: type, mimeType: mimeType)
            }
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
                    self.display(
                        .failed(
                            failure
                                ?? String(
                                    localized: LocalizedStringResource(
                                        "The shared item could not be read. Try copying the link or text.",
                                        locale: RecipeLanguage.active))
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

    private func save(
        _ data: Data,
        as type: RecipeShareInputType,
        mimeType: String
    ) {
        do {
            let inbox = try RecipeShareInbox.shared()
            try inbox.receiveFile(data, as: type, mimeType: mimeType)
            display(.saved)
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
                userInfo: [
                    NSLocalizedDescriptionKey: String(
                        localized: LocalizedStringResource(
                            "Share cancelled.", locale: RecipeLanguage.active))
                ]
            )
        )
    }
}
