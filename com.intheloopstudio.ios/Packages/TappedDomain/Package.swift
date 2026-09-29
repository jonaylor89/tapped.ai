// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TappedDomain",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "TappedDomain", targets: ["TappedDomain"]),
    ],
    targets: [
        .target(name: "TappedDomain"),
        .testTarget(
            name: "TappedDomainTests",
            dependencies: ["TappedDomain"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
