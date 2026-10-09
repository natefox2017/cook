// Purpose: Render an authorized public recipe summary as a social poster with scannable QR.
import CoreImage.CIFilterBuiltins
import RecipeCore
import SwiftUI
import UIKit

enum RecipePosterFormat {
    case story
    case long
    var height: CGFloat { self == .story ? 1920 : 2400 }
}

enum RecipePosterError: Error {
    case invalidURL
    case unlicensedImage
    case qrUnavailable
    case renderFailed
}

/// Not surfaced to users until the real public Web URL and revoke API exist.
@MainActor
enum RecipeSharePosterRenderer {
    static func render(
        snapshot: PublicRecipeSnapshot, url: URL,
        format: RecipePosterFormat, licensedPhoto: UIImage? = nil,
        photoRightsConfirmed: Bool = false
    ) throws -> UIImage {
        guard RecipePublicShareURL.isValid(url) else { throw RecipePosterError.invalidURL }
        guard licensedPhoto == nil || photoRightsConfirmed else {
            throw RecipePosterError.unlicensedImage
        }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "H"
        guard let qrImage = filter.outputImage,
            let cg = CIContext().createCGImage(
                qrImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
                from: qrImage.extent.applying(CGAffineTransform(scaleX: 10, y: 10)))
        else { throw RecipePosterError.qrUnavailable }

        let content = RecipePosterView(
            snapshot: snapshot, url: url, format: format,
            qr: UIImage(cgImage: cg), licensedPhoto: licensedPhoto)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        guard let image = renderer.uiImage else { throw RecipePosterError.renderFailed }
        return image
    }
}

private struct RecipePosterView: View {
    let snapshot: PublicRecipeSnapshot
    let url: URL
    let format: RecipePosterFormat
    let qr: UIImage
    let licensedPhoto: UIImage?

    private let green = Color(red: 0.12, green: 0.40, blue: 0.25)
    private let ink = Color(red: 0.13, green: 0.23, blue: 0.17)

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Label("RECIPE PALS", systemImage: "leaf.fill")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .tracking(5).foregroundStyle(green)
            if let licensedPhoto {
                Image(uiImage: licensedPhoto).resizable().scaledToFill()
                    .frame(width: 940, height: format == .story ? 420 : 540)
                    .clipped().clipShape(RoundedRectangle(cornerRadius: 36))
            } else {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 175, weight: .ultraLight))
                    .foregroundStyle(green.opacity(0.65))
                    .frame(maxWidth: .infinity)
                    .frame(height: format == .story ? 255 : 360)
                    .background(green.opacity(0.08), in: RoundedRectangle(cornerRadius: 36))
            }
            Text(snapshot.title)
                .font(.system(size: 84, weight: .bold, design: .serif))
                .foregroundStyle(ink).lineLimit(3).minimumScaleFactor(0.6)
            if !snapshot.summary.isEmpty {
                Text(snapshot.summary).font(.system(size: 34))
                    .foregroundStyle(ink.opacity(0.74)).lineLimit(3)
            }
            HStack(spacing: 36) {
                if let prep = snapshot.prepMinutes { stat("PREP", "\(prep) min") }
                if let cook = snapshot.cookMinutes { stat("COOK", "\(cook) min") }
                if let servings = snapshot.servings { stat("SERVINGS", "\(servings)") }
            }
            .padding(28).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 26))
            if !snapshot.ingredients.isEmpty {
                Text("INGREDIENTS").font(.system(size: 25, weight: .bold)).tracking(3)
                ForEach(Array(snapshot.ingredients.prefix(4).enumerated()), id: \.offset) {
                    entry in
                    Text("• \(entry.element.amountText) \(entry.element.name)")
                        .font(.system(size: 31)).lineLimit(1)
                }
            }
            if format == .long && !snapshot.steps.isEmpty {
                Text("STEPS").font(.system(size: 25, weight: .bold)).tracking(3)
                ForEach(Array(snapshot.steps.prefix(3).enumerated()), id: \.offset) {
                    entry in
                    Text("\(entry.offset + 1). \(entry.element.instruction)")
                        .font(.system(size: 29)).lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            HStack(alignment: .bottom, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Full recipe & cooking steps")
                        .font(.system(size: 34, weight: .bold))
                    Text("Scan or open this link")
                        .font(.system(size: 28))
                    Text(url.host ?? "")
                        .font(.system(size: 28, weight: .medium))
                    Text(url.path).font(.system(size: 22)).lineLimit(2)
                }
                Spacer(minLength: 2)
                Image(uiImage: qr).interpolation(.none).resizable()
                    .frame(width: 244, height: 244).padding(22)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .foregroundStyle(ink).padding(70)
        .frame(width: 1080, height: format.height)
        .background(Color(red: 0.97, green: 0.96, blue: 0.92))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 19, weight: .medium)).tracking(2)
            Text(value).font(.system(size: 38, weight: .bold))
        }
    }
}
