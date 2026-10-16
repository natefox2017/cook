// Developer: gengyun
// Purpose: Computes the DEV-425 canonical input_hash so the iOS client matches the server recomputation exactly.

import CryptoKit
import Foundation

/// Canonical JSON serialization that mirrors `supabase/functions/_shared/canonicalJSON.ts` for the
/// bounded commercial usage domain: object keys sorted, array order preserved, JSON.stringify escaping.
enum RecipeCanonicalJSON {
    indirect enum Value {
        case null
        case bool(Bool)
        case string(String)
        case array([Value])
        case object([(key: String, value: Value)])
    }

    static func serialize(_ value: Value) -> String {
        switch value {
        case .null:
            return "null"
        case .bool(let flag):
            return flag ? "true" : "false"
        case .string(let text):
            return escaped(text)
        case .array(let items):
            return "[" + items.map(serialize).joined(separator: ",") + "]"
        case .object(let entries):
            let body = entries
                .sorted { $0.key < $1.key }
                .map { escaped($0.key) + ":" + serialize($0.value) }
                .joined(separator: ",")
            return "{" + body + "}"
        }
    }

    /// Matches JSON.stringify for the control characters used by the frozen wire domain.
    private static func escaped(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"":
                result += "\\\""
            case "\\":
                result += "\\\\"
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04X", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        result += "\""
        return result
    }
}

public enum RecipeUsageInputHash {
    /// input_hash = lowercase SHA-256 of canonicalJSON({capability, source}).
    /// The source always carries all five keys (nulls mark non-applicable fields) so this hash is
    /// immutable across reserve -> commit -> finalize, matching `recipeAccess.ts` `computeInputHash`.
    public static func compute(
        capability: RecipeCapability,
        source: RecipeUsageSource
    ) throws -> String {
        let object = RecipeCanonicalJSON.Value.object([
            ("capability", .string(capability.rawValue)),
            ("source", sourceValue(source)),
        ])
        let canonical = RecipeCanonicalJSON.serialize(object)
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func sourceValue(_ source: RecipeUsageSource) -> RecipeCanonicalJSON.Value {
        .object([
            (
                "candidate_ids",
                source.candidateIDs.map {
                    .array($0.map(RecipeCanonicalJSON.Value.string))
                } ?? .null
            ),
            ("job_id", source.jobID.map(RecipeCanonicalJSON.Value.string) ?? .null),
            ("origin", .string(source.origin.rawValue)),
            ("session_id", source.sessionID.map(RecipeCanonicalJSON.Value.string) ?? .null),
            (
                "turn_request_id",
                source.turnRequestID.map(RecipeCanonicalJSON.Value.string) ?? .null
            ),
        ])
    }
}
