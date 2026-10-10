// Developer: gengyun
// Purpose: Locate only evidence-backed recipe parameters inside original step instructions.

import Foundation

/// This is a presentation hint, not a change to the original recipe text.
public enum RecipeInstructionParameter: Hashable, Sendable {
    case ingredient(UUID)
    case temperature
    case timer(UUID)
}

public struct RecipeInstructionSpan: Equatable, Sendable {
    public let text: String
    public let parameter: RecipeInstructionParameter?

    public init(text: String, parameter: RecipeInstructionParameter? = nil) {
        self.text = text
        self.parameter = parameter
    }
}

public enum RecipeInstructionParameterSpans {
    private struct Match {
        let range: Range<String.Index>
        let parameter: RecipeInstructionParameter
    }

    private static let durationPattern = try? NSRegularExpression(
        pattern: #"(?<![\d.,])([1-9][0-9]{0,4})\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?)\b"#,
        options: .caseInsensitive
    )

    /// Preserve every original character, including emoji and complex Unicode.
    /// Large or ambiguous instructions remain plain text instead of guessing.
    public static func spans(
        for step: RecipeStep,
        ingredients: [RecipeIngredient]
    ) -> [RecipeInstructionSpan] {
        let source = step.instruction
        guard !source.isEmpty,
            source.utf16.count <= 4_096,
            step.linkedIngredientIDs.count <= 64,
            step.timers.count <= 16
        else {
            return [RecipeInstructionSpan(text: source)]
        }

        var matches: [Match] = []
        let linkedIDs = Set(step.linkedIngredientIDs)
        let linked = ingredients.filter { linkedIDs.contains($0.id) }
        let byName = Dictionary(grouping: linked) {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive],
                         locale: Locale(identifier: "en_US_POSIX"))
        }

        for ingredientsWithName in byName.values where ingredientsWithName.count == 1 {
            guard let ingredient = ingredientsWithName.first else { continue }
            let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 100 else { continue }
            for range in literalRanges(of: name, in: source) {
                matches.append(Match(range: range, parameter: .ingredient(ingredient.id)))
            }
        }

        if let temperature = step.temperature?.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !temperature.isEmpty, temperature.count <= 100 {
            for range in literalRanges(of: temperature, in: source) {
                matches.append(Match(range: range, parameter: .temperature))
            }
        }

        if let pattern = durationPattern {
            let full = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in pattern.matches(in: source, range: full) {
                guard let range = Range(match.range, in: source),
                    let countRange = Range(match.range(at: 1), in: source),
                    let unitRange = Range(match.range(at: 2), in: source),
                    !isApproximateOrRangePrefix(source[..<range.lowerBound]),
                    let count = Int(source[countRange])
                else { continue }

                let unit = source[unitRange].lowercased()
                let multiplier: Int
                if unit.hasPrefix("sec") {
                    multiplier = 1
                } else if unit.hasPrefix("min") {
                    multiplier = 60
                } else {
                    multiplier = 3_600
                }
                let (duration, overflow) = count.multipliedReportingOverflow(by: multiplier)
                guard !overflow else { continue }
                let timers = step.timers.filter { $0.durationSeconds == duration }
                guard timers.count == 1, let timer = timers.first else { continue }
                matches.append(Match(range: range, parameter: .timer(timer.id)))
            }
        }

        // Overlapping links are ambiguous (e.g. "salt" inside "sea salt").
        // Keep both as plain source text; unaffected tokens can still be tapped.
        let nonOverlapping = matches.enumerated().compactMap { index, match -> Match? in
            let collision = matches.enumerated().contains { otherIndex, other in
                index != otherIndex
                    && match.range.lowerBound < other.range.upperBound
                    && other.range.lowerBound < match.range.upperBound
            }
            return collision ? nil : match
        }.sorted { $0.range.lowerBound < $1.range.lowerBound }

        var result: [RecipeInstructionSpan] = []
        var cursor = source.startIndex
        for match in nonOverlapping {
            guard match.range.lowerBound >= cursor else { continue }
            if cursor < match.range.lowerBound {
                result.append(RecipeInstructionSpan(
                    text: String(source[cursor..<match.range.lowerBound])
                ))
            }
            result.append(RecipeInstructionSpan(
                text: String(source[match.range]), parameter: match.parameter
            ))
            cursor = match.range.upperBound
        }
        if cursor < source.endIndex {
            result.append(RecipeInstructionSpan(text: String(source[cursor...])))
        }
        return result.isEmpty ? [RecipeInstructionSpan(text: source)] : result
    }

    private static func literalRanges(
        of needle: String,
        in source: String
    ) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var cursor = source.startIndex
        while cursor < source.endIndex, ranges.count < 16,
            let range = source.range(
                of: needle, options: .caseInsensitive,
                range: cursor..<source.endIndex
            ) {
            if hasWordBoundaries(range, in: source) {
                ranges.append(range)
            }
            cursor = range.upperBound
        }
        return ranges
    }

    /// ASCII identifiers need word boundaries. CJK text has no spaces between
    /// lexical units, so only explicit linked ingredient names are considered.
    private static func hasWordBoundaries(
        _ range: Range<String.Index>,
        in source: String
    ) -> Bool {
        guard range.lowerBound < range.upperBound else { return false }
        let first = source[range.lowerBound]
        let last = source[source.index(before: range.upperBound)]
        if isASCIIWord(first), range.lowerBound > source.startIndex,
            isASCIIWord(source[source.index(before: range.lowerBound)]) {
            return false
        }
        if isASCIIWord(last), range.upperBound < source.endIndex,
            isASCIIWord(source[range.upperBound]) {
            return false
        }
        return true
    }

    private static func isASCIIWord(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (48...57).contains(value) || (65...90).contains(value)
                || (97...122).contains(value)
        }
    }

    private static func isApproximateOrRangePrefix(
        _ prefix: Substring
    ) -> Bool {
        let lower = String(prefix.suffix(32)).lowercased()
        if ["about ", "around ", "roughly ", "approx ", "approximately ",
            "circa ", "to ", "or "].contains(where: lower.hasSuffix) {
            return true
        }
        guard let last = prefix.last(where: { !$0.isWhitespace }) else {
            return false
        }
        return last == "-" || last == "–" || last == "—" || last == "~"
    }
}
