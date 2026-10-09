// Developer: gengyun
// Purpose: Measures local RecipeStore write and recipe-search latency at fixed library sizes.

import Foundation

@main
struct RecipeStoreBenchmark {
    private static let sizes = [100, 1_000, 5_000]
    private static let writeSamples = 21
    private static let searchSamples = 21
    private static let coverBytes = 16 * 1_024

    @MainActor
    static func main() throws {
        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        print("Recipes | Cover | File MiB | Write p50 ms | Write p95 ms | Search p50 ms | Search p95 ms")
        for count in sizes {
            for hasCover in [false, true] {
                let fileURL = outputDirectory
                    .appendingPathComponent("\(count)-\(hasCover).json")
                let recipes = fixture(count: count, hasCover: hasCover)
                let store = RecipeStore(fileURL: fileURL)
                try store.replaceLibrary(with: RecipeLibrarySnapshot(recipes: recipes))

                let writeTimes = try measureWrites(
                    store: store,
                    recipe: recipes[0],
                    samples: writeSamples
                )
                let searchTimes = measureSearch(
                    recipes: recipes,
                    query: "benchmark dish \(count - 1)",
                    samples: searchSamples
                )
                let bytes = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0

                print(
                    "\(count) | \(hasCover ? "16 KiB each" : "none") | "
                        + "\(String(format: "%.2f", Double(bytes) / 1_048_576)) | "
                        + "\(format(percentile(0.50, in: writeTimes))) | "
                        + "\(format(percentile(0.95, in: writeTimes))) | "
                        + "\(format(percentile(0.50, in: searchTimes))) | "
                        + "\(format(percentile(0.95, in: searchTimes)))"
                )
            }
        }
        print("\nmacOS process benchmark; synthetic recipes; writes use RecipeStore.upsert.")
        print("Writes: 20 measured upserts after one warm-up; searches: 21 full scans per fixture.")
        print("Each search scans the full fixture with RecipeSearch.matches(includeSteps: true).")
        print("Cover fixture is \(coverBytes) bytes per recipe; this is not an Instruments profile.")
    }

    private static func fixture(count: Int, hasCover: Bool) -> [Recipe] {
        let template = SampleRecipes.recipes[0]
        let image = hasCover ? Data(repeating: 0xA5, count: coverBytes) : nil

        return (0..<count).map { index in
            var recipe = template
            recipe.id = UUID(uuidString: String(format: "B0000000-0000-4000-8000-%012X", index + 1))!
            recipe.title = "Benchmark dish \(index)"
            recipe.summary = "Synthetic recipe fixture \(index)"
            recipe.coverAsset = nil
            recipe.coverData = image
            return recipe
        }
    }

    @MainActor
    private static func measureWrites(
        store: RecipeStore,
        recipe original: Recipe,
        samples: Int
    ) throws -> [Double] {
        var times: [Double] = []
        for index in 0..<samples {
            var recipe = original
            recipe.isFavorite = index.isMultiple(of: 2)
            let start = DispatchTime.now().uptimeNanoseconds
            try store.upsert(recipe)
            let end = DispatchTime.now().uptimeNanoseconds
            if index > 0 {
                times.append(Double(end - start) / 1_000_000)
            }
        }
        return times
    }

    private static func measureSearch(
        recipes: [Recipe],
        query: String,
        samples: Int
    ) -> [Double] {
        var times: [Double] = []
        for _ in 0..<samples {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = recipes.filter { RecipeSearch.matches($0, query: query) }
            let end = DispatchTime.now().uptimeNanoseconds
            times.append(Double(end - start) / 1_000_000)
        }
        return times
    }

    private static func percentile(_ percentile: Double, in samples: [Double]) -> Double {
        let sorted = samples.sorted()
        let index = min(Int(ceil(percentile * Double(sorted.count))) - 1, sorted.count - 1)
        return sorted[index]
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
