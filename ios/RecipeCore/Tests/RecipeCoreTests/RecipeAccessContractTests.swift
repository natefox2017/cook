// Developer: gengyun
// Purpose: Exercise the frozen DEV-425 commercial access/usage DTOs against canonical wire examples.

import Foundation
import Testing

@testable import RecipeCore

private let owner = "a0000000-0000-4000-8000-000000000001"
private let operation = "b0000000-0000-4000-8000-000000000002"
private let recipe = "c0000000-0000-4000-8000-000000000003"
private let requestID = "d0000000-0000-4000-8000-000000000004"
private let job = "e0000000-0000-4000-8000-000000000005"
private let candidateA = "f0000000-0000-4000-8000-000000000001"
private let candidateB = "f0000000-0000-4000-8000-000000000002"
private let candidateC = "f0000000-0000-4000-8000-000000000003"
private let sessionID = "f0000000-0000-4000-8000-000000000004"
private let turnRequestID = "f0000000-0000-4000-8000-000000000005"
private let inputHash = String(repeating: "a", count: 64)
private let payloadHash = String(repeating: "b", count: 64)

private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

private let freeAccessJSON = #"""
{
  "owner_id": "a0000000-0000-4000-8000-000000000001",
  "server_time": "2026-10-15T12:00:00.000Z",
  "policy_version": 1,
  "stage": "freeTest",
  "entitlement": { "status": "free", "valid_until": null },
  "capabilities": [
    { "id": "smart_import", "entitled": true, "quota": { "units": "successful_imports", "period_type": "iso_week", "period_start": "2026-10-12T00:00:00.000Z", "reset_at": "2026-10-19T00:00:00.000Z", "limit": 5, "used": 2, "reserved": 1, "remaining": 2 } },
    { "id": "ai_edit", "entitled": true, "quota": { "units": "successful_edits", "period_type": "lifetime", "period_start": null, "reset_at": null, "limit": 3, "used": 1, "reserved": 0, "remaining": 2 } },
    { "id": "hands_free_cooking", "entitled": false, "quota": null },
    { "id": "weekly_templates", "entitled": false, "quota": null },
    { "id": "weekly_groceries", "entitled": false, "quota": null },
    { "id": "auto_plan", "entitled": false, "quota": null },
    { "id": "recipe_question", "entitled": false, "quota": null },
    { "id": "recipe_translation", "entitled": false, "quota": null },
    { "id": "media_import", "entitled": false, "quota": null },
    { "id": "pdf_export", "entitled": false, "quota": null }
  ]
}
"""#

private let premiumAccessJSON = #"""
{
  "owner_id": "a0000000-0000-4000-8000-000000000001",
  "server_time": "2026-10-15T12:00:00.000Z",
  "policy_version": 1,
  "stage": "commercial",
  "entitlement": { "status": "premium", "valid_until": "2026-11-01T00:00:00.000Z" },
  "capabilities": [
    { "id": "smart_import", "entitled": true, "quota": { "units": "successful_imports", "period_type": "utc_month", "period_start": "2026-10-01T00:00:00.000Z", "reset_at": "2026-11-01T00:00:00.000Z", "limit": 100, "used": 99, "reserved": 0, "remaining": 1 } },
    { "id": "ai_edit", "entitled": true, "quota": { "units": "successful_edits", "period_type": "utc_month", "period_start": "2026-10-01T00:00:00.000Z", "reset_at": "2026-11-01T00:00:00.000Z", "limit": 30, "used": 5, "reserved": 1, "remaining": 24 } },
    { "id": "recipe_question", "entitled": true, "quota": { "units": "successful_answers", "period_type": "utc_month", "period_start": "2026-10-01T00:00:00.000Z", "reset_at": "2026-11-01T00:00:00.000Z", "limit": 100, "used": 0, "reserved": 0, "remaining": 100 } },
    { "id": "recipe_translation", "entitled": true, "quota": { "units": "successful_translations", "period_type": "utc_month", "period_start": "2026-10-01T00:00:00.000Z", "reset_at": "2026-11-01T00:00:00.000Z", "limit": 20, "used": 0, "reserved": 0, "remaining": 20 } },
    { "id": "media_import", "entitled": true, "quota": { "units": "media_tasks", "period_type": "utc_month", "period_start": "2026-10-01T00:00:00.000Z", "reset_at": "2026-11-01T00:00:00.000Z", "limit": 20, "used": 0, "reserved": 0, "remaining": 20 } },
    { "id": "hands_free_cooking", "entitled": true, "quota": null },
    { "id": "weekly_templates", "entitled": true, "quota": null },
    { "id": "weekly_groceries", "entitled": true, "quota": null },
    { "id": "auto_plan", "entitled": true, "quota": null },
    { "id": "pdf_export", "entitled": true, "quota": null }
  ]
}
"""#

private let expiredAccessJSON = #"""
{
  "owner_id": "a0000000-0000-4000-8000-000000000001",
  "server_time": "2026-10-15T12:00:00.000Z",
  "policy_version": 1,
  "stage": "commercial",
  "entitlement": { "status": "expired", "valid_until": "2026-10-01T00:00:00.000Z" },
  "capabilities": [
    { "id": "smart_import", "entitled": true, "quota": { "units": "successful_imports", "period_type": "iso_week", "period_start": "2026-10-12T00:00:00.000Z", "reset_at": "2026-10-19T00:00:00.000Z", "limit": 5, "used": 3, "reserved": 0, "remaining": 2 } },
    { "id": "ai_edit", "entitled": true, "quota": { "units": "successful_edits", "period_type": "lifetime", "period_start": null, "reset_at": null, "limit": 3, "used": 3, "reserved": 0, "remaining": 0 } },
    { "id": "hands_free_cooking", "entitled": false, "quota": null },
    { "id": "weekly_templates", "entitled": false, "quota": null },
    { "id": "weekly_groceries", "entitled": false, "quota": null },
    { "id": "auto_plan", "entitled": false, "quota": null },
    { "id": "recipe_question", "entitled": false, "quota": null },
    { "id": "recipe_translation", "entitled": false, "quota": null },
    { "id": "media_import", "entitled": false, "quota": null },
    { "id": "pdf_export", "entitled": false, "quota": null }
  ]
}
"""#

@Suite struct RecipeAccessContractTests {
    @Test func freeAccessResponseDecodes() throws {
        let access = try decode(RecipeAccessResponse.self, from: freeAccessJSON)
        #expect(access.ownerID == owner)
        #expect(access.stage == .freeTest)
        #expect(access.policyVersion == 1)
        #expect(access.entitlement.status == .free)
        #expect(access.entitlement.validUntil == nil)
        #expect(access.capabilities.count == 10)
        let importCapability = try #require(access.capabilities.first { $0.id == .smartImport })
        #expect(importCapability.entitled)
        #expect(importCapability.quota?.limit == 5)
        #expect(importCapability.quota?.remaining == 2)
        #expect(importCapability.quota?.periodType == .isoWeek)
    }

    @Test func premiumAccessResponseDecodes() throws {
        let access = try decode(RecipeAccessResponse.self, from: premiumAccessJSON)
        #expect(access.stage == .commercial)
        #expect(access.entitlement.status == .premium)
        #expect(access.entitlement.validUntil != nil)
        let editCapability = try #require(access.capabilities.first { $0.id == .aiEdit })
        #expect(editCapability.quota?.limit == 30)
        #expect(editCapability.quota?.periodType == .utcMonth)
    }

    @Test func expiredAccessResponseFallsBackToFreeQuota() throws {
        let access = try decode(RecipeAccessResponse.self, from: expiredAccessJSON)
        #expect(access.stage == .commercial)
        #expect(access.entitlement.status == .expired)
        let editCapability = try #require(access.capabilities.first { $0.id == .aiEdit })
        #expect(editCapability.entitled)
        #expect(editCapability.quota?.remaining == 0)
    }

    @Test func reservationAndSettlementResponsesDecode() throws {
        let request = try decode(
            RecipeReservationRequest.self,
            from: #"{"operation_id":"\#(operation)","capability":"smart_import","input_hash":"\#(inputHash)","estimated_units":3,"source":{"origin":"import_job","job_id":"\#(job)","candidate_ids":["\#(candidateA)","\#(candidateB)","\#(candidateC)"],"session_id":null,"turn_request_id":null}}"#)
        #expect(request.capability == .smartImport)
        #expect(request.estimatedUnits == 3)
        #expect(request.source.candidateIDs?.count == 3)

        let reservation = try decode(
            RecipeReservation.self,
            from: #"""
            {"operation_id":"\#(operation)","owner_id":"\#(owner)","capability":"smart_import","period_start":"2026-10-12T00:00:00.000Z","policy_version":1,"tier_at_reserve":"free","reserved_units":3,"status":"reserved","reserved_until":"2026-10-15T12:10:00.000Z"}
            """#)
        #expect(reservation.tierAtReserve == .free)
        #expect(reservation.reservedUnits == 3)

        let commit = try decode(
            RecipeUsageCommitResponse.self,
            from: #"{"operation_id":"\#(operation)","status":"committed","committed_units":1,"period_start":"2026-10-12T00:00:00.000Z"}"#)
        #expect(commit.status == "committed")

        let finalize = try decode(
            RecipeUsageFinalizeResponse.self,
            from: #"{"operation_id":"\#(operation)","status":"finalized","recipe_id":"\#(recipe)","payload_hash":"\#(payloadHash)","committed_units":1,"period_start":"2026-10-12T00:00:00.000Z"}"#)
        #expect(finalize.recipeID == recipe)
        #expect(finalize.payloadHash == payloadHash)

        let ack = try decode(
            RecipeUsageAckResponse.self,
            from: #"{"operation_id":"\#(operation)","status":"acked"}"#)
        #expect(ack.status == "acked")
    }

    @Test func errorEnvelopeDecodes() throws {
        let error = try decode(
            RecipeUsageAPIError.self,
            from: #"{"code":"QUOTA_EXCEEDED","message":"Weekly import quota reached.","recoverable":true,"request_id":"\#(requestID)"}"#)
        #expect(error.code == "QUOTA_EXCEEDED")
        #expect(RecipeUsageAPIError.statuses[error.code] == 402)
    }

    @Test func unknownCapabilityIsRejected() {
        #expect(throws: RecipeAccessContractError.invalidResponse) {
            _ = try decode(RecipeCapability.self, from: #""not_a_capability""#)
        }
    }

    @Test func negativeQuotaCountIsRejected() {
        #expect(throws: RecipeAccessContractError.invalidResponse) {
            _ = try decode(
                RecipeQuota.self,
                from: #"{"units":"successful_imports","period_type":"iso_week","period_start":"2026-10-12T00:00:00.000Z","reset_at":"2026-10-19T00:00:00.000Z","limit":5,"used":-1,"reserved":0,"remaining":6}"#)
        }
    }

    @Test func quotaWithInconsistentRemainingIsRejected() {
        #expect(throws: RecipeAccessContractError.invalidResponse) {
            _ = try decode(
                RecipeQuota.self,
                from: #"{"units":"successful_imports","period_type":"iso_week","period_start":"2026-10-12T00:00:00.000Z","reset_at":"2026-10-19T00:00:00.000Z","limit":5,"used":2,"reserved":1,"remaining":99}"#)
        }
    }

    @Test func invalidPeriodOrderIsRejected() {
        #expect(throws: RecipeAccessContractError.invalidResponse) {
            _ = try decode(
                RecipeQuota.self,
                from: #"{"units":"successful_imports","period_type":"iso_week","period_start":"2026-10-19T00:00:00.000Z","reset_at":"2026-10-12T00:00:00.000Z","limit":5,"used":0,"reserved":0,"remaining":5}"#)
        }
    }

    @Test func lifetimePeriodWithBoundsIsRejected() {
        #expect(throws: RecipeAccessContractError.invalidResponse) {
            _ = try decode(
                RecipeQuota.self,
                from: #"{"units":"successful_edits","period_type":"lifetime","period_start":"2026-10-12T00:00:00.000Z","reset_at":null,"limit":3,"used":0,"reserved":0,"remaining":3}"#)
        }
    }

    @Test func extraWireKeyIsRejected() {
        #expect(throws: RecipeAccessContractError.invalidResponse) {
            _ = try decode(
                RecipeAccessResponse.self,
                from: #"{"owner_id":"\#(owner)","server_time":"2026-10-15T12:00:00.000Z","policy_version":1,"stage":"freeTest","entitlement":{"status":"free","valid_until":null},"capabilities":[],"unexpected":"x"}"#)
        }
    }

    @Test func malformedOwnerIDIsRejected() {
        #expect(throws: RecipeAccessContractError.invalidResponse) {
            _ = try decode(
                RecipeAccessResponse.self,
                from: #"{"owner_id":"not-a-uuid","server_time":"2026-10-15T12:00:00.000Z","policy_version":1,"stage":"freeTest","entitlement":{"status":"free","valid_until":null},"capabilities":[]}"#)
        }
    }

    @Test func unknownErrorCodeIsRejected() {
        #expect(throws: RecipeAccessContractError.invalidResponse) {
            _ = try decode(
                RecipeUsageAPIError.self,
                from: #"{"code":"MADE_UP","message":"nope","recoverable":false,"request_id":"\#(requestID)"}"#)
        }
    }

    @Test func downgradedQuotaWithUsedAboveLimitDecodes() throws {
        let q = try decode(
            RecipeQuota.self,
            from: #"{"units":"successful_imports","period_type":"iso_week","period_start":"2026-10-12T00:00:00.000Z","reset_at":"2026-10-19T00:00:00.000Z","limit":5,"used":7,"reserved":0,"remaining":0}"#)
        #expect(q.used == 7)
        #expect(q.remaining == 0)
    }

    @Test func countBeyondSafeIntegerIsRejected() {
        #expect(throws: RecipeAccessContractError.invalidResponse) {
            _ = try decode(
                RecipeQuota.self,
                from: #"{"units":"successful_imports","period_type":"iso_week","period_start":"2026-10-12T00:00:00.000Z","reset_at":"2026-10-19T00:00:00.000Z","limit":9007199254740992,"used":0,"reserved":0,"remaining":9007199254740992}"#)
        }
    }

    @Test func uppercaseOwnerIDIsRejected() {
        #expect(throws: RecipeAccessContractError.invalidResponse) {
            _ = try decode(
                RecipeAccessResponse.self,
                from: #"{"owner_id":"A0000000-0000-4000-8000-000000000001","server_time":"2026-10-15T12:00:00.000Z","policy_version":1,"stage":"freeTest","entitlement":{"status":"free","valid_until":null},"capabilities":[{"id":"pdf_export","entitled":false,"quota":null}]}"#)
        }
    }

    @Test func invalidCalendarDateIsRejected() {
        #expect(throws: RecipeAccessContractError.invalidResponse) {
            _ = try decode(
                RecipeAccessResponse.self,
                from: #"{"owner_id":"\#(owner)","server_time":"2026-02-30T00:00:00.000Z","policy_version":1,"stage":"freeTest","entitlement":{"status":"free","valid_until":null},"capabilities":[{"id":"pdf_export","entitled":false,"quota":null}]}"#)
        }
    }

    @Test func importReservationRequiresMatchingCandidateCount() {
        #expect(throws: RecipeAccessContractError.invalidResponse) {
            _ = try decode(
                RecipeReservationRequest.self,
                from: #"{"operation_id":"\#(operation)","capability":"smart_import","input_hash":"\#(inputHash)","estimated_units":2,"source":{"origin":"import_job","job_id":"\#(job)","candidate_ids":["\#(candidateA)"],"session_id":null,"turn_request_id":null}}"#)
        }
    }

    @Test func finalizeRequiresSingleCandidate() {
        #expect(throws: RecipeAccessContractError.invalidResponse) {
            _ = try decode(
                RecipeUsageFinalizeRequest.self,
                from: #"{"capability":"smart_import","input_hash":"\#(inputHash)","source":{"origin":"import_job","job_id":"\#(job)","candidate_ids":["\#(candidateA)","\#(candidateB)"],"session_id":null,"turn_request_id":null}}"#)
        }
    }

    @Test func reservationRequestEncodesRoundTrip() throws {
        let source = try RecipeUsageSource(importJobID: job, candidateIDs: [candidateA, candidateB])
        let request = try RecipeReservationRequest(
            operationID: operation, capability: .smartImport, inputHash: inputHash,
            estimatedUnits: 2, source: source)
        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(RecipeReservationRequest.self, from: encoded)
        #expect(decoded == request)
    }

    @Test func aiEditFinalizeRequestEncodesRoundTrip() throws {
        let source = try RecipeUsageSource(sessionID: sessionID, turnRequestID: turnRequestID)
        let request = try RecipeUsageFinalizeRequest(
            capability: .aiEdit, inputHash: inputHash, source: source)
        #expect(request.source.origin == .draftApproval)
        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(RecipeUsageFinalizeRequest.self, from: encoded)
        #expect(decoded == request)
    }
}
