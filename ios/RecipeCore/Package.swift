// swift-tools-version: 6.0
import PackageDescription

// Product deployment floor; application and extension signing are configured separately.
let package = Package(
    name: "RecipeCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "RecipeCore", targets: ["RecipeCore"])],
    targets: [
        .target(name: "RecipeCore", path: "Sources/RecipeCore"),
        .testTarget(name: "RecipeCoreTests", dependencies: ["RecipeCore"], path: "Tests/RecipeCoreTests")
    ]
)
