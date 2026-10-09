// Developer: gengyun
// Purpose: Creates isolated deterministic DEBUG fixtures for app performance profiling.

#if DEBUG
    import CoreGraphics
    import Foundation
    import OSLog
    import RecipeCore
    import UIKit

    struct RecipePerformanceFixtureConfiguration {
        static let launchArgument = "--uitesting-performance-fixtures"
        static let resetArgument = "--uitesting-performance-reset"
        static let seedPrefix = "--uitesting-performance-seed="
        static let countPrefix = "--uitesting-performance-count="
        static let collectionsPrefix = "--uitesting-performance-collections="
        static let coversPrefix = "--uitesting-performance-covers="

        let seed: UInt64
        let recipeCount: Int
        let collectionCount: Int
        let includesCovers: Bool

        static func isRequested(arguments: [String]) -> Bool {
            return arguments.contains("--uitesting")
                && arguments.contains(launchArgument)
        }

        static func parse(arguments: [String]) -> Self? {
            guard isRequested(arguments: arguments) else {
                return nil
            }
            let seedValue: UInt64
            if let seedArgument = arguments.first(where: {
                $0.hasPrefix(seedPrefix)
            }) {
                guard let parsedSeed = UInt64(seedArgument.dropFirst(seedPrefix.count)) else {
                    return nil
                }
                seedValue = parsedSeed
            } else {
                seedValue = 137
            }
            let countArgument = arguments.first { argument in
                argument.hasPrefix(countPrefix)
            }
            let count = countArgument.flatMap { argument in
                Int(argument.dropFirst(countPrefix.count))
            }
            guard let count, [500, 1_000, 5_000].contains(count) else {
                return nil
            }
            let collectionsArgument = arguments.first { argument in
                argument.hasPrefix(collectionsPrefix)
            }
            let collectionCount = collectionsArgument.flatMap { argument in
                Int(argument.dropFirst(collectionsPrefix.count))
            } ?? 10
            guard [10, 100].contains(collectionCount) else {
                return nil
            }
            let coversArgument = arguments.first { argument in
                argument.hasPrefix(coversPrefix)
            }
            let coverMode = coversArgument.map { argument in
                String(argument.dropFirst(coversPrefix.count))
            } ?? "with"
            guard coverMode == "with" || coverMode == "without" else {
                return nil
            }
            return Self(
                seed: seedValue,
                recipeCount: count,
                collectionCount: collectionCount,
                includesCovers: coverMode == "with"
            )
        }

        var fileURL: URL {
            URL.applicationSupportDirectory
                .appending(
                    path:
                        "RecipeUITestPerformance/seed-\(seed)/count-\(recipeCount)/collections-\(collectionCount)/covers-\(includesCovers ? "with" : "without")/library.json"
                )
        }

        @MainActor
        func makeStore(arguments: [String]) throws -> RecipeStore {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if arguments.contains(Self.resetArgument),
                fileManager.fileExists(atPath: fileURL.path)
            {
                try fileManager.removeItem(at: fileURL)
            }

            let store = RecipeStore(fileURL: fileURL)
            guard store.loadError == nil else {
                throw RecipeStoreError.unreadableLibrary(
                    store.loadError ?? "Unknown error"
                )
            }
            if fileManager.fileExists(atPath: fileURL.path) {
                guard store.recipes.count == recipeCount,
                    store.recipes.first?.id == Self.recipeID(seed: seed, index: 0),
                    store.recipes.last?.id == Self.recipeID(seed: seed, index: recipeCount - 1)
                else {
                    throw RecipeStoreError.invalidValue(
                        "The performance fixture does not match its seed and count. "
                            + "Relaunch with \(Self.resetArgument) to recreate it."
                    )
                }
            } else {
                try store.replaceLibrary(
                    with: Self.snapshot(
                        seed: seed,
                        recipeCount: recipeCount,
                        collectionCount: collectionCount,
                        includesCovers: includesCovers
                    )
                )
            }
            return store
        }

        @MainActor
        static func snapshot(
            seed: UInt64,
            recipeCount: Int,
            collectionCount: Int = 10,
            includesCovers: Bool = true
        ) -> RecipeLibrarySnapshot {
            var generator = FixtureGenerator(seed: seed)
            let baseDate = Date(timeIntervalSince1970: 1_750_000_000)
            let collections = (0..<collectionCount).map { index in
                RecipeCollection(
                    id: recipeID(seed: seed, index: 10_000 + index),
                    name: "Collection \(index + 1)",
                    createdAt: baseDate,
                    updatedAt: baseDate
                )
            }
            let recipes = (0..<recipeCount).map { index in
                let id = recipeID(seed: seed, index: index)
                let ingredients = (0..<6).map { ingredientIndex in
                    RecipeIngredient(
                        id: recipeID(seed: seed, index: 20_000 + index * 6 + ingredientIndex),
                        name: "Ingredient \(generator.next() % 500)",
                        amountText: "\(1 + generator.next() % 4) cups",
                        category: [
                            .produce,
                            .proteins,
                            .dairy,
                            .pantry,
                            .other,
                        ][ingredientIndex % 5]
                    )
                }
                let steps = (0..<4).map { stepIndex in
                    RecipeStep(
                        id: recipeID(seed: seed, index: 50_000 + index * 4 + stepIndex),
                        title: "Step \(stepIndex + 1)",
                        instruction:
                            "Prepare recipe \(index + 1) using method \(generator.next() % 20)."
                    )
                }
                return Recipe(
                    id: id,
                    title: "Recipe \(String(format: "%05d", index + 1))",
                    summary: "Deterministic performance fixture \(generator.next())",
                    category: RecipeCategory.allCases[index % RecipeCategory.allCases.count],
                    servings: 2 + Int(generator.next() % 6),
                    prepMinutes: 5 + Int(generator.next() % 45),
                    cookMinutes: 5 + Int(generator.next() % 90),
                    ingredients: ingredients,
                    steps: steps,
                    coverData: includesCovers ? Self.fixtureCoverData : nil,
                    isFavorite: generator.next().isMultiple(of: 4),
                    notes: "Synthetic fixture; seed \(seed), item \(index).",
                    createdAt: baseDate.addingTimeInterval(TimeInterval(index)),
                    updatedAt: baseDate.addingTimeInterval(TimeInterval(index))
                )
            }
            let memberships = recipes.enumerated().flatMap { index, recipe in
                [index % collectionCount, (index * 7 + 3) % collectionCount].map {
                    collectionIndex in
                    RecipeCollectionMembership(
                        recipeID: recipe.id, collectionID: collections[collectionIndex].id)
                }
            }
            let groceries = (0..<300).map { index in
                GroceryItem(
                    id: recipeID(seed: seed, index: 80_000 + index),
                    name: "Grocery \(index + 1)",
                    amountText: "\(index % 5 + 1) items",
                    category: GroceryCategory.allCases[index % GroceryCategory.allCases.count],
                    isChecked: index.isMultiple(of: 3),
                    recipeIDs: recipes.isEmpty ? [] : [recipes[index % recipes.count].id]
                )
            }
            let mealPlan = (0..<90).map { index in
                MealPlanEntry(
                    id: recipeID(seed: seed, index: 90_000 + index),
                    recipeID: recipes[index % recipes.count].id,
                    date: baseDate.addingTimeInterval(TimeInterval(index * 86_400)),
                    slot: MealSlot.allCases[index % MealSlot.allCases.count]
                )
            }
            return RecipeLibrarySnapshot(
                recipes: recipes,
                groceries: groceries,
                mealPlan: mealPlan,
                collections: collections,
                collectionMemberships: memberships
            )
        }

        static func recipeID(seed: UInt64, index: Int) -> UUID {
            var generator = FixtureGenerator(seed: seed ^ UInt64(index) &* 0x9E37_79B9_7F4A_7C15)
            let bytes = (0..<16).map { _ in
                UInt8(truncatingIfNeeded: generator.next())
            }
            return UUID(
                uuid: (
                    bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                    bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14],
                    bytes[15]
                ))
        }

        @MainActor
        private static let fixtureCoverData: Data = {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512))
            let image = renderer.image { context in
                for row in 0..<16 {
                    for column in 0..<16 {
                        let value = CGFloat((row * 17 + column * 29) % 255) / 255
                        UIColor(red: value, green: 0.3, blue: 1 - value, alpha: 1).setFill()
                        context.cgContext.fill(
                            CGRect(x: column * 32, y: row * 32, width: 32, height: 32))
                    }
                }
            }
            guard let data = image.jpegData(compressionQuality: 0.82) else {
                preconditionFailure("The deterministic performance cover could not be encoded.")
            }
            return data
        }()
    }

    private struct FixtureGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            if seed == 0 {
                state = 0xA076_1D64_78BD_642F
            } else {
                state = seed
            }
        }

        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    @MainActor
    enum RecipePerformanceSignposts {
        private static let signposter = OSSignposter(
            subsystem: "com.shopkivoo.recipe",
            category: "Performance"
        )

        static var isEnabled: Bool {
            RecipePerformanceFixtureConfiguration.isRequested(
                arguments: ProcessInfo.processInfo.arguments
            )
        }

        static func measure<Value>(
            _ name: StaticString,
            _ operation: () throws -> Value
        ) rethrows -> Value {
            guard isEnabled else {
                return try operation()
            }
            return try signposter.withIntervalSignpost(
                name,
                id: signposter.makeSignpostID(),
                around: operation
            )
        }

        private static var libraryScrollInterval: OSSignpostIntervalState?

        static func setLibraryScrollActive(_ isActive: Bool) {
            guard isEnabled else {
                return
            }
            if isActive, libraryScrollInterval == nil {
                let id = signposter.makeSignpostID()
                libraryScrollInterval = signposter.beginInterval("Library Scroll", id: id)
            } else if !isActive, let interval = libraryScrollInterval {
                signposter.endInterval("Library Scroll", interval)
                libraryScrollInterval = nil
            }
        }
    }
#else
    import Foundation
    import RecipeCore

    struct RecipePerformanceFixtureConfiguration {
        static func isRequested(arguments: [String]) -> Bool {
            return false
        }

        static func parse(arguments: [String]) -> Self? {
            return nil
        }

        @MainActor
        func makeStore(arguments: [String]) throws -> RecipeStore {
            return RecipeStore(fileURL: nil)
        }
    }

    @MainActor
    enum RecipePerformanceSignposts {
        static func measure<Value>(
            _ name: StaticString,
            _ operation: () throws -> Value
        ) rethrows -> Value {
            try operation()
        }

        static func setLibraryScrollActive(_ isActive: Bool) {
            return
        }
    }
#endif
