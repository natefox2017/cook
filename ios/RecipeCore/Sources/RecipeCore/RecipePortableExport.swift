// Developer: gengyun
// Purpose: Exports private RecipePouch recipes to portable, versioned JSON and safe offline HTML.

import Foundation

/// A recipe-only export format, not an importable device backup.
public struct RecipePortableArchive: Codable, Sendable {
    public let format: String
    public let version: Int
    public let exportedAt: Date
    public let recipes: [Recipe]
    public let collections: [RecipeCollection]
    public let collectionMemberships: [RecipeCollectionMembership]

    public init(
        exportedAt: Date,
        recipes: [Recipe],
        collections: [RecipeCollection],
        collectionMemberships: [RecipeCollectionMembership]
    ) {
        self.format = "recipepouch.recipes"
        self.version = 1
        self.exportedAt = exportedAt
        self.recipes = recipes
        self.collections = collections
        self.collectionMemberships = collectionMemberships
    }
}

public enum RecipePortableExport {
    public static func json(
        snapshot: RecipeLibrarySnapshot,
        exportedAt: Date = .now
    ) throws -> Data {
        let archive = RecipePortableArchive(
            exportedAt: exportedAt,
            recipes: sortedRecipes(snapshot.recipes).map { recipe in
                // Portable JSON intentionally excludes image bytes and bundled
                // asset references; the full-library export remains unchanged.
                var portable = recipe
                portable.coverData = nil
                portable.coverAsset = nil
                return portable
            },
            collections: snapshot.collections.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            },
            collectionMemberships: snapshot.collectionMemberships.sorted {
                let lhs = $0.collectionID.uuidString + ":" + $0.recipeID.uuidString
                let rhs = $1.collectionID.uuidString + ":" + $1.recipeID.uuidString
                return lhs < rhs
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    /// Produces one self-contained HTML file, readable offline in any browser.
    /// User text is escaped and image attachments are intentionally excluded.
    public static func html(
        snapshot: RecipeLibrarySnapshot,
        exportedAt: Date = .now
    ) -> Data {
        let recipes = sortedRecipes(snapshot.recipes)
        let formatter = ISO8601DateFormatter()
        let dateText = escape(formatter.string(from: exportedAt))

        var lines: [String] = [
            "<!doctype html>",
            "<html lang=\"en\">",
            "<head>",
            "<meta charset=\"utf-8\">",
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
            "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'\">",
            "<title>RecipePouch Recipes</title>",
            """
            <style>
            body{font-family:system-ui,-apple-system,sans-serif;line-height:1.55;
            max-width:800px;margin:2rem auto;padding:0 1.2rem;color:#223128}
            h1,h2,h3{line-height:1.25}h1{color:#287a42}
            nav,article{border:1px solid #dfe8df;border-radius:14px;padding:1rem;margin:1rem 0}
            article{page-break-before:always}nav ol{columns:2}
            li{margin:.45rem 0}.muted{color:#57685c}.preserve{white-space:pre-wrap;overflow-wrap:anywhere}
            a{color:#287a42;overflow-wrap:anywhere}pre{white-space:pre-wrap;overflow-wrap:anywhere}
            @media(max-width:550px){nav ol{columns:1}}
            </style>
            """,
            "</head>",
            "<body>",
            "<h1>RecipePouch Recipes</h1>",
            "<p class=\"muted\">Exported \(dateText). Recipe text only; photos, attachments, shopping lists, meal plans and app preferences are not included.</p>"
        ]

        if recipes.isEmpty {
            lines.append("<p>No saved recipes in this export.</p>")
        } else {
            lines.append("<nav aria-label=\"Recipe index\"><h2>Recipes</h2><ol>")
            for (index, recipe) in recipes.enumerated() {
                lines.append(
                    "<li><a href=\"#recipe-\(index + 1)\">\(escape(recipe.title))</a></li>"
                )
            }
            lines.append("</ol></nav>")

            let collectionsByID = Dictionary(
                uniqueKeysWithValues: snapshot.collections.map { ($0.id, $0.name) }
            )
            // Reuse one membership index for every exported recipe instead
            // of repeatedly filtering the complete collection membership list.
            let collectionIndex = RecipeCollectionIndex(
                memberships: snapshot.collectionMemberships
            )
            for (index, recipe) in recipes.enumerated() {
                lines.append("<article id=\"recipe-\(index + 1)\">")
                lines.append("<h2>\(escape(recipe.title))</h2>")

                if !recipe.summary.isEmpty {
                    lines.append("<p class=\"preserve\">\(escape(recipe.summary))</p>")
                }

                var facts: [String] = [recipe.category.rawValue]
                if let servings = recipe.servings {
                    facts.append("\(servings) servings")
                }
                if let prep = recipe.prepMinutes {
                    facts.append("Prep: \(prep) minutes")
                }
                if let cook = recipe.cookMinutes {
                    facts.append("Cook: \(cook) minutes")
                }
                if recipe.isFavorite {
                    facts.append("Favorite")
                }
                lines.append("<p class=\"muted\">\(escape(facts.joined(separator: " · ")))</p>")

                let associatedIDs = collectionIndex.collectionIDs(forRecipe: recipe.id)
                let associatedNames = associatedIDs.compactMap { collectionsByID[$0] }
                    .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                if !associatedNames.isEmpty {
                    lines.append(
                        "<p><strong>Collections:</strong> \(escape(associatedNames.joined(separator: ", ")))</p>"
                    )
                }

                lines.append("<h3>Ingredients</h3><ul>")
                if recipe.ingredients.isEmpty {
                    lines.append("<li>Not specified</li>")
                }
                for ingredient in recipe.ingredients {
                    let amount = ingredient.amountText
                    let label = amount.isEmpty ? ingredient.name : amount + " — " + ingredient.name
                    lines.append("<li class=\"preserve\">\(escape(label))</li>")
                }
                lines.append("</ul>")

                lines.append("<h3>Steps</h3><ol>")
                if recipe.steps.isEmpty {
                    lines.append("<li>Not specified</li>")
                }
                for (stepIndex, step) in recipe.steps.enumerated() {
                    let title = step.title.isEmpty ? "Step \(stepIndex + 1)" : step.title
                    lines.append("<li><strong>\(escape(title))</strong>")
                    lines.append("<p class=\"preserve\">\(escape(step.instruction))</p>")
                    if let temperature = step.temperature, !temperature.text.isEmpty {
                        lines.append("<p>Temperature/heat: \(escape(temperature.text))</p>")
                    }
                    if !step.timers.isEmpty {
                        let timerLabels = step.timers.map {
                            "\($0.label): \($0.durationSeconds) seconds"
                        }
                        lines.append("<p>Timers: \(escape(timerLabels.joined(separator: ", ")))</p>")
                    }
                    lines.append("</li>")
                }
                lines.append("</ol>")

                if !recipe.notes.isEmpty {
                    lines.append("<h3>Notes</h3>")
                    lines.append("<p class=\"preserve\">\(escape(recipe.notes))</p>")
                }

                if let sourceName = recipe.sourceName, !sourceName.isEmpty {
                    lines.append("<p><strong>Source:</strong> \(escape(sourceName))</p>")
                }
                if let sourceURL = recipe.sourceURL, !sourceURL.isEmpty {
                    if safeHTTPSURL(sourceURL) {
                        lines.append(
                            "<p><strong>Original URL:</strong> <a href=\"\(escape(sourceURL))\" rel=\"noopener noreferrer\">\(escape(sourceURL))</a></p>"
                        )
                    } else {
                        // Never place untrusted URL schemes in clickable hrefs.
                        lines.append("<p><strong>Original URL:</strong> \(escape(sourceURL))</p>")
                    }
                }
                if let sourceText = recipe.sourceText, !sourceText.isEmpty {
                    lines.append("<h3>Original source text</h3>")
                    lines.append("<pre>\(escape(sourceText))</pre>")
                }
                lines.append("</article>")
            }
        }

        lines.append("</body></html>")
        return Data(lines.joined(separator: "\n").utf8)
    }

    private static func sortedRecipes(_ recipes: [Recipe]) -> [Recipe] {
        recipes.sorted {
            let comparison = $0.title.localizedStandardCompare($1.title)
            return comparison == .orderedSame
                ? $0.id.uuidString < $1.id.uuidString
                : comparison == .orderedAscending
        }
    }

    private static func safeHTTPSURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else {
            return false
        }
        return true
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
