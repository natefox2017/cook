// Developer: gengyun
// Purpose: Bounded batch document scanning state machine for multiple screenshots or one limited-page PDF.

import Foundation

/// Batch-level limits for the Premium document scanning tool. A batch accepts
/// at most 10 screenshots or a single PDF of at most 20 pages; per-file and
/// whole-batch byte ceilings bound uploads and OCR work.
public enum RecipeDocumentBatchLimits {
    public static let maxImages = 10
    public static let maxPDFPages = 20
    public static let maxFileBytes = 20 * 1024 * 1024
    public static let maxTotalBytes = 40 * 1024 * 1024
    public static let maxCandidates = 8
    public static let deadlineSeconds: TimeInterval = 180
}

public enum RecipeDocumentBatchError: Error, Equatable, Sendable {
    case emptySelection
    case mixedTypes
    case unsupportedType
    case tooManyImages
    case tooManyPDFs
    case ownerMismatch
    case fileTooLarge
    case totalTooLarge
    case pdfTooManyPages
}

public enum RecipeDocumentBatchInputType: String, Sendable, Equatable {
    case image
    case file
}

/// A single selected source. `pageCount` is the document's detected page count
/// (always 1 for a standalone screenshot; detected by the app via PDFKit for a
/// PDF). `ownerID` scopes every item so a batch can never mix two accounts.
public struct RecipeDocumentBatchItem: Sendable, Equatable, Hashable {
    public let id: String
    public let inputType: RecipeDocumentBatchInputType
    public let mimeType: String
    public let sizeBytes: Int
    public let pageCount: Int
    public let ownerID: UUID

    public init(
        id: String,
        inputType: RecipeDocumentBatchInputType,
        mimeType: String,
        sizeBytes: Int,
        pageCount: Int,
        ownerID: UUID
    ) {
        self.id = id
        self.inputType = inputType
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.pageCount = pageCount
        self.ownerID = ownerID
    }
}

public enum RecipeDocumentBatchKind: Sendable, Equatable {
    case images
    case pdf
}

public struct RecipeDocumentBatchSpec: Sendable, Equatable {
    public let kind: RecipeDocumentBatchKind
    public let items: [RecipeDocumentBatchItem]
    public let pageCount: Int
    public let totalBytes: Int

    public init(
        kind: RecipeDocumentBatchKind,
        items: [RecipeDocumentBatchItem],
        pageCount: Int,
        totalBytes: Int
    ) {
        self.kind = kind
        self.items = items
        self.pageCount = pageCount
        self.totalBytes = totalBytes
    }
}

public enum RecipeDocumentBatchPageStatus: Sendable, Equatable {
    case pending
    case processing
    case completed
    case failed
    case skipped
}

/// A stable, order-independent work unit. PDF pages keep their 1-based page
/// number; every screenshot is its own unit with page number 1.
public struct RecipeDocumentBatchPageUnit: Sendable, Equatable, Hashable {
    public let index: Int
    public let pageNumber: Int
    public let artifactID: String

    public init(index: Int, pageNumber: Int, artifactID: String) {
        self.index = index
        self.pageNumber = pageNumber
        self.artifactID = artifactID
    }
}

/// A server-derived candidate shown in the preview sheet. Candidate IDs are the
/// opaque stable IDs produced by the backend; the app never fabricates them.
public struct RecipeDocumentBatchCandidate: Sendable, Equatable, Hashable {
    public let candidateID: String
    public let title: String?
    public let ingredients: [String]
    public let steps: [String]

    public init(
        candidateID: String,
        title: String?,
        ingredients: [String],
        steps: [String]
    ) {
        self.candidateID = candidateID
        self.title = title
        self.ingredients = ingredients
        self.steps = steps
    }
}

/// What the preview sheet resolved into. `saveSelected` carries the exact
/// candidate IDs the user confirmed; `canceled` preserves the batch for a later
/// resume (for example after a quota upgrade) without charging anything.
public enum RecipeDocumentBatchSelection: Sendable, Equatable {
    case saveSelected(Set<String>)
    case canceled
}

/// Final preview outcome: the bounded candidate list plus whether more pages
/// remain unprocessed, so the UI can say the rest is still pending instead of
/// silently dropping pages.
public struct RecipeDocumentBatchOutcome: Sendable, Equatable {
    public let candidates: [RecipeDocumentBatchCandidate]
    public let hasMore: Bool
    public let unprocessed: Int

    public init(
        candidates: [RecipeDocumentBatchCandidate],
        hasMore: Bool,
        unprocessed: Int
    ) {
        self.candidates = candidates
        self.hasMore = hasMore
        self.unprocessed = unprocessed
    }
}

public struct RecipeDocumentBatchPageState: Sendable, Equatable {
    public let index: Int
    public var status: RecipeDocumentBatchPageStatus
    public var candidateID: String?

    public init(
        index: Int,
        status: RecipeDocumentBatchPageStatus,
        candidateID: String? = nil
    ) {
        self.index = index
        self.status = status
        self.candidateID = candidateID
    }
}

/// Recoverable batch progress. Persisting this between calls lets a timed-out
/// or crashed batch resume only the pages that never completed.
public struct RecipeDocumentBatchProgress: Sendable, Equatable {
    public let batchID: UUID
    public let totalPages: Int
    public var pages: [RecipeDocumentBatchPageState]

    public init(batchID: UUID, totalPages: Int, pages: [RecipeDocumentBatchPageState]) {
        self.batchID = batchID
        self.totalPages = totalPages
        self.pages = pages
    }
}

public enum RecipeDocumentBatch {
    private static let imageMIMETypes: Set<String> = [
        "image/jpeg", "image/png", "image/heic", "image/heif",
    ]

    /// Validates the selected sources and derives their bounded spec. Order is
    /// preserved, every item must belong to the same owner, and no source is
    /// dropped: an invalid batch fails atomically instead of partially scanning.
    public static func validate(_ items: [RecipeDocumentBatchItem]) throws
        -> RecipeDocumentBatchSpec
    {
        guard !items.isEmpty else {
            throw RecipeDocumentBatchError.emptySelection
        }
        guard let ownerID = items.first?.ownerID,
            items.allSatisfy({ $0.ownerID == ownerID })
        else {
            throw RecipeDocumentBatchError.ownerMismatch
        }

        let images = items.filter {
            $0.inputType == .image && imageMIMETypes.contains($0.mimeType)
        }
        let pdfs = items.filter {
            $0.inputType == .file && $0.mimeType == "application/pdf"
        }
        guard images.count + pdfs.count == items.count else {
            throw RecipeDocumentBatchError.unsupportedType
        }
        guard images.isEmpty || pdfs.isEmpty else {
            throw RecipeDocumentBatchError.mixedTypes
        }
        if !pdfs.isEmpty && pdfs.count > 1 {
            throw RecipeDocumentBatchError.tooManyPDFs
        }
        if pdfs.isEmpty && images.count > RecipeDocumentBatchLimits.maxImages {
            throw RecipeDocumentBatchError.tooManyImages
        }

        var totalBytes = 0
        for item in items {
            guard (1...RecipeDocumentBatchLimits.maxFileBytes).contains(item.sizeBytes)
            else {
                throw RecipeDocumentBatchError.fileTooLarge
            }
            totalBytes += item.sizeBytes
        }
        guard totalBytes <= RecipeDocumentBatchLimits.maxTotalBytes else {
            throw RecipeDocumentBatchError.totalTooLarge
        }

        var pageCount = images.count
        if let pdf = pdfs.first {
            guard (1...RecipeDocumentBatchLimits.maxPDFPages).contains(pdf.pageCount)
            else {
                throw RecipeDocumentBatchError.pdfTooManyPages
            }
            pageCount = pdf.pageCount
        }

        return RecipeDocumentBatchSpec(
            kind: pdfs.isEmpty ? .images : .pdf,
            items: items,
            pageCount: pageCount,
            totalBytes: totalBytes
        )
    }

    /// Expands a validated spec into stable, ordered page units. Images
    /// contribute one unit each; a PDF contributes one unit per page.
    public static func pageUnits(for spec: RecipeDocumentBatchSpec)
        -> [RecipeDocumentBatchPageUnit]
    {
        var units: [RecipeDocumentBatchPageUnit] = []
        var index = 0
        for item in spec.items {
            if item.inputType == .file && item.mimeType == "application/pdf" {
                for page in 1...spec.pageCount {
                    units.append(
                        RecipeDocumentBatchPageUnit(
                            index: index, pageNumber: page, artifactID: item.id))
                    index += 1
                }
            } else {
                units.append(
                    RecipeDocumentBatchPageUnit(
                        index: index, pageNumber: 1, artifactID: item.id))
                index += 1
            }
        }
        return units
    }

    /// Caps a server candidate list to the bounded preview size and reports
    /// whether more remain unprocessed. The caller supplies the full candidate
    /// list from the server; no page is merged or dropped by this function.
    public static func outcome(from candidates: [RecipeDocumentBatchCandidate])
        -> RecipeDocumentBatchOutcome
    {
        let hasMore = candidates.count > RecipeDocumentBatchLimits.maxCandidates
        let shown = Array(candidates.prefix(RecipeDocumentBatchLimits.maxCandidates))
        return RecipeDocumentBatchOutcome(
            candidates: shown,
            hasMore: hasMore,
            unprocessed: hasMore
                ? candidates.count - RecipeDocumentBatchLimits.maxCandidates : 0
        )
    }

    public static func initialProgress(
        batchID: UUID, units: [RecipeDocumentBatchPageUnit]
    ) -> RecipeDocumentBatchProgress {
        RecipeDocumentBatchProgress(
            batchID: batchID,
            totalPages: units.count,
            pages: units.map {
                RecipeDocumentBatchPageState(index: $0.index, status: .pending)
            }
        )
    }

    private static func updating(
        _ progress: RecipeDocumentBatchProgress,
        index: Int,
        _ update: (RecipeDocumentBatchPageState) -> RecipeDocumentBatchPageState
    ) -> RecipeDocumentBatchProgress {
        var updated = progress
        updated.pages = progress.pages.map { state in
            state.index == index ? update(state) : state
        }
        return updated
    }

    public static func markCompleted(
        _ progress: RecipeDocumentBatchProgress, index: Int, candidateID: String?
    ) -> RecipeDocumentBatchProgress {
        updating(progress, index: index) {
            RecipeDocumentBatchPageState(
                index: $0.index, status: .completed, candidateID: candidateID)
        }
    }

    public static func markFailed(
        _ progress: RecipeDocumentBatchProgress, index: Int
    ) -> RecipeDocumentBatchProgress {
        updating(progress, index: index) {
            RecipeDocumentBatchPageState(index: $0.index, status: .failed)
        }
    }

    public static func markSkipped(
        _ progress: RecipeDocumentBatchProgress, index: Int
    ) -> RecipeDocumentBatchProgress {
        updating(progress, index: index) {
            RecipeDocumentBatchPageState(index: $0.index, status: .skipped)
        }
    }

    /// Returns the page indexes that still need work after a deadline or crash.
    /// Completed pages are never re-run; failed pages are retryable.
    public static func resumablePages(_ progress: RecipeDocumentBatchProgress)
        -> (pending: [Int], completed: [Int])
    {
        var pending: [Int] = []
        var completed: [Int] = []
        for page in progress.pages {
            switch page.status {
            case .completed:
                completed.append(page.index)
            case .pending, .failed:
                pending.append(page.index)
            case .processing, .skipped:
                break
            }
        }
        return (pending, completed)
    }

    /// Whether a batch exceeded its processing deadline. `now` is injectable so
    /// callers and tests can evaluate the boundary without waiting.
    public static func deadlineExceeded(
        startedAt: Date, now: Date = Date()
    ) -> Bool {
        now.timeIntervalSince(startedAt) >= RecipeDocumentBatchLimits.deadlineSeconds
    }
}
