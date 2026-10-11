// Developer: gengyun
// Purpose: Exercises consent state with the original owner client and network-free HTTP fixtures.

import Foundation
import RecipeCore
import SwiftUI
import UIKit
import XCTest

@testable import Recipe

@MainActor
private final class ConsentFixture {
    let ownerA = UUID()
    let ownerB = UUID()
    let shareID = UUID()
    var currentOwner: UUID?
    var recipe: Recipe? = Recipe(title: "Soup", notes: "Private note")
    var requests: [URLRequest] = []
    var status = 201
    var version = 1
    var url = "https://recipes.example.org/r/opaque_share_slug"
    var afterSend: (() -> Void)?
    var pause = false
    var suspended: CheckedContinuation<Void, Never>?

    init() {
        currentOwner = ownerA
    }

    func service() throws -> RecipeSharePublishingService {
        try RecipeSharePublishingService(
            managementEndpoint: URL(
                string: "https://api.example.org/functions/v1/recipe-share-manage")!,
            session: {
                guard let owner = self.currentOwner else {
                    return nil
                }
                return RecipeSharePublishingSession(ownerID: owner, accessToken: "fake.token")
            },
            send: { request in
                self.requests.append(request)
                if self.pause {
                    await withCheckedContinuation {
                        self.suspended = $0
                    }
                }
                self.afterSend?()
                let requestBody = request.httpBody.flatMap {
                    try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
                }
                let body: [String: Any] = [
                    "shareID": self.shareID.uuidString,
                    "slug": "opaque_share_slug",
                    "shareVersion": self.version,
                    "scope": requestBody?["scope"] as? String ?? "summaryAndSource",
                    "createdAt": "2026-10-10T11:00:00Z",
                    "updatedAt": "2026-10-10T11:00:00Z",
                    "revokedAt": NSNull(),
                    "publicURL": self.url,
                ]
                return (
                    self.status == 204 ? Data() : try JSONSerialization.data(withJSONObject: body),
                    HTTPURLResponse(
                        url: request.url!, statusCode: self.status,
                        httpVersion: nil, headerFields: nil)!
                )
            }
        )
    }

    func state(existing: RecipeShareConsentExistingShare? = nil) throws -> RecipeShareConsentState {
        RecipeShareConsentState(
            recipeID: recipe!.id, service: try service(),
            currentOwnerID: {
                self.currentOwner
            },
            readRecipe: { id in
                self.recipe?.id == id ? self.recipe : nil
            },
            existingShare: existing
        )
    }

    func key(_ index: Int) throws -> String? {
        let body =
            try JSONSerialization.jsonObject(with: requests[index].httpBody!) as! [String: Any]
        return body["idempotencyKey"] as? String
    }
}

@MainActor
final class RecipeShareConsentStateTests: XCTestCase {
    func testChangedPreviewRequiresAnotherConfirmationWithoutSending() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        fake.recipe?.updatedAt.addTimeInterval(1)
        fake.recipe?.title = "Changed soup"
        await state.confirm()
        XCTAssertTrue(fake.requests.isEmpty)
        XCTAssertEqual(state.preview?.title, "Changed soup")
        await state.confirm()
        XCTAssertEqual(fake.requests.count, 1)
    }

    func testDismissalBeforeQueuedConfirmationPreventsRequests() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        state.cancel()
        await state.confirm()
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testCallerCancellationDoesNotAcceptLateResponse() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        fake.pause = true
        let operation = Task {
            await state.confirm()
        }
        while fake.suspended == nil {
            await Task.yield()
        }
        operation.cancel()
        fake.suspended?.resume()
        await operation.value
        XCTAssertNil(state.share)
        XCTAssertNil(state.publicURL)
    }

    func testFullInstructionsRequireExplicitRightsAndUseFrozenPreview() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        state.select(scope: .fullInstructions, rightsConfirmed: true)
        await state.confirm()
        XCTAssertNotNil(state.publicURL)
        let body =
            try JSONSerialization.jsonObject(with: fake.requests[0].httpBody!) as! [String: Any]
        XCTAssertEqual(body["scope"] as? String, "fullInstructions")
        XCTAssertEqual(body["hasDistributionRights"] as? Bool, true)
    }

    func testDefaultSummaryDoesNotRequestOrExposeLink() throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        XCTAssertEqual(state.scope, .summaryAndSource)
        XCTAssertFalse(state.rightsConfirmed)
        XCTAssertTrue(state.preview?.ingredients.isEmpty == true)
        XCTAssertNil(state.publicURL)
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testSignedOutAndUnconfirmedFullDoNotSend() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        fake.currentOwner = nil
        await state.confirm()
        XCTAssertTrue(fake.requests.isEmpty)
        fake.currentOwner = fake.ownerA
        state.select(scope: .fullInstructions, rightsConfirmed: false)
        await state.confirm()
        XCTAssertTrue(fake.requests.isEmpty)
    }

    func testSuccessfulCreateUsesAllowlistAndRealURL() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        await state.confirm()
        XCTAssertEqual(fake.requests.count, 1)
        XCTAssertEqual(state.publicURL?.absoluteString, fake.url)
        let body =
            try JSONSerialization.jsonObject(with: fake.requests[0].httpBody!) as! [String: Any]
        let snapshot = body["snapshot"] as! [String: Any]
        XCTAssertEqual(snapshot.count, 8)
        XCTAssertNil(snapshot["notes"])
        XCTAssertEqual(fake.requests[0].httpMethod, "POST")
        state.cancel()
        XCTAssertNil(state.publicURL)
    }

    func testBusyDuplicateConfirmAndCancellationIgnoreLateResponse() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        fake.pause = true
        let first = Task {
            await state.confirm()
        }
        while fake.suspended == nil {
            await Task.yield()
        }
        await state.confirm()
        XCTAssertEqual(fake.requests.count, 1)
        state.cancel()
        fake.suspended?.resume()
        await first.value
        XCTAssertNil(state.share)
        XCTAssertNil(state.publicURL)
        XCTAssertFalse(state.isBusy)
    }

    func testRetryKeepsConfirmedKey() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        fake.status = 503
        await state.confirm()
        XCTAssertTrue(state.canRetry)
        XCTAssertNil(state.publicURL)
        fake.status = 201
        await state.retry()
        XCTAssertEqual(try fake.key(0), try fake.key(1))
        XCTAssertNotNil(state.publicURL)
    }

    func testSelectionInvalidatesRetryAndMakesNewKey() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        fake.status = 503
        await state.confirm()
        state.select(scope: .summaryAndSource, rightsConfirmed: false)
        XCTAssertFalse(state.canRetry)
        await state.confirm()
        XCTAssertNotEqual(try fake.key(0), try fake.key(1))
    }

    func testSourceChangeDuringRequestAndDeletionDuringRetryRejectResult() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        fake.afterSend = {
            fake.recipe?.updatedAt.addTimeInterval(1)
        }
        await state.confirm()
        XCTAssertNil(state.share)
        XCTAssertNil(state.publicURL)
        fake.afterSend = nil
        state.refreshPreview()
        fake.status = 503
        await state.confirm()
        fake.recipe = nil
        await state.retry()
        XCTAssertEqual(fake.requests.count, 2)
        XCTAssertNil(state.publicURL)
    }

    func testOwnerChangeDuringRequestDoesNotExposeShare() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        fake.afterSend = {
            fake.currentOwner = fake.ownerB
        }
        await state.confirm()
        XCTAssertNil(state.share)
        XCTAssertNil(state.publicURL)
    }

    func testPublishedLinkIsHiddenAfterOwnerOrRecipeChanges() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        await state.confirm()
        XCTAssertNotNil(state.publicURL)
        fake.currentOwner = fake.ownerB
        XCTAssertNil(state.publicURL)
        fake.currentOwner = fake.ownerA
        fake.recipe?.updatedAt.addTimeInterval(1)
        XCTAssertNil(state.publicURL)
    }

    func testUpdateConflictRequiresReloadAndPreservesRecipe() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        await state.confirm()
        fake.status = 409
        await state.confirm()
        XCTAssertTrue(state.needsReload)
        XCTAssertEqual(fake.requests.last?.httpMethod, "PUT")
        XCTAssertEqual(fake.requests.last?.value(forHTTPHeaderField: "If-Match"), "\"v1\"")
        XCTAssertNotNil(state.share)
        XCTAssertEqual(fake.recipe?.notes, "Private note")
        XCTAssertNil(state.publicURL)
        fake.status = 200
        fake.version = 2
        await state.reload()
        XCTAssertFalse(state.needsReload)
        XCTAssertNotNil(state.publicURL)
        XCTAssertEqual(fake.requests.last?.httpMethod, "GET")
    }

    func testFailedRevokeRetainsMetadataAnd204ClearsOnlyShare() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        await state.confirm()
        fake.status = 503
        await state.revoke()
        XCTAssertNotNil(state.share)
        fake.status = 204
        await state.revoke()
        XCTAssertNil(state.share)
        XCTAssertNil(state.publicURL)
        XCTAssertNotNil(fake.recipe)
        XCTAssertEqual(fake.requests.last?.httpMethod, "DELETE")
    }

    func testInvalidMetadataCannotExposeLink() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        fake.url = "http://private.invalid/r/opaque_share_slug"
        await state.confirm()
        XCTAssertNil(state.share)
        XCTAssertNil(state.publicURL)
    }

    func testExistingBindingMustMatchRecipeAndOwner() async throws {
        let fake = ConsentFixture()
        let metadata = try await fake.service().create(
            recipe: fake.recipe!,
            approval: RecipeShareApproval(
                recipeID: fake.recipe!.id, expectedUpdatedAt: fake.recipe!.updatedAt,
                scope: .summaryAndSource, hasDistributionRights: false
            ), ownerID: fake.ownerA, idempotencyKey: UUID()
        )
        fake.requests = []
        let wrongRecipe = try fake.state(
            existing: RecipeShareConsentExistingShare(
                share: metadata, recipeID: UUID()
            ))
        await wrongRecipe.confirm()
        XCTAssertTrue(fake.requests.isEmpty)
        fake.currentOwner = fake.ownerB
        let wrongOwner = try fake.state(
            existing: RecipeShareConsentExistingShare(
                share: metadata, recipeID: fake.recipe!.id
            ))
        await wrongOwner.confirm()
        XCTAssertTrue(fake.requests.isEmpty)
        XCTAssertNil(wrongOwner.publicURL)
    }

    func testCopyActionUsesIsolatedPasteboardAndRechecksAuthorization() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        let sheet = RecipeShareConsentSheet(state: state)
        let name = UIPasteboard.Name("recipe.consent.test." + UUID().uuidString)
        let pasteboard = try XCTUnwrap(UIPasteboard(name: name, create: true))
        defer {
            UIPasteboard.remove(withName: name)
        }
        pasteboard.string = "Existing clipboard"
        XCTAssertFalse(sheet.copyLink(to: pasteboard))
        XCTAssertEqual(pasteboard.string, "Existing clipboard")
        await state.confirm()
        XCTAssertTrue(sheet.copyLink(to: pasteboard))
        XCTAssertEqual(pasteboard.url?.absoluteString, fake.url)
        pasteboard.string = "Keep this text"
        fake.currentOwner = fake.ownerB
        XCTAssertFalse(sheet.copyLink(to: pasteboard))
        fake.currentOwner = fake.ownerA
        fake.recipe?.updatedAt.addTimeInterval(1)
        XCTAssertFalse(sheet.copyLink(to: pasteboard))
        XCTAssertEqual(pasteboard.string, "Keep this text")
        state.cancel()
        XCTAssertFalse(sheet.copyLink(to: pasteboard))
    }

    func testSystemControllerInputIsURLOnlyAndRechecksAfterTap() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        let activity = ConsentURLActivity(state: state)
        XCTAssertTrue(activity.activityItems().isEmpty)
        await state.confirm()
        XCTAssertEqual(activity.activityItems().count, 1)
        XCTAssertEqual(activity.activityItems().first as? URL, state.publicURL)
        // Construct the actual UIKit adapter; this does not select a system share destination.
        let controller = activity.makeController()
        XCTAssertNil(controller.presentingViewController)
        fake.currentOwner = fake.ownerB
        XCTAssertTrue(activity.activityItems().isEmpty)
        fake.currentOwner = fake.ownerA
        state.cancel()
        XCTAssertTrue(activity.activityItems().isEmpty)
    }

    func testCopyAndSystemPayloadStayUnavailableUntilRecoveryAndAfterRevoke() async throws {
        let fake = ConsentFixture()
        let state = try fake.state()
        let sheet = RecipeShareConsentSheet(state: state)
        let activity = ConsentURLActivity(state: state)
        let name = UIPasteboard.Name("recipe.consent.test." + UUID().uuidString)
        let pasteboard = try XCTUnwrap(UIPasteboard(name: name, create: true))
        defer {
            UIPasteboard.remove(withName: name)
        }
        fake.status = 503
        await state.confirm()
        XCTAssertFalse(sheet.copyLink(to: pasteboard))
        XCTAssertTrue(activity.activityItems().isEmpty)
        fake.status = 201
        await state.retry()
        XCTAssertEqual(try fake.key(0), try fake.key(1))
        XCTAssertTrue(sheet.copyLink(to: pasteboard))
        XCTAssertEqual(activity.activityItems().count, 1)
        fake.status = 204
        await state.revoke()
        XCTAssertFalse(sheet.copyLink(to: pasteboard))
        XCTAssertTrue(activity.activityItems().isEmpty)
        XCTAssertNotNil(fake.recipe)
    }

    func testHostedSheetRendersNormalAndAccessibilityTypeAndCancelsOnRemoval() async throws {
        for size in [DynamicTypeSize.large, .accessibility5] {
            let fake = ConsentFixture()
            fake.recipe?.title = "Lemon soup with roasted vegetables and a long descriptive title"
            let state = try fake.state()
            await state.confirm()
            let root = AnyView(
                RecipeShareConsentSheet(state: state)
                    .dynamicTypeSize(size)
                    .preferredColorScheme(.light)
            )
            let host = UIHostingController(rootView: root)
            let scene = try XCTUnwrap(
                UIApplication.shared.connectedScenes.compactMap {
                    $0 as? UIWindowScene
                }.first
            )
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                XCTAssertTrue(
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
            }
            XCTAssertEqual(image.size, host.view.bounds.size)
            XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 1_000)
            let attachment = XCTAttachment(image: image)
            attachment.name = "ConsentSheet-" + String(describing: size)
            attachment.lifetime = .keepAlways
            add(attachment)
            // Exercise the real onDisappear modifier rather than calling state.cancel directly.
            host.rootView = AnyView(EmptyView())
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertNil(state.publicURL)
            await state.confirm()
            XCTAssertEqual(fake.requests.count, 1)
        }
    }

}
