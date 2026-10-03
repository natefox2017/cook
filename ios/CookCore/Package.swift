// swift-tools-version: 6.0
import PackageDescription

// Product deployment floor; application and extension signing are configured separately.
let package = Package(
    name: "CookCore",
    platforms: [.iOS(.v18)],
    products: [.library(name: "CookCore", targets: ["CookCore"])],
    targets: [
        .target(name: "CookCore"),
        .testTarget(name: "CookCoreTests", dependencies: ["CookCore"])
    ]
)
