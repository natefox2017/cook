// Developer: gengyun
// Purpose: Persists weekly meal-plan templates in an independent atomic JSON file, separate from the cloud library.

import Foundation
import Observation

@Observable @MainActor
public final class RecipeMealPlanTemplateStore {
    public private(set) var templates: [RecipeMealPlanTemplate] = []
    public private(set) var loadError: String?
    @ObservationIgnored private let fileURL: URL?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        reload()
    }

    public static func defaultFileURL() -> URL {
        let supportDirectory = URL.applicationSupportDirectory
        let recipeDirectory =
            supportDirectory
            .appendingPathComponent("Recipe", isDirectory: true)
        // Logical key `recipe.mealPlanTemplates.v1`; kept out of library.json so
        // templates never ride the cloud snapshot or its merge/tombstone protocol.
        return recipeDirectory.appendingPathComponent("mealPlanTemplates.v1.json")
    }

    public func template(id: UUID) -> RecipeMealPlanTemplate? {
        templates.first { $0.id == id }
    }

    @discardableResult
    public func saveTemplate(
        name: String,
        slots: [RecipeMealPlanTemplateSlot]
    ) throws -> RecipeMealPlanTemplate {
        let cleaned = try Self.validatedName(name)
        let validatedSlots = try Self.validatedSlots(slots)
        var next = templates
        let template = RecipeMealPlanTemplate(name: cleaned, slots: validatedSlots)
        next.append(template)
        next.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        try commit(next)
        return template
    }

    public func renameTemplate(id: UUID, name: String) throws {
        guard let index = templates.firstIndex(where: { $0.id == id }) else {
            throw RecipeMealPlanTemplateError.missingTemplate
        }
        let cleaned = try Self.validatedName(name)
        var next = templates
        next[index].name = cleaned
        next[index].updatedAt = .now
        next.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        try commit(next)
    }

    public func deleteTemplate(id: UUID) throws {
        guard templates.contains(where: { $0.id == id }) else {
            throw RecipeMealPlanTemplateError.missingTemplate
        }
        var next = templates
        next.removeAll { $0.id == id }
        try commit(next)
    }

    public func reload() {
        guard let fileURL else {
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let file = try JSONDecoder().decode(RecipeMealPlanTemplateFile.self, from: data)
            try Self.validate(file.templates)
            publish(file.templates)
            loadError = nil
        } catch {
            let cocoaError = error as NSError
            if cocoaError.domain == NSCocoaErrorDomain
                && cocoaError.code == NSFileReadNoSuchFileError
            {
                publish([])
                loadError = nil
            } else {
                // Preserve the original file and the last good in-memory data.
                loadError = error.localizedDescription
            }
        }
    }

    // MARK: - Private

    private func commit(_ next: [RecipeMealPlanTemplate]) throws {
        if let loadError {
            throw RecipeMealPlanTemplateError.unreadable(loadError)
        }
        try Self.validate(next)
        let data = try Self.encoded(RecipeMealPlanTemplateFile(templates: next))
        if let fileURL {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        }
        // Publish only after the full file is safely written, so an I/O failure
        // rolls back in-memory state rather than partially applying the change.
        publish(next)
    }

    private func publish(_ templates: [RecipeMealPlanTemplate]) {
        self.templates = templates
    }

    private static func validatedName(_ name: String) throws -> String {
        let cleaned =
            name
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw RecipeMealPlanTemplateError.emptyName
        }
        guard cleaned.count <= 80 else {
            throw RecipeMealPlanTemplateError.nameTooLong
        }
        return cleaned
    }

    private static func validatedSlots(
        _ slots: [RecipeMealPlanTemplateSlot]
    ) throws -> [RecipeMealPlanTemplateSlot] {
        guard !slots.isEmpty else {
            throw RecipeMealPlanTemplateError.emptyWeek
        }
        var keys: Set<String> = []
        for slot in slots {
            guard (0...6).contains(slot.relativeDayOffset) else {
                throw RecipeMealPlanTemplateError.invalidSlot
            }
            let key = "\(slot.relativeDayOffset):\(slot.mealSlot.rawValue)"
            guard keys.insert(key).inserted else {
                throw RecipeMealPlanTemplateError.invalidSlot
            }
        }
        return slots
    }

    private static func validate(_ templates: [RecipeMealPlanTemplate]) throws {
        for template in templates {
            guard !template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RecipeMealPlanTemplateError.emptyName
            }
            _ = try validatedSlots(template.slots)
        }
    }

    private static func encoded(_ file: RecipeMealPlanTemplateFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }
}
