// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AfterlightCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AfterlightCore", targets: ["AfterlightCore"])
    ],
    targets: [
        .target(name: "AfterlightCore"),
        .testTarget(name: "AfterlightCoreTests", dependencies: ["AfterlightCore"])
    ]
)
