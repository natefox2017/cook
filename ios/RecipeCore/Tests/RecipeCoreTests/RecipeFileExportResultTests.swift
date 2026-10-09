// Developer: gengyun
// Purpose: Tests system document-export completion without invoking a Files provider.

import Foundation
import Testing

@testable import RecipeCore

@Test
func fileExportSuccessRequiresPickerCompletion() {
    let selectedURL = URL(fileURLWithPath: "/tmp/RecipePals-Recipes.json")

    #expect(
        RecipeFileExportResult(.success(selectedURL))
            == .saved(filename: "RecipePals-Recipes.json")
    )
}

@Test
func fileExportUserCancellationDoesNotReportFailure() {
    let error = NSError(
        domain: NSCocoaErrorDomain,
        code: CocoaError.Code.userCancelled.rawValue
    )

    #expect(RecipeFileExportResult(.failure(error)) == .cancelled)
}

@Test
func fileExportProviderErrorIsReported() {
    let error = NSError(
        domain: NSCocoaErrorDomain,
        code: CocoaError.Code.fileWriteNoPermission.rawValue,
        userInfo: [NSLocalizedDescriptionKey: "Destination is not writable"]
    )

    #expect(
        RecipeFileExportResult(.failure(error))
            == .failed(message: "Destination is not writable")
    )
}

@Test
func fileExportDoesNotSuppressSameCodeInDifferentErrorDomain() {
    let error = NSError(
        domain: "com.example.external-provider",
        code: CocoaError.Code.userCancelled.rawValue,
        userInfo: [NSLocalizedDescriptionKey: "External provider failed"]
    )

    #expect(
        RecipeFileExportResult(.failure(error))
            == .failed(message: "External provider failed")
    )
}
