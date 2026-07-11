// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ACorner",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ACorner", targets: ["ACorner"])
    ],
    targets: [
        .executableTarget(name: "ACorner"),
        .testTarget(name: "ACornerTests", dependencies: ["ACorner"])
    ]
)
