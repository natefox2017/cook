// Developer: gengyun
// Purpose: Classifies a system document export completion without claiming a file was saved prematurely.

import Foundation

/// The document picker owns persistence; prepared export data is not a completed save.
public enum RecipeFileExportResult: Equatable {
    case saved(filename: String)
    case cancelled
    case failed(message: String)

    public init(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            self = .saved(filename: url.lastPathComponent)

        case .failure(let error):
            let cocoaError = error as NSError
            if cocoaError.domain == NSCocoaErrorDomain
                && cocoaError.code == CocoaError.Code.userCancelled.rawValue
            {
                self = .cancelled
            } else {
                self = .failed(message: error.localizedDescription)
            }
        }
    }
}
