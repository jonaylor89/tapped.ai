// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TappedData",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "TappedData", targets: ["TappedData"]),
    ],
    dependencies: [
        .package(path: "../TappedDomain"),
        // Every remote dependency is pinned with `exact:`; Package.resolved is committed.
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", exact: "12.19.2"),
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", exact: "10.0.0"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", exact: "3.79.1"),
        .package(url: "https://github.com/GetStream/stream-chat-swift.git", exact: "5.9.0"),
    ],
    targets: [
        .target(
            name: "TappedData",
            dependencies: [
                "TappedDomain",
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseStorage", package: "firebase-ios-sdk"),
                .product(name: "FirebaseRemoteConfig", package: "firebase-ios-sdk"),
                .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk"),
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
                .product(name: "PostHog", package: "posthog-ios"),
                .product(name: "StreamChat", package: "stream-chat-swift"),
            ]
        ),
        .testTarget(name: "TappedDataTests", dependencies: ["TappedData"]),
    ],
    swiftLanguageModes: [.v6]
)
