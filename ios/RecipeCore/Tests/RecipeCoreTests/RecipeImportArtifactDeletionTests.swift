// Developer: gengyun
// Purpose: Tests backward-compatible private source deletion metadata.

import Foundation
import Testing
@testable import RecipeCore

@Test
func artifactDeletionMarkerPreservesImportedEvidenceAcrossEncoding() throws {
    let artifactID = UUID()
    let jobID = UUID()
    let result = RecipeImportJobResponse.Result(
        recipeID: UUID(),
        status: "needs_review",
        source: .init(inputType: "file", sourceArtifactID: artifactID),
        fields: [:],
        reviewFields: ["artifact_text"]
    )
    let original = RecipeImportRecord(jobID: jobID, result: result)
    let oldData = try JSONEncoder().encode(original)
    let legacy = try JSONDecoder().decode(RecipeImportRecord.self, from: oldData)

    #expect(legacy.sourceArtifactDeletedAt == nil)
    #expect(legacy.result.source.sourceArtifactID == artifactID)

    var deleted = legacy
    deleted.sourceArtifactDeletedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let data = try JSONEncoder().encode(deleted)
    let restored = try JSONDecoder().decode(RecipeImportRecord.self, from: data)

    #expect(restored.sourceArtifactDeletedAt == deleted.sourceArtifactDeletedAt)
    #expect(restored.jobID == jobID)
    #expect(restored.result.source.sourceArtifactID == artifactID)
    #expect(restored.result.reviewFields == ["artifact_text"])
}
