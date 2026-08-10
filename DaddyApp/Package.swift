// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DaddyApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "DaddyApp",
            targets: ["DaddyApp"]
        ),
    ],
    dependencies: [
        .package(path: "../daddycore-spm"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "DaddyApp",
            dependencies: [
                .product(name: "DaddyCore", package: "daddycore-spm"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
    ]
)
