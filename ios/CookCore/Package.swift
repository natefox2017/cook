// swift-tools-version: 6.0
import PackageDescription

// Platform floors intentionally remain unset until the application target is approved.
let package = Package(
    name: "CookCore",
    products: [.library(name: "CookCore", targets: ["CookCore"])],
    targets: [
        .target(name: "CookCore"),
        .testTarget(name: "CookCoreTests", dependencies: ["CookCore"])
    ]
)
