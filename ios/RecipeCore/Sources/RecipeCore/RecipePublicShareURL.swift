// Developer: gengyun
// Purpose: Reject non-public or malformed links before embedding them in shared QR codes.

import Foundation

public enum RecipePublicShareURL {
    public static func isValid(_ url: URL) -> Bool {
        // Terminal DNS dots disguise local hostnames; mapped IPv6 can contain IPv4 dots.
        guard
            url.scheme?.lowercased() == "https",
            let host = url.host?.lowercased(),
            host.contains("."),
            !host.hasSuffix("."),
            !host.contains(":"),
            host != "localhost",
            !host.hasSuffix(".local"),
            !host.allSatisfy({ $0.isNumber || $0 == "." }),
            url.user == nil,
            url.password == nil,
            url.port == nil,
            url.query == nil,
            url.fragment == nil
        else {
            return false
        }

        let segments = url.path.split(separator: "/")
        guard segments.count == 2, segments[0] == "r" else {
            return false
        }
        let slug = segments[1]
        let safe = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
        )

        return (8...128).contains(slug.count)
            && slug.unicodeScalars.allSatisfy { safe.contains($0) }
            && URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath
                == "/r/\(slug)"
    }
}
