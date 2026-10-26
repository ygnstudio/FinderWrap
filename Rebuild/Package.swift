// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FinderWrapRebuild",
    platforms: [.macOS(.v13)],
    products: [.library(name: "FinderBridge", targets: ["FinderBridge"])],
    targets: [
        .target(name: "FinderBridge"),
        .testTarget(name: "FinderBridgeTests", dependencies: ["FinderBridge"])
    ]
)
