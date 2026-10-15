// Developer: gengyun
// Purpose: Verifies bounded batch validation, owner scoping, ordering and recoverable progress.

import Foundation
import Testing

@testable import RecipeCore

struct RecipeDocumentBatchTests {
    private let owner = UUID()

    private func imageItem(_ id: String, sizeBytes: Int = 1024) -> RecipeDocumentBatchItem {
        RecipeDocumentBatchItem(
            id: id,
            inputType: .image,
            mimeType: "image/jpeg",
            sizeBytes: sizeBytes,
            pageCount: 1,
            ownerID: owner
        )
    }

    private func pdfItem(pageCount: Int, sizeBytes: Int = 1024) -> RecipeDocumentBatchItem {
        RecipeDocumentBatchItem(
            id: "pdf-id",
            inputType: .file,
            mimeType: "application/pdf",
            sizeBytes: sizeBytes,
            pageCount: pageCount,
            ownerID: owner
        )
    }

    @Test
    func validationEnforcesPageAndCountLimits() throws {
        let images = (0..<11).map { imageItem("image-\($0)") }
        #expect(throws: RecipeDocumentBatchError.tooManyImages) {
            try RecipeDocumentBatch.validate(images)
        }

        let oversized = [pdfItem(pageCount: 21)]
        #expect(throws: RecipeDocumentBatchError.pdfTooManyPages) {
            try RecipeDocumentBatch.validate(oversized)
        }

        let zeroPages = [pdfItem(pageCount: 0)]
        #expect(throws: RecipeDocumentBatchError.pdfTooManyPages) {
            try RecipeDocumentBatch.validate(zeroPages)
        }

        #expect(throws: RecipeDocumentBatchError.emptySelection) {
            try RecipeDocumentBatch.validate([])
        }
    }

    @Test
    func validationRejectsMixedTypesAndSizeOverflow() throws {
        let mixed = [imageItem("a"), pdfItem(pageCount: 2)]
        #expect(throws: RecipeDocumentBatchError.mixedTypes) {
            try RecipeDocumentBatch.validate(mixed)
        }

        let unsupported = RecipeDocumentBatchItem(
            id: "video",
            inputType: .file,
            mimeType: "video/mp4",
            sizeBytes: 1024,
            pageCount: 1,
            ownerID: owner
        )
        #expect(throws: RecipeDocumentBatchError.unsupportedType) {
            try RecipeDocumentBatch.validate([unsupported])
        }

        let largeFile = imageItem(
            "large", sizeBytes: RecipeDocumentBatchLimits.maxFileBytes + 1)
        #expect(throws: RecipeDocumentBatchError.fileTooLarge) {
            try RecipeDocumentBatch.validate([largeFile])
        }

        let overTotal = (0..<3).map {
            imageItem("image-\($0)", sizeBytes: 15 * 1024 * 1024)
        }
        #expect(throws: RecipeDocumentBatchError.totalTooLarge) {
            try RecipeDocumentBatch.validate(overTotal)
        }
    }

    @Test
    func validationScopesEveryItemToOneOwner() throws {
        let other = UUID()
        let foreign = RecipeDocumentBatchItem(
            id: "foreign",
            inputType: .image,
            mimeType: "image/png",
            sizeBytes: 1024,
            pageCount: 1,
            ownerID: other
        )
        #expect(throws: RecipeDocumentBatchError.ownerMismatch) {
            try RecipeDocumentBatch.validate([imageItem("a"), foreign])
        }
    }

    @Test
    func pageUnitsPreserveDocumentOrder() throws {
        let imageSpec = try RecipeDocumentBatch.validate([
            imageItem("one"), imageItem("two"), imageItem("three"),
        ])
        let imageUnits = RecipeDocumentBatch.pageUnits(for: imageSpec)
        #expect(imageUnits.map(\.artifactID) == ["one", "two", "three"])
        #expect(imageUnits.map(\.pageNumber) == [1, 1, 1])

        let pdfSpec = try RecipeDocumentBatch.validate([pdfItem(pageCount: 2)])
        let pdfUnits = RecipeDocumentBatch.pageUnits(for: pdfSpec)
        #expect(pdfUnits.map(\.pageNumber) == [1, 2])
        #expect(pdfUnits.map(\.artifactID) == ["pdf-id", "pdf-id"])
    }

    @Test
    func progressResumesOnlyUnfinishedPages() throws {
        let spec = try RecipeDocumentBatch.validate([
            imageItem("one"), imageItem("two"), imageItem("three"),
        ])
        let units = RecipeDocumentBatch.pageUnits(for: spec)
        var progress = RecipeDocumentBatch.initialProgress(
            batchID: UUID(), units: units)

        progress = RecipeDocumentBatch.markCompleted(
            progress, index: 0, candidateID: "candidate-v2-deadbeef")
        progress = RecipeDocumentBatch.markFailed(progress, index: 1)
        progress = RecipeDocumentBatch.markSkipped(progress, index: 2)

        let resumable = RecipeDocumentBatch.resumablePages(progress)
        #expect(resumable.completed == [0])
        #expect(resumable.pending == [1])
        #expect(
            progress.pages.first(where: { $0.index == 0 })?.candidateID
                == "candidate-v2-deadbeef"
        )
    }

    @Test
    func outcomeCapsCandidatesAndFlagsUnprocessedPages() {
        let candidates = (0..<10).map { index in
            RecipeDocumentBatchCandidate(
                candidateID: "candidate-v2-\(index)",
                title: "Recipe \(index)",
                ingredients: ["ingredient"],
                steps: ["step"]
            )
        }
        let outcome = RecipeDocumentBatch.outcome(from: candidates)
        #expect(outcome.hasMore)
        #expect(outcome.unprocessed == 2)
        #expect(outcome.candidates.count == RecipeDocumentBatchLimits.maxCandidates)

        let few = RecipeDocumentBatch.outcome(from: Array(candidates.prefix(3)))
        #expect(!few.hasMore)
        #expect(few.unprocessed == 0)
        #expect(few.candidates.count == 3)
    }

    @Test
    func deadlineBoundaryIsDeterministic() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(
            !RecipeDocumentBatch.deadlineExceeded(
                startedAt: start,
                now: Date(timeIntervalSince1970: RecipeDocumentBatchLimits.deadlineSeconds - 1)
            )
        )
        #expect(
            RecipeDocumentBatch.deadlineExceeded(
                startedAt: start,
                now: Date(timeIntervalSince1970: RecipeDocumentBatchLimits.deadlineSeconds)
            )
        )
    }
}
