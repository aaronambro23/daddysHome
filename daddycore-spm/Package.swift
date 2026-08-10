// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DaddyCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DaddyCore",
            targets: ["DaddyCore"]
        ),
        .executable(
            name: "daddy-cli",
            targets: ["DaddyCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "DaddyCore",
            dependencies: ["SwiftTerm"]
        ),
        .executableTarget(
            name: "DaddyCLI",
            dependencies: ["DaddyCore"]
        ),
        .testTarget(
            name: "DaddyCoreTests",
            dependencies: ["DaddyCore"]
        ),
    ]
)
