// Developer: gengyun
// Purpose: Renders selected private recipes into a local A4 multipage PDF without remote images or private paths.

import Foundation
import RecipeCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Frozen `pdf_export` capability gate for the Recipe PDF exporter.
///
/// The first release ships in the `freeTest` stage with StoreKit routes disabled,
/// so `pdf_export` defaults to unavailable. A later commercial build injects a
/// provider that decodes the verified access contract. This seam adds no new
/// monetization framework.
@MainActor
enum RecipePDFExportEntitlement {
    /// Injectable seam returning the currently entitled capability set.
    static var entitledCapabilities: @Sendable () -> Set<RecipeCapability> = { [] }

    static var isEntitled: Bool {
        entitledCapabilities().contains(.pdfExport)
    }
}

enum RecipePDFExportError: LocalizedError {
    case noRecipes

    var errorDescription: String? {
        switch self {
        case .noRecipes:
            return "Select at least one recipe to export."
        }
    }
}

/// `FileDocument` for the system PDF exporter; holds only the rendered bytes.
struct RecipePDFExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Text-only A4 PDF renderer. Only user-visible recipe text is drawn; image bytes,
/// storage paths, identifiers and import records are never embedded. The system
/// font renders CJK glyphs and every long field paginates instead of truncating.
enum RecipePDFExportService {
    /// A4 portrait at 72 points per inch.
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    static let pageMargins = UIEdgeInsets(top: 56, left: 56, bottom: 56, right: 56)

    static func render(recipes: [Recipe]) throws -> Data {
        guard !recipes.isEmpty else {
            throw RecipePDFExportError.noRecipes
        }
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            for recipe in recipes {
                draw(recipe, in: context)
            }
        }
    }

    // MARK: - Drawing

    private static func draw(_ recipe: Recipe, in context: UIGraphicsPDFRendererContext) {
        let contentRect = CGRect(
            x: pageMargins.left,
            y: pageMargins.top,
            width: pageSize.width - pageMargins.left - pageMargins.right,
            height: pageSize.height - pageMargins.top - pageMargins.bottom
        )
        var writer = PDFPageWriter(context: context, contentRect: contentRect)

        // Each recipe begins on a fresh A4 page.
        writer.beginNewPage()

        writer.write(
            recipe.title,
            font: PDFFont.title,
            color: PDFColor.primary,
            lineBreakMode: .byWordWrapping
        )
        writer.skip(6)

        if !recipe.summary.isEmpty {
            writer.write(
                recipe.summary,
                font: PDFFont.body,
                color: PDFColor.primary,
                lineBreakMode: .byWordWrapping
            )
            writer.skip(8)
        }

        drawMetadata(recipe, writer: &writer)
        drawIngredients(recipe, writer: &writer)
        drawSteps(recipe, writer: &writer)

        if !recipe.notes.isEmpty {
            writer.sectionHeading("Notes")
            writer.write(
                recipe.notes,
                font: PDFFont.body,
                color: PDFColor.primary,
                lineBreakMode: .byWordWrapping
            )
        }

        drawSource(recipe, writer: &writer)
    }

    /// Draws only metadata that is present; unknown values are never invented.
    private static func drawMetadata(_ recipe: Recipe, writer: inout PDFPageWriter) {
        var parts: [String] = []
        let category = recipe.category.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !category.isEmpty {
            parts.append(category)
        }
        if let servings = recipe.servings {
            parts.append("Servings: \(servings)")
        }
        if let prep = recipe.prepMinutes {
            parts.append("Prep: \(prep) min")
        }
        if let cook = recipe.cookMinutes {
            parts.append("Cook: \(cook) min")
        }
        guard !parts.isEmpty else { return }

        writer.write(
            parts.joined(separator: " · "),
            font: PDFFont.meta,
            color: PDFColor.secondary,
            lineBreakMode: .byWordWrapping
        )
        writer.skip(12)
    }

    private static func drawIngredients(_ recipe: Recipe, writer: inout PDFPageWriter) {
        writer.sectionHeading("Ingredients")
        if recipe.ingredients.isEmpty {
            writer.write(
                "Not specified",
                font: PDFFont.body,
                color: PDFColor.secondary,
                lineBreakMode: .byWordWrapping
            )
            return
        }
        for ingredient in recipe.ingredients {
            // Preserve the original amount text verbatim; a blank amount is omitted.
            let name = ingredient.name
            let amount = ingredient.amountText
            let line = amount.isEmpty ? name : "\(amount) — \(name)"
            writer.write(
                "• \(line)",
                font: PDFFont.body,
                color: PDFColor.primary,
                lineBreakMode: .byWordWrapping
            )
            writer.skip(2)
        }
    }

    private static func drawSteps(_ recipe: Recipe, writer: inout PDFPageWriter) {
        writer.sectionHeading("Steps")
        if recipe.steps.isEmpty {
            writer.write(
                "Not specified",
                font: PDFFont.body,
                color: PDFColor.secondary,
                lineBreakMode: .byWordWrapping
            )
            return
        }
        for (index, step) in recipe.steps.enumerated() {
            let title = step.title.isEmpty ? "Step \(index + 1)" : step.title
            writer.write(
                "\(index + 1). \(title)",
                font: PDFFont.body,
                color: PDFColor.primary,
                lineBreakMode: .byWordWrapping
            )
            writer.skip(2)
            if !step.instruction.isEmpty {
                writer.write(
                    step.instruction,
                    font: PDFFont.body,
                    color: PDFColor.primary,
                    lineBreakMode: .byWordWrapping
                )
                writer.skip(2)
            }
            if let temperature = step.temperature, !temperature.text.isEmpty {
                writer.write(
                    "Temperature: \(temperature.text)",
                    font: PDFFont.meta,
                    color: PDFColor.secondary,
                    lineBreakMode: .byWordWrapping
                )
                writer.skip(2)
            }
            if !step.timers.isEmpty {
                let labels = step.timers.map { timer in
                    timer.label.isEmpty
                        ? "\(timer.durationSeconds)s"
                        : "\(timer.label): \(timer.durationSeconds)s"
                }
                writer.write(
                    "Timers: \(labels.joined(separator: ", "))",
                    font: PDFFont.meta,
                    color: PDFColor.secondary,
                    lineBreakMode: .byWordWrapping
                )
                writer.skip(2)
            }
            writer.skip(4)
        }
    }

    private static func drawSource(_ recipe: Recipe, writer: inout PDFPageWriter) {
        let name = recipe.sourceName.flatMap { $0.isEmpty ? nil : $0 }
        let url = recipe.sourceURL.flatMap { $0.isEmpty ? nil : $0 }
        let text = recipe.sourceText.flatMap { $0.isEmpty ? nil : $0 }
        guard name != nil || url != nil || text != nil else { return }

        writer.sectionHeading("Source")
        if let name {
            writer.write(
                name,
                font: PDFFont.body,
                color: PDFColor.primary,
                lineBreakMode: .byWordWrapping
            )
            writer.skip(2)
        }
        if let url {
            // Drawn as plain text only; a PDF has no clickable, executable link.
            writer.write(
                "Original URL: \(url)",
                font: PDFFont.meta,
                color: PDFColor.secondary,
                lineBreakMode: .byCharWrapping
            )
            writer.skip(2)
        }
        if let text {
            writer.sectionHeading("Original source text")
            writer.write(
                text,
                font: PDFFont.body,
                color: PDFColor.primary,
                lineBreakMode: .byWordWrapping
            )
        }
    }
}

private enum PDFFont {
    static let title = UIFont.systemFont(ofSize: 24, weight: .bold)
    static let heading = UIFont.systemFont(ofSize: 14, weight: .bold)
    static let body = UIFont.systemFont(ofSize: 11, weight: .regular)
    static let meta = UIFont.systemFont(ofSize: 10, weight: .regular)
}

private enum PDFColor {
    static let primary = UIColor.black
    static let secondary = UIColor(white: 0.35, alpha: 1)
}

/// Manages the vertical cursor and page breaks while drawing one recipe.
private struct PDFPageWriter {
    let context: UIGraphicsPDFRendererContext
    let contentRect: CGRect
    private var cursorY: CGFloat

    init(context: UIGraphicsPDFRendererContext, contentRect: CGRect) {
        self.context = context
        self.contentRect = contentRect
        self.cursorY = contentRect.minY
    }

    mutating func beginNewPage() {
        context.beginPage()
        cursorY = contentRect.minY
    }

    mutating func skip(_ points: CGFloat) {
        cursorY += points
    }

    mutating func sectionHeading(_ text: String) {
        skip(8)
        write(
            text,
            font: PDFFont.heading,
            color: PDFColor.primary,
            lineBreakMode: .byWordWrapping
        )
        skip(4)
    }

    /// Wrapped, paginated text drawing. Long text never truncates: when it no
    /// longer fits the current page it is split on a measured line boundary and
    /// continued on a fresh page.
    mutating func write(
        _ text: String,
        font: UIFont,
        color: UIColor,
        lineBreakMode: NSLineBreakMode
    ) {
        guard !text.isEmpty else { return }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = lineBreakMode
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]

        var remaining = text as NSString
        let minLineHeight = font.lineHeight

        while remaining.length > 0 {
            let available = contentRect.maxY - cursorY
            if available < minLineHeight {
                beginNewPage()
                continue
            }

            let totalHeight = remaining.boundingRect(
                with: CGSize(width: contentRect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            ).height

            // A one-point margin guarantees a measured line is never clipped by a
            // pixel-level mismatch between measurement and drawing.
            if totalHeight <= available - 1 {
                remaining.draw(
                    in: CGRect(
                        x: contentRect.minX,
                        y: cursorY,
                        width: contentRect.width,
                        height: available
                    ),
                    withAttributes: attributes
                )
                cursorY += ceil(totalHeight)
                return
            }

            // Find the longest prefix that fits the remaining vertical space.
            var lower = 1
            var upper = remaining.length
            var fit = 0
            while lower <= upper {
                let mid = (lower + upper) / 2
                let prefix = remaining.substring(with: NSRange(location: 0, length: mid))
                let height = (prefix as NSString).boundingRect(
                    with: CGSize(width: contentRect.width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                ).height
                if height <= available - 1 {
                    fit = mid
                    lower = mid + 1
                } else {
                    upper = mid - 1
                }
            }

            if fit == 0 {
                // A single character cannot fit; defensively start a fresh page.
                beginNewPage()
                continue
            }

            let prefix = remaining.substring(with: NSRange(location: 0, length: fit))
            prefix.draw(
                in: CGRect(
                    x: contentRect.minX,
                    y: cursorY,
                    width: contentRect.width,
                    height: available
                ),
                withAttributes: attributes
            )
            remaining = remaining.substring(from: fit) as NSString
            beginNewPage()
        }
    }
}
