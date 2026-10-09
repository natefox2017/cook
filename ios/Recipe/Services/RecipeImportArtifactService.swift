// Developer: gengyun
// Purpose: Uploads and retrieves private recipe sources through owner-checked artifact endpoints.

import Foundation
import RecipeCore
import Supabase

struct RecipeImportArtifactService {
    private struct CreateRequest: Encodable {
        let clientRequestID: UUID
        let inputType: RecipeShareInputType
        let mimeType: String
        let sizeBytes: Int

        enum CodingKeys: String, CodingKey {
            case clientRequestID = "client_request_id"
            case inputType = "input_type"
            case mimeType = "mime_type"
            case sizeBytes = "size_bytes"
        }
    }

    private struct UploadIntent: Decodable {
        struct Artifact: Decodable {
            let artifactID: UUID
            let state: String

            enum CodingKeys: String, CodingKey {
                case artifactID = "artifact_id"
                case state
            }
        }

        let artifact: Artifact
        let uploadPath: String?
        let uploadToken: String?

        enum CodingKeys: String, CodingKey {
            case artifact
            case uploadPath = "upload_path"
            case uploadToken = "upload_token"
        }
    }

    private struct Completion: Decodable {
        struct Artifact: Decodable {
            let artifactID: UUID

            enum CodingKeys: String, CodingKey {
                case artifactID = "artifact_id"
            }
        }

        let artifact: Artifact
    }

    private struct DownloadResponse: Decodable {
        let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case downloadURL = "download_url"
        }
    }

    private struct DeleteResponse: Decodable {
        let artifactID: UUID

        enum CodingKeys: String, CodingKey {
            case artifactID = "artifact_id"
        }
    }

    func upload(
        receipt: RecipeShareReceipt,
        ownerID: UUID
    ) async throws -> UUID {
        try await verifySession(ownerID: ownerID)
        let data = try RecipeShareInbox.shared().fileData(for: receipt)
        guard let mimeType = receipt.payload.mimeType else {
            throw RecipeRemoteImportError.transport(RecipeLanguage.localized("The shared file has no supported media type."))
        }
        let intent: UploadIntent = try await RecipeSupabase.client.functions.invoke(
            "recipe-import-artifacts",
            options: FunctionInvokeOptions(
                method: .post,
                body: CreateRequest(
                    clientRequestID: receipt.clientRequestID,
                    inputType: receipt.inputType,
                    mimeType: mimeType,
                    sizeBytes: data.count
                )
            )
        )
        if intent.artifact.state == "available" {
            return intent.artifact.artifactID
        }
        guard let path = intent.uploadPath, let token = intent.uploadToken else {
            throw RecipeRemoteImportError.transport(RecipeLanguage.localized("The file upload could not be resumed."))
        }

        do {
            try await RecipeSupabase.client.storage
                .from("recipe-import-artifacts")
                .uploadToSignedURL(
                    path,
                    token: token,
                    data: data,
                    options: FileOptions(contentType: mimeType, upsert: false)
                )
        } catch {
            // A connection loss can happen after Storage accepted all bytes.
            return try await complete(intent.artifact.artifactID)
        }
        return try await complete(intent.artifact.artifactID)
    }

    func downloadURL(
        artifactID: UUID,
        ownerID: UUID
    ) async throws -> URL {
        try await verifySession(ownerID: ownerID)
        let response: DownloadResponse = try await RecipeSupabase.client.functions
            .invoke(
                "recipe-import-artifacts/\(artifactID.uuidString.lowercased())/download",
                options: FunctionInvokeOptions(method: .get)
            )
        return response.downloadURL
    }

    func delete(
        artifactID: UUID,
        ownerID: UUID
    ) async throws {
        try await verifySession(ownerID: ownerID)
        _ =
            try await RecipeSupabase.client.functions.invoke(
                "recipe-import-artifacts/\(artifactID.uuidString.lowercased())",
                options: FunctionInvokeOptions(method: .delete)
            ) as DeleteResponse
    }

    private func complete(_ artifactID: UUID) async throws -> UUID {
        let response: Completion = try await RecipeSupabase.client.functions
            .invoke(
                "recipe-import-artifacts/\(artifactID.uuidString.lowercased())/complete",
                options: FunctionInvokeOptions(method: .post)
            )
        return response.artifact.artifactID
    }

    private func verifySession(ownerID: UUID) async throws {
        let session = try await RecipeSupabase.client.auth.session
        guard session.user.id == ownerID else {
            throw RecipeShareImportWorkflowError.accountChanged
        }
    }
}
