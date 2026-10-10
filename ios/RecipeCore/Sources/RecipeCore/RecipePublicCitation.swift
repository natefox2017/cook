// Developer: gengyun
// Purpose: Exclude private, credentialed or token-bearing source links from public recipe shares.

import Foundation

public enum RecipePublicCitation {
    /// A source link is optional in a public snapshot. When the URL is uncertain,
    /// omit its public copy; the private recipe keeps the complete original.
    public static func eligibleURL(_ original: String?) -> String? {
        guard let original,
              original.count <= 2_048,
              !original.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }),
              let components = URLComponents(string: original),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              host.contains("."),
              !host.hasSuffix(".local"),
              !host.contains(":"),
              host.unicodeScalars.contains(where: {
                  CharacterSet.letters.contains($0)
              }),
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil
        else {
            return nil
        }

        // Unknown query parameters may carry access grants or user identifiers.
        // Only common public recipe/video lookup keys are safe to reproduce.
        let publicLookupKeys: Set<String> = ["v", "p", "id"]
        guard (components.queryItems ?? []).allSatisfy({
            publicLookupKeys.contains($0.name.lowercased())
        }) else {
            return nil
        }

        return original
    }
}
