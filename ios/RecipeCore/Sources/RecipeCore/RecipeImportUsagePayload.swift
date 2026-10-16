// Developer: gengyun
// Purpose: Canonicalizes the raw owned-job `result` JSON for payload-hash verification against the server.

import CryptoKit
import Foundation

/// Extracts the raw `result` value from the import job response body and returns the canonical
/// key-sorted SHA-256 that matches the server's `canonicalJSON(job.result)`. The raw scalar tokens
/// (numbers, strings, null, booleans) are preserved verbatim because the worker already emits
/// `JSON.stringify`-formatted JSON; only object key order is normalized. Returns `nil` when the
/// response has no non-null `result`.
public enum RecipeImportUsagePayload {
    public enum PayloadError: Error, Equatable {
        case malformed
    }

    public static func canonicalResultHash(responseBody: Data) throws -> String? {
        let text = String(decoding: responseBody, as: UTF8.self)
        var parser = Parser(text)
        guard let canonical = try parser.canonicalResultValue() else {
            return nil
        }
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private struct Parser {
        private let chars: [Character]
        private var index: Int

        init(_ text: String) {
            self.chars = Array(text)
            self.index = 0
        }

        // MARK: - Top level

        /// Scans the top-level object for the `result` key and returns its canonical form, or nil when
        /// the key is absent or its value is JSON null.
        mutating func canonicalResultValue() throws -> String? {
            skipWhitespace()
            guard peek() == "{" else { return nil }
            _ = try consume("{")
            skipWhitespace()
            if peek() == "}" {
                _ = try consume("}")
                return nil
            }
            while true {
                skipWhitespace()
                let rawKey = try readString()
                let key = Self.decode(rawKey)
                skipWhitespace()
                guard peek() == ":" else { throw PayloadError.malformed }
                _ = try consume(":")
                skipWhitespace()
                if key == "result" {
                    let value = try canonicalValue()
                    return value
                } else {
                    try skipValue()
                }
                skipWhitespace()
                if peek() == "," {
                    _ = try consume(",")
                    continue
                }
                if peek() == "}" {
                    _ = try consume("}")
                    return nil
                }
                throw PayloadError.malformed
            }
        }

        // MARK: - Values

        /// Returns the canonical form of the next value; JSON null returns nil.
        private mutating func canonicalValue() throws -> String? {
            skipWhitespace()
            guard let c = peek() else { throw PayloadError.malformed }
            switch c {
            case "{":
                return try canonicalObject()
            case "[":
                return try canonicalArray()
            case "\"":
                return try readString()
            case "n":
                return try readLiteral("null").map { _ in nil }
            case "t":
                return try readLiteral("true")
            case "f":
                return try readLiteral("false")
            default:
                return try readScalar()
            }
        }

        private mutating func canonicalObject() throws -> String {
            _ = try consume("{")
            skipWhitespace()
            var pairs: [(rawKey: String, value: String)] = []
            if peek() == "}" {
                _ = try consume("}")
                return "{}"
            }
            while true {
                skipWhitespace()
                let rawKey = try readString()
                skipWhitespace()
                guard peek() == ":" else { throw PayloadError.malformed }
                _ = try consume(":")
                skipWhitespace()
                let value = try canonicalValue() ?? "null"
                pairs.append((rawKey, value))
                skipWhitespace()
                if peek() == "," {
                    _ = try consume(",")
                    continue
                }
                if peek() == "}" {
                    _ = try consume("}")
                    break
                }
                throw PayloadError.malformed
            }
            pairs.sort { Self.decode($0.rawKey) < Self.decode($1.rawKey) }
            return "{" + pairs.map { $0.rawKey + ":" + $0.value }.joined(separator: ",") + "}"
        }

        private mutating func canonicalArray() throws -> String {
            _ = try consume("[")
            skipWhitespace()
            var items: [String] = []
            if peek() == "]" {
                _ = try consume("]")
                return "[]"
            }
            while true {
                skipWhitespace()
                items.append(try canonicalValue() ?? "null")
                skipWhitespace()
                if peek() == "," {
                    _ = try consume(",")
                    continue
                }
                if peek() == "]" {
                    _ = try consume("]")
                    break
                }
                throw PayloadError.malformed
            }
            return "[" + items.joined(separator: ",") + "]"
        }

        // MARK: - Scalars

        /// Reads a JSON string token verbatim (including the surrounding quotes and escapes).
        private mutating func readString() throws -> String {
            skipWhitespace()
            guard peek() == "\"" else { throw PayloadError.malformed }
            let start = index
            _ = try consume("\"")
            var escaped = false
            while true {
                guard let c = peek() else { throw PayloadError.malformed }
                _ = try consume(String(c))
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    break
                }
            }
            return String(chars[start..<index])
        }

        /// Reads a number token (or any bare scalar) verbatim.
        private mutating func readScalar() throws -> String {
            skipWhitespace()
            let start = index
            while let c = peek(), !c.isWhitespace, c != ",", c != "}", c != "]" {
                _ = try consume(String(c))
            }
            guard index > start else { throw PayloadError.malformed }
            return String(chars[start..<index])
        }

        private mutating func readLiteral(_ literal: String) throws -> String {
            skipWhitespace()
            let start = index
            for ch in literal {
                guard peek() == ch else { throw PayloadError.malformed }
                _ = try consume(String(ch))
            }
            return String(chars[start..<index])
        }

        /// Skips an arbitrary JSON value without canonicalizing it.
        private mutating func skipValue() throws {
            skipWhitespace()
            guard let c = peek() else { throw PayloadError.malformed }
            switch c {
            case "{":
                _ = try canonicalObject()
            case "[":
                _ = try canonicalArray()
            case "\"":
                _ = try readString()
            case "t", "f":
                _ = try readLiteral(c == "t" ? "true" : "false")
            case "n":
                _ = try readLiteral("null")
            default:
                _ = try readScalar()
            }
        }

        // MARK: - Helpers

        private func peek() -> Character? {
            index < chars.count ? chars[index] : nil
        }

        private mutating func consume(_ expected: Character) throws -> Character {
            guard let c = peek(), c == expected else { throw PayloadError.malformed }
            index += 1
            return c
        }

        private mutating func consume(_ expected: String) throws -> String {
            let start = index
            for ch in expected {
                _ = try consume(ch)
            }
            return String(chars[start..<index])
        }

        private mutating func skipWhitespace() {
            while let c = peek(), c == " " || c == "\n" || c == "\t" || c == "\r" {
                index += 1
            }
        }

        /// Decodes a JSON string token to its plain text for key comparison (worker keys are ASCII).
        private static func decode(_ token: String) -> String {
            var result = ""
            var i = token.startIndex
            let end = token.endIndex
            if i < end && token[i] == "\"" { i = token.index(after: i) }
            while i < end {
                let c = token[i]
                if c == "\\" {
                    let next = token.index(after: i)
                    if next < end {
                        let esc = token[next]
                        if esc == "u" {
                            let hexStart = token.index(after: next)
                            let hexEnd = token.index(hexStart, offsetBy: 4, limitedBy: end) ?? end
                            if hexEnd <= end, let scalar = UInt32(token[hexStart..<hexEnd], radix: 16),
                                let unicode = UnicodeScalar(scalar)
                            {
                                result.unicodeScalars.append(unicode)
                                i = hexEnd
                                continue
                            }
                        }
                        switch esc {
                        case "n": result.append("\n")
                        case "t": result.append("\t")
                        case "r": result.append("\r")
                        case "b": result.append("\u{08}")
                        case "f": result.append("\u{0C}")
                        default: result.append(esc)
                        }
                        i = token.index(after: next)
                        continue
                    }
                }
                if c == "\"" { break }
                result.append(c)
                i = token.index(after: i)
            }
            return result
        }
    }
}
