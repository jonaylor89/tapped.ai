// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TappedUI",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "TappedUI", targets: ["TappedUI"]),
    ],
    dependencies: [
        .package(path: "../TappedDomain"),
        .package(url: "https://github.com/rive-app/rive-ios.git", exact: "6.27.0"),
    ],
    targets: [
        .target(
            name: "TappedUI",
            dependencies: [
                "TappedDomain",
                .product(name: "RiveRuntime", package: "rive-ios"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "TappedUITests", dependencies: ["TappedUI"]),
    ],
    swiftLanguageModes: [.v6]
)
