// Developer: gengyun
// Purpose: Persist an independent crash-recovery barrier before local-only erasure.

import Foundation

/// Stored outside the Sync cache directory so cache cleanup cannot remove it.
/// An unreadable or unremovable marker fails closed: the app must not reuse an
/// old cloud sync base until a confirmed download or upload clears the marker.
public enum RecipeLocalEraseMarker {
    private static let signature = Data("RecipePouch.localErasePending.v1".utf8)

    public static func persist(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try signature.write(to: url, options: .atomic)

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
        guard try Data(contentsOf: url) == signature else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    public static func isPresent(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public static func clear(at url: URL) throws {
        if isPresent(at: url) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
