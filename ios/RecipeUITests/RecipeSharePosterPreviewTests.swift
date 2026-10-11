// Developer: gengyun
// Purpose: Verify published-poster authorization, cancellation, rendering lineage and export payloads on Apple hosts.

import CoreImage
import RecipeCore
import SwiftUI
import UIKit
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
            // Core Image's software detector decodes the actual rendered pixels without
            // depending on a simulator-only Vision inference model being available.
            let detector = try XCTUnwrap(
                CIDetector(
                    ofType: CIDetectorTypeQRCode,
                    context: CIContext(options: [.useSoftwareRenderer: true]),
                    options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
                )
            )
            let decoded = detector.features(in: CIImage(cgImage: cgImage))
                .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertTrue(decoded.contains(publicURL.absoluteString))
        }
    }

    func testDefaultCopyWritesOnlyMatchingURLToNativePasteboard() async throws {
        let pasteboard = UIPasteboard.general
        let previousItems = pasteboard.items
        defer {
            pasteboard.items = previousItems
        }
        pasteboard.string = "Original synthetic clipboard"
        var valid = true
        let state = RecipePosterPreviewState(
            snapshot: try snapshot(),
            publicURL: publicURL,
            isStillValid: { valid }
        )
        await state.copyLink()
        XCTAssertEqual(pasteboard.url, publicURL)
        let copiedItems = pasteboard.items
        valid = false
        await state.copyLink()
        XCTAssertEqual(pasteboard.url, publicURL)
        XCTAssertEqual(pasteboard.items.count, copiedItems.count)
        XCTAssertTrue(state.isUnavailable)
    }

    func testCancelDuringShareValidationCannotPresentActivity() async throws {
        var shouldSuspend = false
        var continuation: CheckedContinuation<Bool, Never>?
        let entered = expectation(description: "Share validation suspended")
        let state = RecipePosterPreviewState(
            snapshot: try snapshot(),
            publicURL: publicURL,
            isStillValid: {
                if shouldSuspend {
                    return await withCheckedContinuation { pending in
                        continuation = pending
                        entered.fulfill()
                    }
                }
                return true
            },
            renderer: { _, _, _ in UIImage() }
        )
        await state.render(format: .story)
        shouldSuspend = true
        let task = Task { await state.share() }
        await fulfillment(of: [entered], timeout: 2)
        state.close()
        task.cancel()
        continuation?.resume(returning: true)
        await task.value
        XCTAssertNil(state.activity)
        XCTAssertNil(state.image)
        XCTAssertFalse(state.isBusy)
    }

    func testProductionActivityWrapperCreatesNativeControllerAndCancels() async throws {
        let state = RecipePosterPreviewState(
            snapshot: try snapshot(),
            publicURL: publicURL,
            isStillValid: { true }
        )
        await state.render(format: .story)
        await state.share()
        let activity = try XCTUnwrap(state.activity)
        XCTAssertEqual(activity.items.count, 2)
        XCTAssertEqual(activity.items[1] as? URL, publicURL)
        let host = UIHostingController(rootView: RecipePosterActivity(items: activity.items))
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
        }
        let loaded = expectation(description: "Native activity wrapper loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loaded.fulfill()
        }
        await fulfillment(of: [loaded], timeout: 3)
        func findActivity(in controller: UIViewController) -> UIActivityViewController? {
            if let activity = controller as? UIActivityViewController {
                return activity
            }
            return controller.children.compactMap { findActivity(in: $0) }.first
        }
        let nativeController = try XCTUnwrap(findActivity(in: host))
        XCTAssertNotNil(nativeController.view.window)
        state.close()
        XCTAssertNil(state.activity)
        XCTAssertNil(state.image)
        await state.share()
        XCTAssertNil(state.activity)
    }

    func testProductionPreviewNativePickerSwitchesStoryToLongImage() async throws {
        let host = UIHostingController(
            rootView: RecipeSharePosterPreview(
                snapshot: try snapshot(full: true),
                publicURL: publicURL,
                isStillValid: { true }
            )
        )
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
        }
        func waitForLayout() async {
            let ready = expectation(description: "Preview layout and render")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                ready.fulfill()
            }
            await fulfillment(of: [ready], timeout: 3)
        }
        func findPicker(in view: UIView) -> UISegmentedControl? {
            if let picker = view as? UISegmentedControl {
                return picker
            }
            return view.subviews.compactMap { findPicker(in: $0) }.first
        }
        func savePreview(_ name: String) throws {
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[
                0]
            try image.pngData()?.write(to: directory.appendingPathComponent(name + ".png"))
        }
        await waitForLayout()
        let picker = try XCTUnwrap(findPicker(in: host.view))
        XCTAssertEqual(picker.numberOfSegments, 2)
        XCTAssertEqual(picker.titleForSegment(at: 0), "Story")
        XCTAssertEqual(picker.titleForSegment(at: 1), "Long Image")
        XCTAssertEqual(picker.selectedSegmentIndex, 0)
        try savePreview("DEV288-story-preview")
        picker.selectedSegmentIndex = 1
        picker.sendActions(for: .valueChanged)
        await waitForLayout()
        XCTAssertEqual(picker.selectedSegmentIndex, 1)
        try savePreview("DEV288-long-preview")
    }

}
