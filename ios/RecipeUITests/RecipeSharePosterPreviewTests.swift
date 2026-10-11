// Developer: gengyun
// Purpose: Verify published-poster authorization, cancellation, rendering lineage and export payloads on Apple hosts.

import RecipeCore
import UIKit
import Vision
import XCTest

@testable import Recipe

@MainActor
final class RecipeSharePosterPreviewTests: XCTestCase {
    private let publicURL = URL(string: "https://example.invalid/r/original-fixture")!

    private func snapshot(full: Bool = false) throws -> PublicRecipeSnapshot {
        let recipe = Recipe(
            title: "Original fixture soup", summary: "Author-created test recipe.",
            ingredients: [.from(name: "Salt", amountText: "to taste")],
            steps: [.init(instruction: "Stir gently.")]
        )
        return try PublicRecipeSnapshot.preview(
            of: recipe,
            approvedBy: RecipeShareApproval(
                recipeID: recipe.id,
                expectedUpdatedAt: recipe.updatedAt,
                scope: full ? .fullInstructions : .summaryAndSource,
                hasDistributionRights: full
            )
        )
    }

    func testInitialInvalidityBlocksRenderingAndEveryOutput() async throws {
        var renders = 0
        var copies = 0
        let state = RecipePosterPreviewState(
            snapshot: try snapshot(), publicURL: publicURL,
            isStillValid: { false },
            renderer: { _, _, _ in
                renders += 1
                return UIImage()
            },
            copyURL: { _ in copies += 1 }
        )
        await state.render(format: .story)
        await state.copyLink()
        await state.share()
        XCTAssertEqual(renders, 0)
        XCTAssertEqual(copies, 0)
        XCTAssertTrue(state.isUnavailable)
        XCTAssertNil(state.image)
        XCTAssertNil(state.activity)
    }

    func testInvalidURLCannotInvokeCallerOrRenderer() async throws {
        var validations = 0
        let state = RecipePosterPreviewState(
            snapshot: try snapshot(), publicURL: URL(string: "https://example.invalid/private")!,
            isStillValid: {
                validations += 1
                return true
            },
            renderer: { _, _, _ in
                XCTFail("Invalid URL rendered")
                return UIImage()
            }
        )
        await state.render(format: .story)
        XCTAssertEqual(validations, 0)
        XCTAssertTrue(state.isUnavailable)
    }

    func testRenderShareAndCopyEachRevalidateAndShareOnlyImageAndMatchingURL() async throws {
        var validations = 0
        var copiedURL: URL?
        let rendered = UIImage()
        let state = RecipePosterPreviewState(
            snapshot: try snapshot(), publicURL: publicURL,
            isStillValid: {
                validations += 1
                return true
            },
            renderer: { _, _, _ in rendered },
            copyURL: { copiedURL = $0 }
        )
        await state.render(format: .story)
        XCTAssertEqual(validations, 2)
        await state.share()
        XCTAssertEqual(validations, 3)
        let activity = try XCTUnwrap(state.activity)
        XCTAssertEqual(activity.items.count, 2)
        XCTAssertTrue((activity.items[0] as? UIImage) === rendered)
        XCTAssertEqual(activity.items[1] as? URL, publicURL)
        state.activity = nil
        await state.copyLink()
        XCTAssertEqual(validations, 4)
        XCTAssertEqual(copiedURL, publicURL)
    }

    func testRevocationBeforeOutputClearsImageAndExistingActivity() async throws {
        var valid = true
        var copies = 0
        let state = RecipePosterPreviewState(
            snapshot: try snapshot(), publicURL: publicURL,
            isStillValid: { valid }, renderer: { _, _, _ in UIImage() },
            copyURL: { _ in copies += 1 }
        )
        await state.render(format: .story)
        await state.share()
        XCTAssertNotNil(state.activity)
        valid = false
        await state.copyLink()
        XCTAssertEqual(copies, 0)
        XCTAssertTrue(state.isUnavailable)
        XCTAssertNil(state.image)
        XCTAssertNil(state.activity)
    }

    func testCancelDuringValidationCannotCopyOrPresent() async throws {
        let entered = expectation(description: "Copy validation suspended")
        var continuation: CheckedContinuation<Bool, Never>?
        var copies = 0
        let state = RecipePosterPreviewState(
            snapshot: try snapshot(), publicURL: publicURL,
            isStillValid: {
                await withCheckedContinuation { pending in
                    continuation = pending
                    entered.fulfill()
                }
            },
            copyURL: { _ in copies += 1 }
        )
        let task = Task { await state.copyLink() }
        await fulfillment(of: [entered], timeout: 1)
        state.close()
        task.cancel()
        continuation?.resume(returning: true)
        await task.value
        XCTAssertEqual(copies, 0)
        XCTAssertNil(state.activity)
        XCTAssertFalse(state.isBusy)
    }

    func testChangedFormatRejectsLateRenderResult() async throws {
        let entered = expectation(description: "Story rendering suspended")
        var continuation: CheckedContinuation<UIImage, Never>?
        let longImage = UIImage()
        let state = RecipePosterPreviewState(
            snapshot: try snapshot(), publicURL: publicURL,
            isStillValid: { true },
            renderer: { _, _, format in
                if format == .story {
                    return await withCheckedContinuation { pending in
                        continuation = pending
                        entered.fulfill()
                    }
                }
                return longImage
            }
        )
        let story = Task { await state.render(format: .story) }
        await fulfillment(of: [entered], timeout: 1)
        await state.render(format: .long)
        continuation?.resume(returning: UIImage())
        await story.value
        XCTAssertTrue(state.image === longImage)
        XCTAssertFalse(state.isBusy)
    }

    func testRenderErrorAllowsOnlyNewlyValidatedCopy() async throws {
        var valid = true
        var copies = 0
        let state = RecipePosterPreviewState(
            snapshot: try snapshot(), publicURL: publicURL,
            isStillValid: { valid },
            renderer: { _, _, _ in throw RecipePosterError.renderFailed },
            copyURL: { _ in copies += 1 }
        )
        await state.render(format: .story)
        XCTAssertTrue(state.hasRenderError)
        XCTAssertNil(state.image)
        await state.copyLink()
        XCTAssertEqual(copies, 1)
        valid = false
        await state.copyLink()
        XCTAssertEqual(copies, 1)
        XCTAssertTrue(state.isUnavailable)
    }

    func testPostRenderAuthorizationCanDiscardSuccessfullyRenderedImage() async throws {
        var validations = 0
        let state = RecipePosterPreviewState(
            snapshot: try snapshot(), publicURL: publicURL,
            isStillValid: {
                validations += 1
                return validations == 1
            },
            renderer: { _, _, _ in UIImage() }
        )
        await state.render(format: .story)
        XCTAssertEqual(validations, 2)
        XCTAssertTrue(state.isUnavailable)
        XCTAssertNil(state.image)
    }

    func testExistingRendererDimensionsAndQRContainOnlyTheAuthorizedPublicURL() throws {
        for format in [RecipePosterFormat.story, .long] {
            let image = try RecipeSharePosterRenderer.render(
                snapshot: try snapshot(full: true), url: publicURL, format: format
            )
            let cgImage = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(cgImage.width, 1080)
            XCTAssertEqual(cgImage.height, format == .story ? 1920 : 2400)
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            XCTAssertTrue(
                request.results?.contains { $0.payloadStringValue == publicURL.absoluteString }
                    == true)
        }
    }
}
