import Foundation
import UIKit
import Vision
import PDFKit
import RecipeCore

enum RecipeImportError: LocalizedError {
    case invalidLink, unsupportedPage, tooLarge, textTooLong, unreadableImage, noText, network(Int)
    var errorDescription: String? {
        switch self {
        case .invalidLink: "Paste a public recipe link beginning with https://. Local addresses and sign-in details aren't supported."
        case .unsupportedPage: "This page doesn't contain a readable recipe. Your link can still be saved; add its text or a screenshot to complete it."
        case .tooLarge: "This file is too large. Choose a smaller image or a recipe document under 10 MB."
        case .textTooLong: "This recipe contains more than 100,000 characters. Choose a shorter document or paste a shorter section. Nothing was imported."
        case .unreadableImage: "Recipe couldn't read this image. Try another photo with the recipe clearly in view."
        case .noText: "No readable text was found. Try a clearer photo, paste the recipe text, or enter the details."
        case .network(let code): "The website couldn't be read (HTTP \(code)). You can keep the link and add the recipe details."
        }
    }
}

enum RecipeImportService {
    static func importWebpage(_ url: URL) async throws -> Recipe {
        guard RecipeDocumentParser.validatedSourceURL(url.absoluteString) != nil else { throw RecipeImportError.invalidLink }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration, delegate: RecipeRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw RecipeImportError.network((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard response.expectedContentLength <= 2_000_000 else { throw RecipeImportError.tooLarge }
        guard ["text/html", "application/xhtml+xml"].contains(response.mimeType ?? "") else { throw RecipeImportError.unsupportedPage }
        var data = Data()
        for try await byte in bytes {
            if data.count >= 2_000_000 { throw RecipeImportError.tooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        guard let recipe = RecipeDocumentParser.recipe(inHTML: html, sourceURL: url) else { throw RecipeImportError.unsupportedPage }
        return recipe
    }

    @MainActor
    static func normalizedPhoto(_ data: Data) throws -> Data {
        guard data.count <= 10_000_000 else { throw RecipeImportError.tooLarge }
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0,
              image.size.width * image.size.height <= 70_000_000 else { throw RecipeImportError.unreadableImage }
        let factor = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let resized = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let output = resized.jpegData(compressionQuality: 0.85) else { throw RecipeImportError.unreadableImage }
        return output
    }

    static func recognizeText(in data: Data) async throws -> String {
        let result = try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(data: data).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
        try Task.checkCancellation()
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RecipeImportError.noText }
        return result
    }

    static func text(fromFile url: URL) throws -> String {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 10_000_000 else { throw RecipeImportError.tooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= 10_000_000 else { throw RecipeImportError.tooLarge }
        let text: String
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(data: data), pdf.pageCount <= 50 else { throw RecipeImportError.tooLarge }
            text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        } else {
            text = String(data: data, encoding: .utf8) ?? ""
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RecipeImportError.noText }
        guard text.count <= RecipeDocumentParser.maximumTextCharacters else { throw RecipeImportError.textTooLong }
        return text
    }
}

private final class RecipeRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, RecipeDocumentParser.validatedSourceURL(url.absoluteString) != nil,
              task.countOfBytesReceived < 2_000_000 else { completionHandler(nil); return }
        completionHandler(request)
    }
}
