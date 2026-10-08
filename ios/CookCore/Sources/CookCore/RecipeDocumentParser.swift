import Foundation

/// Local document parsing only. This is not the backend's import-job/API model.
/// Shape coverage follows Schema.org Recipe and recipe-scrapers' schema approach.
public enum RecipeDocumentParser {
    public static let maximumTextCharacters = 100_000

    public static func recipe(inHTML html: String, sourceURL: URL) -> Recipe? {
        guard html.utf8.count <= 2_000_000 else { return nil }
        let pattern = #"<script\b[^>]*\btype\s*=\s*[\"']application/ld\+json[\"'][^>]*>([\s\S]*?)</script\s*>"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        for match in expression.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html),
                  let data = String(html[range]).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let object = findRecipe(json, depth: 0) else { continue }
            if let recipe = recipe(from: object, sourceURL: sourceURL) { return recipe }
        }
        return nil
    }

    /// Only explicit section headings structure pasted/OCR text. Unstructured text
    /// is retained as source evidence for editing, never replaced with made-up steps.
    public static func recipe(fromText text: String, title: String = "Imported recipe") -> Recipe {
        var result = Recipe(title: title, servings: nil, sourceText: text, sourceName: "Text import")
        // Keep all original evidence. A document beyond the bounded parser's
        // working limit stays incomplete instead of looking fully imported.
        guard text.count <= maximumTextCharacters else { return result }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var section = ""
        for raw in trimmed.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let heading = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":# "))
            if ["ingredients", "ingredient list", "食材", "材料"].contains(heading) { section = "ingredients"; continue }
            if ["instructions", "directions", "method", "steps", "步骤", "做法"].contains(heading) { section = "steps"; continue }
            if ["notes", "tips", "备注"].contains(heading) { section = "notes"; continue }
            switch section {
            case "ingredients": result.ingredients.append(ingredient(line))
            case "steps": result.steps.append(structuredStep(title: "", instruction: removingBullet(line)))
            case "notes": result.notes += (result.notes.isEmpty ? "" : "\n") + line
            default:
                if result.title == "Imported recipe", line.count < 120 { result.title = line }
            }
        }
        result.steps = enrichSteps(result.steps, ingredients: result.ingredients)
        return result
    }

    public static func validatedSourceURL(_ text: String) -> URL? {
        guard text.utf8.count <= 8_192,
              let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https",
              parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443,
              let host = parts.host?.lowercased(), host.contains("."),
              !host.contains(":"), !host.hasSuffix("."),
              !["localhost", "local", "localdomain", "internal", "intranet", "corp", "invalid", "test", "lan", "home", "onion"].contains(host.components(separatedBy: ".").last ?? ""),
              host != "home.arpa", !host.hasSuffix(".home.arpa"),
              !host.allSatisfy({ $0.isNumber || $0 == "." }),
              !looksLikeIPv4Literal(host),
              !host.contains("%"), !host.contains("\\"),
              let url = parts.url else { return nil }
        return url
    }

    public static func sourceKey(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        parts.fragment = nil
        if parts.path.isEmpty { parts.path = "/" }
        return parts.string ?? url.absoluteString
    }

    private static func looksLikeIPv4Literal(_ host: String) -> Bool {
        // IPv4 parsers can accept hexadecimal components as well as decimal
        // and octal forms. These are address literals, even when they contain x.
        host.range(
            of: #"^(?:0x[0-9a-f]+|[0-9]+)(?:\.(?:0x[0-9a-f]+|[0-9]+)){0,3}$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func findRecipe(_ value: Any, depth: Int) -> [String: Any]? {
        guard depth < 24 else { return nil }
        if let array = value as? [Any] {
            return array.lazy.compactMap { findRecipe($0, depth: depth + 1) }.first
        }
        guard let object = value as? [String: Any] else { return nil }
        let types = (object["@type"] as? [String]) ?? [object["@type"] as? String ?? ""]
        if types.contains(where: { $0.components(separatedBy: "/").last?.lowercased() == "recipe" }),
           !clean(object["name"] as? String ?? "").isEmpty { return object }
        if let graph = object["@graph"], let recipe = findRecipe(graph, depth: depth + 1) { return recipe }
        if let main = object["mainEntity"], let recipe = findRecipe(main, depth: depth + 1) { return recipe }
        return nil
    }

    private static func recipe(from json: [String: Any], sourceURL: URL) -> Recipe? {
        let name = clean(json["name"] as? String ?? "")
        guard !name.isEmpty else { return nil }
        let rawIngredients = (json["recipeIngredient"] as? [String]) ?? []
        let ingredients = rawIngredients.prefix(250).map(ingredient)
        let steps = enrichSteps(Array(stepList(json["recipeInstructions"], depth: 0).prefix(250)), ingredients: ingredients)
        let author = (json["author"] as? String)
            ?? (json["author"] as? [String: Any])?["name"] as? String
            ?? (json["author"] as? [[String: Any]])?.first?["name"] as? String
        var recipe = Recipe(
            title: name, summary: clean(json["description"] as? String ?? ""),
            servings: servings(json["recipeYield"]),
            prepMinutes: minutes(json["prepTime"] as? String),
            cookMinutes: minutes(json["cookTime"] as? String),
            ingredients: ingredients,
            steps: steps, sourceURL: sourceURL.absoluteString,
            sourceText: "Ingredients\n" + rawIngredients.joined(separator: "\n") + "\nInstructions\n" + steps.map(\.instruction).joined(separator: "\n"),
            sourceName: clean(author ?? sourceURL.host() ?? "Recipe website")
        )
        if recipe.prepMinutes == nil && recipe.cookMinutes == nil { recipe.cookMinutes = minutes(json["totalTime"] as? String) }
        let category = (json["recipeCategory"] as? String ?? "").lowercased()
        if category.contains("breakfast") { recipe.category = .breakfast }
        else if category.contains("dessert") { recipe.category = .desserts }
        else if category.contains("drink") { recipe.category = .drinks }
        else if category.contains("side") { recipe.category = .sides }
        return recipe
    }

    private static func stepList(_ value: Any?, depth: Int) -> [RecipeStep] {
        guard depth < 24 else { return [] }
        if let text = value as? String {
            return text.components(separatedBy: .newlines).map(clean).filter { !$0.isEmpty }.map { structuredStep(title: "", instruction: removingBullet($0)) }
        }
        if let values = value as? [Any] { return values.flatMap { stepList($0, depth: depth + 1) } }
        guard let object = value as? [String: Any] else { return [] }
        if let children = object["itemListElement"] { return stepList(children, depth: depth + 1) }
        let text = clean(object["text"] as? String ?? object["name"] as? String ?? "")
        guard !text.isEmpty else { return [] }
        return [structuredStep(title: clean(object["name"] as? String ?? ""), instruction: text)]
    }


    private static func structuredStep(title: String, instruction: String) -> RecipeStep {
        let cleanedTitle = clean(title)
        let cleanedInstruction = clean(instruction)
        return RecipeStep(
            title: cleanedTitle,
            instruction: cleanedInstruction,
            temperature: temperature(in: cleanedInstruction),
            timers: timerCandidates(in: cleanedInstruction, stepTitle: cleanedTitle)
        )
    }

    private static func enrichSteps(_ steps: [RecipeStep], ingredients: [RecipeIngredient]) -> [RecipeStep] {
        steps.map { step in
            var updated = step
            let haystack = normalizedWords(step.instruction)
            updated.linkedIngredientIDs = ingredients.compactMap { ingredient in
                let needle = normalizedWords(ingredient.name)
                let meaningfulLength = needle.trimmingCharacters(in: .whitespacesAndNewlines).count
                guard meaningfulLength >= 3, haystack.contains(needle) else { return nil }
                return ingredient.id
            }
            return updated
        }
    }

    private static func normalizedWords(_ text: String) -> String {
        " " + text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) + " "
    }

    private static func timerCandidates(in text: String, stepTitle: String) -> [RecipeStepTimer] {
        let pattern = #"\b(\d{1,3})\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var timers: [RecipeStepTimer] = []

        for match in matches {
            guard let fullRange = Range(match.range(at: 0), in: text),
                  let valueRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let value = Int(text[valueRange]) else { continue }

            let before = fullRange.lowerBound > text.startIndex ? text[text.index(before: fullRange.lowerBound)] : " "
            let after = fullRange.upperBound < text.endIndex ? text[fullRange.upperBound] : " "
            if "-–—".contains(before) || "-–—".contains(after) { continue }

            let unit = text[unitRange].lowercased()
            let seconds: Int
            if unit.hasPrefix("hour") || unit.hasPrefix("hr") {
                seconds = value * 3_600
            } else if unit.hasPrefix("second") || unit.hasPrefix("sec") {
                seconds = value
            } else {
                seconds = value * 60
            }
            guard seconds > 0, seconds <= 43_200 else { continue }

            let sourceLabel = String(text[fullRange])
            let base = stepTitle.isEmpty ? "Step timer" : stepTitle
            let label = matches.count > 1 ? "\(base) · \(sourceLabel)" : base
            timers.append(RecipeStepTimer(label: label, durationSeconds: seconds))
        }
        return timers
    }

    private static func temperature(in text: String) -> CookingTemperature? {
        let patterns = [
            #"\b\d{2,3}\s*°?\s*[CF]\b"#,
            #"\b(?:low|medium-low|medium|medium-high|high)\s+heat\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 0), in: text) else { continue }
            return CookingTemperature(text: String(text[range]))
        }
        return nil
    }

    private static func ingredient(_ raw: String) -> RecipeIngredient {
        let line = removingBullet(clean(raw))
        // Separate only an explicit amount + recognized unit + ingredient name.
        // Other sentences remain verbatim, including qualitative amounts/ranges.
        let pattern = #"^((?:(?:\d+\s+)?\d+/\d+|\d+(?:\.\d+)?|[¼½¾⅛⅜⅝⅞]))\s+(g|kg|mg|ml|l|oz|lb|lbs|cups?|tbsp|tsp|tablespoons?|teaspoons?|cloves?)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let number = Range(match.range(at: 1), in: line),
              let unit = Range(match.range(at: 2), in: line),
              let name = Range(match.range(at: 3), in: line) else { return RecipeIngredient(name: line) }
        return .from(name: String(line[name]), amountText: String(line[number]) + " " + String(line[unit]))
    }

    private static func servings(_ value: Any?) -> Int? {
        if let values = value as? [Any] { return values.lazy.compactMap { servings($0) }.first }
        if let number = value as? Int, (1...100).contains(number) { return number }
        guard let text = value as? String,
              let regex = try? NSRegularExpression(pattern: #"^\s*(\d{1,3})\s*(?:servings?|portions?|people)?\s*$"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let result = Int(text[range]), (1...100).contains(result) else { return nil }
        return result
    }

    private static func minutes(_ value: String?) -> Int? {
        guard let value, let regex = try? NSRegularExpression(pattern: #"^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$"#),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        var parts: [Int] = []
        for index in 1...3 {
            let matchedRange = match.range(at: index)
            if matchedRange.location == NSNotFound {
                parts.append(0)
                continue
            }
            guard let range = Range(matchedRange, in: value),
                  let number = Int(value[range]), number <= 10_000 else { return nil }
            parts.append(number)
        }
        let seconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
        guard seconds > 0, seconds <= 7 * 24 * 3600 else { return nil }
        return (seconds + 59) / 60
    }

    private static func removingBullet(_ text: String) -> String {
        text.replacingOccurrences(of: #"^\s*(?:[-*•]\s+|\d+[.)]\s+)"#, with: "", options: .regularExpression)
    }

    private static func clean(_ text: String) -> String {
        var value = text.replacingOccurrences(of: #"<br\s*/?>|</p>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, character) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            value = value.replacingOccurrences(of: entity, with: character)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
