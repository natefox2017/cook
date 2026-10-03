// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CookLocal", platforms: [.macOS(.v14)], targets: [
    .target(name: "CookLocal", path: "CookApp", exclude: ["AddRecipeView.swift", "CookApp.swift", "CookingView.swift", "GroceriesView.swift", "ProfileView.swift", "RecipeDetailView.swift", "RecipeEditorView.swift", "RecipeLibraryView.swift", "Theme.swift", "Localizable.xcstrings"], sources: ["Models.swift", "Store.swift", "TimerState.swift"]),
    .testTarget(name: "CookLocalTests", dependencies: ["CookLocal"], path: "CookAppTests/Tests")
])
